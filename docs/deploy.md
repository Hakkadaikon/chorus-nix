# Chorus Nostr Relay デプロイ手順

Linux VPS に [Chorus](https://github.com/mikedilger/chorus) Nostr Relay をデプロイし、Cloudflare Tunnel 経由で公開する手順です。

## 構成

```
[クライアント] → wss://relay.example.com/
                  ↓ (Cloudflare Tunnel)
              [cloudflared] → http://127.0.0.1:8080
                  ↓
              [chorus]
```

- **VPS**: x86_64 Linux (RHEL 系 / Debian 系)
- **リレー**: [Chorus](https://github.com/mikedilger/chorus) (静的リンク musl バイナリ)
- **トンネル**: Cloudflare Tunnel (`cloudflared`)

## 1. バイナリのビルド

GitHub Actions でビルドします。低メモリ VPS では Rust のコンパイルが困難なため、CI でのビルドを推奨します。

### 手順

1. GitHub 上で Actions タブを開く → "Build chorus static binary"
2. "Run workflow" をクリックして実行
3. 完了後、Artifacts から `chorus-linux-x86_64-musl` をダウンロード

### CLI での操作

```bash
# ワークフロー実行
gh workflow run build.yml

# 最新の実行を確認
gh run list --limit 1

# アーティファクトをダウンロード
gh run download <RUN_ID> --name chorus-linux-x86_64-musl --dir ./chorus-bin
```

### chorus のバージョンを変更する場合

`.github/workflows/build.yml` の `ref` を更新してください:

```yaml
- name: Checkout chorus
  uses: actions/checkout@v4
  with:
    repository: mikedilger/chorus
    ref: <新しいコミットハッシュ>
```

## 2. VPS へのデプロイ

### バイナリの転送と配置

```bash
# ローカルから転送
scp ./chorus-bin/chorus <USER>@<VPS_HOST>:/tmp/chorus

# VPS 上で配置
sudo cp /tmp/chorus /opt/chorus/bin/chorus
sudo chmod 755 /opt/chorus/bin/chorus
sudo chown chorus:chorus /opt/chorus/bin/chorus
```

### サービスの再起動

```bash
sudo systemctl restart chorus
sudo systemctl status chorus
```

## 3. VPS の初期セットアップ (参考)

初回のみ必要な手順です。

### swap の追加 (低メモリ VPS の場合)

```bash
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
```

### chorus ユーザーとディレクトリ

```bash
sudo useradd -r -s /sbin/nologin chorus
sudo mkdir -p /opt/chorus/{bin,etc,var/chorus}
sudo chown -R chorus:chorus /opt/chorus/var
```

### chorus.toml

`/opt/chorus/etc/chorus.toml`:

```toml
data_directory = "/opt/chorus/var/chorus"
ip_address = "127.0.0.1"
port = 8080
hostname = "relay.example.com"
use_tls = false
chorus_is_behind_a_proxy = false
open_relay = false
verify_events = true
allow_scraping = false
```

> **注意**: `chorus_is_behind_a_proxy` は `false` にしてください。
> cloudflared は chorus が要求する `X-Real-Ip` ヘッダーを送信しないため、
> `true` にすると `RealIpHeaderMissing` エラーで起動に失敗します。
> nginx 等のリバースプロキシを間に挟む場合は `true` にして `X-Real-Ip` を付与してください。

### chorus systemd サービス

`/etc/systemd/system/chorus.service`:

```ini
[Unit]
Description=Chorus Nostr Relay
After=network.target

[Service]
Type=simple
User=chorus
Group=chorus
ExecStart=/opt/chorus/bin/chorus /opt/chorus/etc/chorus.toml
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable chorus
sudo systemctl start chorus
```

### Cloudflare Tunnel のセットアップ

```bash
# cloudflared のインストール (RHEL 系)
sudo dnf install -y cloudflared
# Debian 系の場合は公式ドキュメントを参照

# トンネルの作成 (初回のみ)
cloudflared tunnel login
cloudflared tunnel create <TUNNEL_NAME>

# DNS レコードの設定
cloudflared tunnel route dns <TUNNEL_NAME> relay.example.com
```

`/etc/cloudflared/config.yml`:

```yaml
tunnel: <TUNNEL_ID>
credentials-file: /etc/cloudflared/<TUNNEL_ID>.json

ingress:
  - hostname: relay.example.com
    service: http://127.0.0.1:8080
    originRequest:
      httpHostHeader: relay.example.com
  - service: http_status:404
```

`/etc/systemd/system/cloudflared.service`:

```ini
[Unit]
Description=cloudflared
After=network-online.target
Wants=network-online.target

[Service]
TimeoutStartSec=15
Type=notify
ExecStart=/usr/bin/cloudflared --no-autoupdate --config /etc/cloudflared/config.yml tunnel run
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable cloudflared
sudo systemctl start cloudflared
```

## 4. 動作確認

```bash
# WebSocket で接続テスト
echo '["REQ","test",{"limit":1}]' | websocat wss://relay.example.com/

# 期待されるレスポンス:
# ["AUTH","..."]
# ["EOSE","test"]
```

## ディレクトリ構成 (VPS)

```
/opt/chorus/
  bin/chorus          # バイナリ
  etc/chorus.toml     # 設定ファイル
  var/chorus/         # データディレクトリ (chorus:chorus)
/etc/cloudflared/
  config.yml          # cloudflared 設定
  <TUNNEL_ID>.json    # トンネル認証情報
```
