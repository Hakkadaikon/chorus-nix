#!/usr/bin/env bash
set -euo pipefail

# Chorus + Pfortner deploy script
# Usage: ./scripts/deploy.sh [--config-only]
#
# Options:
#   --config-only   設定ファイルのみ転送 (バイナリはスキップ)
#
# 環境変数 (すべて必須):
#   VPS_HOST       VPS のホスト名
#   VPS_USER       SSH ユーザー名
#   SSH_KEY        SSH 秘密鍵パス
#   RELAY_DOMAIN   リレーのドメイン名
#   TUNNEL_ID      Cloudflare Tunnel ID

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

: "${VPS_HOST:?VPS_HOST is required}"
: "${VPS_USER:?VPS_USER is required}"
: "${SSH_KEY:?SSH_KEY is required}"
: "${RELAY_DOMAIN:?RELAY_DOMAIN is required}"
: "${TUNNEL_ID:?TUNNEL_ID is required}"

SSH_CMD="ssh -i $SSH_KEY ${VPS_USER}@${VPS_HOST}"
SCP_CMD="scp -i $SSH_KEY"

CONFIG_ONLY=false
if [[ "${1:-}" == "--config-only" ]]; then
    CONFIG_ONLY=true
fi

# --- Generate config from templates ---
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

for f in "$REPO_DIR"/config/*; do
    sed \
        -e "s/\${RELAY_DOMAIN}/${RELAY_DOMAIN}/g" \
        -e "s/\${TUNNEL_ID}/${TUNNEL_ID}/g" \
        "$f" > "$TMPDIR/$(basename "$f")"
done

echo "==> Deploying to ${VPS_USER}@${VPS_HOST} (domain: ${RELAY_DOMAIN})"

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
    "$TMPDIR/chorus.toml" \
    "$TMPDIR/pfortner.yaml" \
    "$TMPDIR/cloudflared.yml" \
    "$TMPDIR/chorus.service" \
    "$TMPDIR/pfortner.service" \
    "$TMPDIR/cloudflared.service" \
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
