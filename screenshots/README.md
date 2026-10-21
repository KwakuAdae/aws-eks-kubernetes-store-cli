# Screenshots

Save your own evidence here while you run the project, for example:

| File | What to capture | Step |
|------|-----------------|------|
| `eks-cluster.png` | EKS console: cluster `kwaku-store-eks` ACTIVE, Auto Mode enabled | 3 |
| `ecr-image.png` | ECR console: `kwaku-store-k8s` with tags 1.0 and 2.0 and the scan result | 6 |
| `kubectl-get-all.png` | `kubectl get deployment,pods,service,hpa -n kwaku-store -o wide` | 7 |
| `website-v1.png` | The store in the browser, with the pod name panel | 8 |
| `self-healing.png` | The end of `09-test-self-healing.sh`: recovery times and availability % | 9 |
| `autoscaling.png` | `10-test-autoscaling.sh` showing pods 3 → 6+ → 3 | 10 |
| `rolling-update.png` | `kubectl rollout history` and the version 2.0 page | 11 |
| `container-insights.png` | CloudWatch → Container Insights dashboard for the cluster | 12 |
| `cleanup.png` | The end of `99-cleanup.sh` | 13 |

Crop out account IDs and anything sensitive before committing.
