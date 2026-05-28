#!/usr/bin/env bash
set -euo pipefail
# ── args ────────────────────────────────────────────────────────────────────
TARGET_MDNS="${1:?Usage: $0 <target-mDNS-name-or-IP> <ssh-user>}"
SSH_USER="${2:?Usage: $0 <target-mDNS-name-or-IP> <ssh-user>}"
# ── Detect input type ────────────────────────────────────────────────────────
if [[ "$TARGET_MDNS" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    INPUT_TYPE="ip"
else
    INPUT_TYPE="mdns"
fi
# Strip .local if provided; we'll add it consistently
if [[ "$INPUT_TYPE" == "ip" ]]; then
    TARGET_HOST="$TARGET_MDNS"
else
    TARGET_HOST="${TARGET_MDNS%.local}.local"
fi
SOURCE_HOST="$(hostname -s)"
echo "==> Target : $SSH_USER@$TARGET_HOST"
echo "==> Source : $SOURCE_HOST"
# ── Step 1: reachability ─────────────────────────────────────────────────────
echo ""
if [[ "$INPUT_TYPE" == "ip" ]]; then
    echo "[1/5] Checking IP reachability..."
else
    echo "[1/5] Checking mDNS reachability..."
fi
if ! ping -c 2 -W 3 "$TARGET_HOST" &>/dev/null; then
    echo "✗ '$TARGET_HOST' is not reachable. Exiting."
    exit 1
fi
echo "✓ '$TARGET_HOST' is reachable."
# ── Step 2: Test existing SSH connection ─────────────────────────────────────
echo ""
echo "[2/5] Testing existing SSH connection..."
if ssh -o BatchMode=yes \
       -o ConnectTimeout=5 \
       -o StrictHostKeyChecking=accept-new \
       "$SSH_USER@$TARGET_HOST" exit 2>/dev/null; then
    echo "✓ SSH connection successful. No new key needed."
    exit 0
fi
echo "✗ SSH connection failed with existing keys."
# ── Step 3: Prompt to create a new SSH key ───────────────────────────────────
echo ""
read -r -p "Do you want to establish a new SSH key for $SSH_USER@$TARGET_HOST? [y/N] " REPLY
echo ""
case "$REPLY" in
    [yY][eE][sS]|[yY])
        echo "✓ Proceeding with key generation."
        ;;
    *)
        echo "Exiting without changes."
        exit 0
        ;;
esac
# ── Step 4: Generate SSH key ─────────────────────────────────────────────────
echo "[3/5] Generating SSH key..."
if [[ "$INPUT_TYPE" == "ip" ]]; then
    KEY_NAME="${SOURCE_HOST}_${TARGET_HOST//./_}"
else
    KEY_NAME="${SOURCE_HOST}_${TARGET_HOST%.local}"
fi
KEY_PATH="$HOME/.ssh/$KEY_NAME"
if [[ -f "$KEY_PATH" ]]; then
    echo "  ! Key '$KEY_PATH' already exists. Skipping generation."
else
    ssh-keygen -t ed25519 -f "$KEY_PATH" -C "$KEY_NAME" -N ""
    echo "✓ Key generated at '$KEY_PATH'."
fi
# ── Step 5: Update SSH config ────────────────────────────────────────────────
echo ""
echo "[4/5] Updating SSH config..."
SSH_CONFIG="$HOME/.ssh/config"
CONFIG_BLOCK="
Host $TARGET_HOST
    User $SSH_USER
    IdentityFile $KEY_PATH
    IdentitiesOnly yes
"
if grep -q "Host $TARGET_HOST" "$SSH_CONFIG" 2>/dev/null; then
    EXISTING_KEY="$(awk "/Host $TARGET_HOST/{found=1} found && /IdentityFile/{print \$2; exit}" "$SSH_CONFIG")"
    if [[ "$EXISTING_KEY" == "$KEY_PATH" ]]; then
        echo "  ! Entry for '$TARGET_HOST' already exists in $SSH_CONFIG with correct key. Skipping."
    else
        echo "  ! Entry for '$TARGET_HOST' exists but points to a different key: $EXISTING_KEY"
        read -r -p "    Update IdentityFile to '$KEY_PATH'? [y/N] " KEY_REPLY
        echo ""
        if [[ "$KEY_REPLY" =~ ^[yY]([eE][sS])?$ ]]; then
            sed -i "s|IdentityFile $EXISTING_KEY|IdentityFile $KEY_PATH|" "$SSH_CONFIG"
            echo "✓ SSH config updated to use '$KEY_PATH'."
        else
            echo "  ! Leaving SSH config unchanged. You may be prompted for a password."
        fi
    fi
else
    echo "$CONFIG_BLOCK" >> "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
    echo "✓ SSH config updated."
fi
# ── Step 6: Deploy key to Dropbear target ────────────────────────────────────
echo ""
echo "[5/5] Deploying public key to $SSH_USER@$TARGET_HOST..."
# Remove any stale known_hosts entry before connecting
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$TARGET_HOST" 2>/dev/null || true
DROPBEAR_AUTH_KEYS="/home/$SSH_USER/.ssh/authorized_keys"
# Dropbear commonly uses /etc/dropbear for root
if [[ "$SSH_USER" == "root" ]]; then
    DROPBEAR_AUTH_KEYS="/etc/dropbear/authorized_keys"
fi
PUB_KEY="$(cat "$KEY_PATH.pub")"
ssh -o StrictHostKeyChecking=accept-new \
    "$SSH_USER@$TARGET_HOST" \
    "mkdir -p $(dirname $DROPBEAR_AUTH_KEYS) && \
     chmod 700 $(dirname $DROPBEAR_AUTH_KEYS) && \
     echo '$PUB_KEY' >> $DROPBEAR_AUTH_KEYS && \
     chmod 600 $DROPBEAR_AUTH_KEYS"
echo "✓ Public key deployed."
# ── Step 7: Verify new key connection ────────────────────────────────────────
echo ""
echo "Verifying new SSH key connection..."
if ssh -i "$KEY_PATH" \
       -o BatchMode=yes \
       -o ConnectTimeout=5 \
       -o IdentitiesOnly=yes \
       "$SSH_USER@$TARGET_HOST" exit 2>/dev/null; then
    echo "✓ New SSH key verified successfully."
else
    echo "✗ Verification failed. Check Dropbear logs on the target."
    exit 1
fi