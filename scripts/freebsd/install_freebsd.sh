#!/bin/sh

set -e

### ===== CONFIG =====
GITHUB_USER="YOUR_USERNAME"
REPO_NAME="my-discovery-repo"
SERVICE_ID="123"
SSH_KEY_NAME="id_ed25519_discovery"
SSH_HOST_ALIAS="github-discovery"
REPO_DIR="$HOME/$REPO_NAME"
### ==================

echo "=== FreeBSD Discovery setup ==="

# 1. Ensure packages
echo "Installing required packages..."
pkg install -y git curl

# 2. SSH setup
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

# known_hosts
ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null || true
chmod 600 ~/.ssh/known_hosts

echo
echo "=== ADD THIS KEY TO GITHUB (Deploy Keys, WRITE) ==="
cat "${KEY_PATH}.pub"
echo "=================================================="
echo

# 3. Clone/init repo
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

git push || true

# 4. Create update script
SCRIPT_PATH="/usr/local/bin/update_ip.sh"

echo "Creating update_ip.sh..."

cat > "$SCRIPT_PATH" <<EOF
#!/bin/sh

REPO_DIR="$REPO_DIR"
SERVICE_ID="$SERVICE_ID"
FILE_PATH="services/\$SERVICE_ID/ip.txt"

IP=\$(fetch -qo - https://api.ipify.org)

[ -z "\$IP" ] && exit 1

cd "\$REPO_DIR" || exit 1

git pull --rebase

OLD_IP=\$(cat "\$FILE_PATH" 2>/dev/null || echo "")

if [ "\$IP" = "\$OLD_IP" ]; then
    exit 0
fi

echo "\$IP" > "\$FILE_PATH"

git add "\$FILE_PATH"
git commit -m "update IP to \$IP"
git push
EOF

chmod +x "$SCRIPT_PATH"

# 5. rc.d service
SERVICE_FILE="/usr/local/etc/rc.d/update_ip"

echo "Creating rc.d service..."

cat > "$SERVICE_FILE" <<'EOF'
#!/bin/sh

# PROVIDE: update_ip
# REQUIRE: NETWORKING
# KEYWORD: shutdown

. /etc/rc.subr

name="update_ip"
rcvar=update_ip_enable

command="/usr/local/bin/update_ip.sh"

load_rc_config $name

: ${update_ip_enable="NO"}

run_rc_command "$1"
EOF

chmod +x "$SERVICE_FILE"

# enable service
sysrc update_ip_enable=YES

# 6. cron job (every 5 minutes)
echo "Setting up cron..."

(crontab -l 2>/dev/null; echo "*/5 * * * * $SCRIPT_PATH") | crontab -

echo
echo "=== INSTALL COMPLETE ==="
echo "Run manually:"
echo "  service update_ip start"
echo
echo "Check cron:"
echo "  crontab -l"
