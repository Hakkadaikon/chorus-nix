#!/usr/bin/env bash
set -euo pipefail

# Chorus + Pfortner deploy script
# Usage: ./scripts/deploy.sh [--config-only]
#
# Options:
#   --config-only   設定ファイルのみ転送 (バイナリはスキップ)
#
# 環境変数:
#   VPS_HOST    VPS のホスト名 (default: tk2-202-10829.vs.sakura.ne.jp)
#   VPS_USER    SSH ユーザー名 (default: rocky)
#   SSH_KEY     SSH 秘密鍵パス (default: ~/.ssh/id_ed25519_sakura)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

VPS_HOST="${VPS_HOST:-tk2-202-10829.vs.sakura.ne.jp}"
VPS_USER="${VPS_USER:-rocky}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_sakura}"

SSH_CMD="ssh -i $SSH_KEY ${VPS_USER}@${VPS_HOST}"
SCP_CMD="scp -i $SSH_KEY"

CONFIG_ONLY=false
if [[ "${1:-}" == "--config-only" ]]; then
    CONFIG_ONLY=true
fi

echo "==> Deploying to ${VPS_USER}@${VPS_HOST}"

# --- Chorus binary ---
if [[ "$CONFIG_ONLY" == false ]]; then
    CHORUS_BIN="$REPO_DIR/chorus-bin/chorus"
    if [[ -f "$CHORUS_BIN" ]]; then
        echo "==> Transferring chorus binary..."
        $SCP_CMD "$CHORUS_BIN" "${VPS_USER}@${VPS_HOST}:/tmp/chorus"
        $SSH_CMD "sudo cp /tmp/chorus /opt/chorus/bin/chorus && sudo chmod 755 /opt/chorus/bin/chorus && sudo chown chorus:chorus /opt/chorus/bin/chorus && rm /tmp/chorus"
    else
        echo "    (skipped: $CHORUS_BIN not found. Run 'gh run download' first)"
    fi
fi

# --- Config files ---
echo "==> Transferring config files..."
$SCP_CMD \
    "$REPO_DIR/config/chorus.toml" \
    "$REPO_DIR/config/pfortner.yaml" \
    "$REPO_DIR/config/cloudflared.yml" \
    "$REPO_DIR/config/chorus.service" \
    "$REPO_DIR/config/pfortner.service" \
    "$REPO_DIR/config/cloudflared.service" \
    "${VPS_USER}@${VPS_HOST}:/tmp/"

echo "==> Installing config files on VPS..."
$SSH_CMD bash <<'REMOTE'
set -euo pipefail

# chorus
sudo cp /tmp/chorus.toml /opt/chorus/etc/chorus.toml
sudo chown chorus:chorus /opt/chorus/etc/chorus.toml

# pfortner
sudo cp /tmp/pfortner.yaml /opt/pfortner/etc/pfortner.yaml
sudo chown chorus:chorus /opt/pfortner/etc/pfortner.yaml

# cloudflared
sudo cp /tmp/cloudflared.yml /etc/cloudflared/config.yml

# systemd units
sudo cp /tmp/chorus.service /etc/systemd/system/chorus.service
sudo cp /tmp/pfortner.service /etc/systemd/system/pfortner.service
sudo cp /tmp/cloudflared.service /etc/systemd/system/cloudflared.service
sudo systemctl daemon-reload

# cleanup
rm -f /tmp/chorus.toml /tmp/pfortner.yaml /tmp/cloudflared.yml \
      /tmp/chorus.service /tmp/pfortner.service /tmp/cloudflared.service

# restart services
sudo systemctl restart chorus
sudo systemctl restart pfortner
sudo systemctl restart cloudflared

echo ""
echo "=== Service status ==="
sudo systemctl is-active chorus pfortner cloudflared
REMOTE

echo "==> Deploy complete!"
