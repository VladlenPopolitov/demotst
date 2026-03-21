#!/bin/bash

set -e

### ===== CONFIG =====
REPO_DIR="$HOME/my-discovery-repo"
SERVICE_ID="123"
SOCKS_PORT="1080"
SSH_USER="ubuntu"   # пользователь на сервере
### ==================

FILE_PATH="services/$SERVICE_ID/ip.txt"

cd "$REPO_DIR"

echo "Updating repository..."
git pull --rebase

if [ ! -f "$FILE_PATH" ]; then
  echo "IP file not found: $FILE_PATH"
  exit 1
fi

IP=$(cat "$FILE_PATH")

if [ -z "$IP" ]; then
  echo "Empty IP"
  exit 1
fi

echo "Server IP: $IP"

# Kill existing proxy if running
if lsof -i :$SOCKS_PORT >/dev/null 2>&1; then
  echo "Stopping existing proxy on port $SOCKS_PORT"
  pkill -f "ssh -D $SOCKS_PORT" || true
  sleep 1
fi

echo "Starting SOCKS proxy on port $SOCKS_PORT..."

ssh -N -D 127.0.0.1:$SOCKS_PORT \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=60 \
    -o ServerAliveCountMax=3 \
    "$SSH_USER@$IP" &

echo "SOCKS proxy started on 127.0.0.1:$SOCKS_PORT"
