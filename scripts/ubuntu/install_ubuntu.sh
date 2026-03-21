#!/bin/bash

set -e

### ===== CONFIG (CHANGE THESE) =====
GITHUB_USER="YOUR_USERNAME"
REPO_NAME="my-discovery-repo"
SERVICE_ID="123"
SSH_KEY_NAME="id_ed25519_discovery"
SSH_HOST_ALIAS="github-discovery"
REPO_DIR="$HOME/$REPO_NAME"
SYSTEMD_USER="$USER"
### =================================

echo "=== Discovery FULL setup started ==="

# 1. SSH setup
mkdir -p ~/.ssh
chmod 700 ~/.ssh

KEY_PATH="$HOME/.ssh/$SSH_KEY_NAME"

if [ -f "$KEY_PATH" ]; then
    echo "SSH key exists: $KEY_PATH"
else
    echo "Generating SSH key..."
    ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "discovery-key"
fi

SSH_CONFIG="$HOME/.ssh/config"

if [ ! -f "$SSH_CONFIG" ]; then
    touch "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
fi

if ! grep -q "Host $SSH_HOST_ALIAS" "$SSH_CONFIG"; then
    echo "Adding SSH config entry..."
    cat >> "$SSH_CONFIG" <<EOF

Host $SSH_HOST_ALIAS
    HostName github.com
    User git
    IdentityFile $KEY_PATH
    IdentitiesOnly yes
EOF
fi

echo
echo "=== ADD THIS KEY TO GITHUB (Deploy Keys, WRITE) ==="
cat "${KEY_PATH}.pub"
echo "=================================================="
echo

# 2. Clone/init repo
if [ -d "$REPO_DIR/.git" ]; then
    echo "Repo exists"
else
    git clone "git@$SSH_HOST_ALIAS:$GITHUB_USER/$REPO_NAME.git" "$REPO_DIR" || {
        mkdir -p "$REPO_DIR"
        cd "$REPO_DIR"
        git init
        git remote add origin "git@$SSH_HOST_ALIAS:$GITHUB_USER/$REPO_NAME.git"
    }
fi

cd "$REPO_DIR"
git remote set-url origin "git@$SSH_HOST_ALIAS:$GITHUB_USER/$REPO_NAME.git"

SERVICE_DIR="services/$SERVICE_ID"
mkdir -p "$SERVICE_DIR"

IP_FILE="$SERVICE_DIR/ip.txt"

if [ ! -f "$IP_FILE" ]; then
    echo "0.0.0.0" > "$IP_FILE"
    git add "$IP_FILE"
    git commit -m "init service $SERVICE_ID" || true
fi

git push -u origin master || true

# 3. Create update script
SCRIPT_PATH="/usr/local/bin/update_ip.sh"

echo "Creating update_ip.sh..."

sudo tee "$SCRIPT_PATH" > /dev/null <<EOF
#!/bin/bash

set -e

REPO_DIR="$REPO_DIR"
SERVICE_ID="$SERVICE_ID"
FILE_PATH="services/\$SERVICE_ID/ip.txt"

IP=\$(curl -s https://api.ipify.org)

if [ -z "\$IP" ]; then
  echo "Failed to get IP"
  exit 1
fi

cd "\$REPO_DIR"

git pull --rebase

OLD_IP=\$(cat "\$FILE_PATH" 2>/dev/null || echo "")

if [ "\$IP" = "\$OLD_IP" ]; then
  echo "IP not changed: \$IP"
  exit 0
fi

echo "\$IP" > "\$FILE_PATH"

git add "\$FILE_PATH"
git commit -m "update IP to \$IP"
git push

echo "Updated IP to \$IP"
EOF

sudo chmod +x "$SCRIPT_PATH"

# 4. Create systemd service
SERVICE_FILE="/etc/systemd/system/update-ip.service"

echo "Creating systemd service..."

sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Update public IP to GitHub
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$SYSTEMD_USER
ExecStart=$SCRIPT_PATH

[Install]
WantedBy=multi-user.target
EOF

# 5. Create systemd timer
TIMER_FILE="/etc/systemd/system/update-ip.timer"

echo "Creating systemd timer..."

sudo tee "$TIMER_FILE" > /dev/null <<EOF
[Unit]
Description=Run update-ip every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Unit=update-ip.service

[Install]
WantedBy=timers.target
EOF

# 6. Enable services
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable update-ip.service
sudo systemctl enable update-ip.timer
sudo systemctl start update-ip.timer

echo
echo "=== INSTALL COMPLETE ==="
echo "Check status:"
echo "  systemctl status update-ip.service"
echo "  systemctl status update-ip.timer"
echo
echo "Manual run:"
echo "  sudo systemctl start update-ip.service"
echo
echo "Repo:"
echo "  $REPO_DIR"
