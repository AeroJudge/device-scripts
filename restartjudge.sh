#!/bin/bash

echo Restarting judge....
sudo systemctl restart judge.service

echo "Waiting for service to become healthy..."
HEALTH_URL="http://localhost:8080/actuator/health"
HEALTH_RETRIES=30
HEALTH_INTERVAL=5
HEALTHY=false
for i in $(seq 1 $HEALTH_RETRIES); do
    sleep $HEALTH_INTERVAL
    HTTP_STATUS=$(curl --silent --output /dev/null --write-out "%{http_code}" "$HEALTH_URL" 2>/dev/null)
    if [ "$HTTP_STATUS" = "200" ]; then
        echo "Health check passed (attempt $i/$HEALTH_RETRIES)"
        HEALTHY=true
        break
    fi
    echo "Health check attempt $i/$HEALTH_RETRIES â€” status: $HTTP_STATUS"
done
if [ "$HEALTHY" = true ]; then
    echo "Refreshing browser..."
    DISPLAY=:0 xdotool search --onlyvisible --class chromium key F5
else
   echo "Judge not healthy!"
fi