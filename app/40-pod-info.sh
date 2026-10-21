#!/bin/sh
# Runs when the container starts (the NGINX image runs every script in /docker-entrypoint.d/).
# Writes the pod name, start time and version into the page, so every response shows which
# pod served it: you can watch load balancing, self-healing and rolling updates in the browser.
set -e
HTML=/usr/share/nginx/html/index.html
POD_NAME="${POD_NAME:-$(hostname)}"
STARTED="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

sed -i \
  -e "s/__POD_NAME__/${POD_NAME}/g" \
  -e "s/__STARTED__/${STARTED}/g" \
  -e "s/__APP_VERSION__/${APP_VERSION}/g" \
  "$HTML"

printf '{"pod":"%s","version":"%s","started":"%s"}\n' "$POD_NAME" "$APP_VERSION" "$STARTED" \
  > /usr/share/nginx/html/info.json
