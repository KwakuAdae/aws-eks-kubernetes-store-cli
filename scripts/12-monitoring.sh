#!/usr/bin/env bash
# Step 12: monitoring and troubleshooting: kubectl views, CloudWatch Container Insights metrics and logs,
# and a CloudWatch alarm that fires when store pods keep restarting.
source "$(dirname "$0")/config.sh"
set +e   # show everything, even if one view is not ready yet

step "Health at a glance"
kubectl get deployment,pods,service,hpa,pdb -n "$NAMESPACE"

step "kubectl top: live CPU and memory (from metrics-server)"
kubectl top nodes
kubectl top pods -n "$NAMESPACE"

step "Recent events in ${NAMESPACE} (the first place to look when something is wrong)"
kubectl get events -n "$NAMESPACE" --sort-by=.lastTimestamp | tail -15

step "Website logs from all pods (NGINX access log, last 5 lines each)"
kubectl logs -n "$NAMESPACE" -l app=kwaku-store --prefix --tail=5

step "CloudWatch log groups created by Container Insights"
aws logs describe-log-groups --log-group-name-prefix "/aws/containerinsights/${CLUSTER_NAME}/" \
  --query 'logGroups[].{logGroup:logGroupName, storedBytes:storedBytes}' --output table

step "Store pod logs in CloudWatch (last 15 minutes)"
START_MS=$(( ($(date +%s) - 900) * 1000 ))
aws logs filter-log-events --log-group-name "/aws/containerinsights/${CLUSTER_NAME}/application" \
  --start-time "$START_MS" --filter-pattern '"kwaku-store"' --max-items 5 \
  --query 'events[].message' --output text | cut -c1-200

step "Container Insights metrics for the store (CPU, memory, restarts; last 30 minutes)"
for metric in pod_cpu_utilization pod_memory_utilization pod_number_of_container_restarts; do
  VALUES="$(aws cloudwatch get-metric-statistics --namespace ContainerInsights --metric-name "$metric" \
    --dimensions "Name=ClusterName,Value=${CLUSTER_NAME}" "Name=Namespace,Value=${NAMESPACE}" "Name=PodName,Value=kwaku-store" \
    --start-time "$(date -u -d '-30 min' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-30M +%Y-%m-%dT%H:%M:%SZ)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --period 300 --statistics Maximum \
    --query 'sort_by(Datapoints, &Timestamp)[].Maximum' --output text)"
  printf '   %-34s %s\n' "$metric" "${VALUES:-no data yet (Container Insights needs a few minutes)}"
done

step "CloudWatch alarm: ${PROJECT}-pod-restarts (store pods restarted more than 3 times in 5 minutes)"
aws cloudwatch put-metric-alarm --alarm-name "${PROJECT}-pod-restarts" \
  --alarm-description "Kwaku store pods are restarting (crash loop?)" \
  --namespace ContainerInsights --metric-name pod_number_of_container_restarts \
  --dimensions "Name=ClusterName,Value=${CLUSTER_NAME}" "Name=Namespace,Value=${NAMESPACE}" "Name=PodName,Value=kwaku-store" \
  --statistic Maximum --period 300 --evaluation-periods 1 --threshold 3 \
  --comparison-operator GreaterThanThreshold --treat-missing-data notBreaching \
  --tags "Key=Project,Value=${PROJECT}"
aws cloudwatch describe-alarms --alarm-names "${PROJECT}-pod-restarts" \
  --query 'MetricAlarms[].{alarm:AlarmName, state:StateValue, metric:MetricName, threshold:Threshold}' --output table

echo ""
echo "📊 Container Insights dashboard:"
echo "   https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#container-insights:performance/EKS:Cluster?~(query~(controls~(CW*3a*3aEKS.cluster~(~'${CLUSTER_NAME}'))))"
echo ""
echo "✅ Monitoring in place. When you have taken your screenshots: ./scripts/99-cleanup.sh"
