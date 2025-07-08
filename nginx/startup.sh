#!/bin/sh
# nginx/startup.sh - Container startup script

echo "Starting OpenResty..."
/usr/local/openresty/bin/openresty -g "daemon off;" &
NGINX_PID=$!

echo "Waiting for nginx to start..."
sleep 5

echo "Initializing admin user..."
curl -s http://localhost/api/init > /dev/null 2>&1 || echo "Init call failed (this is normal if admin already exists)"

echo "Startup complete. Waiting for nginx process..."
wait $NGINX_PID