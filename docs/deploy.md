# Chorus Nostr Relay デプロイ手順

Linux VPS に [Chorus](https://github.com/mikedilger/chorus) Nostr Relay をデプロイし、
[Pfortner](https://github.com/ikuradon/Pfortner) で kind フィルタリングを行い、
Cloudflare Tunnel 経由で公開する手順です。

## 構成

```
[クライアント] → wss://relay.example.com/
                  ↓ (Cloudflare Tunnel)
              [cloudflared] → http://127.0.0.1:3000
                  ↓
              [Pfortner]    (kind フィルタリング)
                  ↓
              [chorus]      (127.0.0.1:8080)
```

- **VPS**: x86_64 Linux (RHEL 系 / Debian 系)
- **リレー**: [Chorus](https://github.com/mikedilger/chorus) (静的リンク musl バイナリ)
- **プロキシ**: [Pfortner](https://github.com/ikuradon/Pfortner) (Deno, kind フィルタリング)
- **トンネル**: Cloudflare Tunnel (`cloudflared`)

## リポジトリのファイル構成

```
config/
  chorus.toml           # Chorus 設定
  chorus.service        # Chorus systemd ユニット
  pfortner.yaml         # Pfortner 設定 (kind フィルタリングルール)
  pfortner.service      # Pfortner systemd ユニット
  cloudflared.yml       # Cloudflare Tunnel 設定
  cloudflared.service   # cloudflared systemd ユニット
scripts/
  deploy.sh             # VPS へのデプロイスクリプト
```

## 1. Chorus バイナリのビルド

GitHub Actions でビルドします。低メモリ VPS では Rust のコンパイルが困難なため、CI でのビルドを推奨します。

```bash
# ワークフロー実行
gh workflow run build.yml

# 最新の実行を確認
gh run list --limit 1

# アーティファクトをダウンロード (リポジトリルートの chorus-bin/ に配置)
gh run download <RUN_ID> --name chorus-linux-x86_64-musl --dir ./chorus-bin
```

### chorus のバージョンを変更する場合

`.github/workflows/build.yml` の `ref` を更新してください。

## 2. VPS へのデプロイ

### デプロイスクリプト

`scripts/deploy.sh` で設定ファイルの転送、サービスの再起動をまとめて行えます。

```bash
# バイナリ + 全設定ファイルをデプロイ
./scripts/deploy.sh

# 設定ファイルのみデプロイ (バイナリはスキップ)
./scripts/deploy.sh --config-only
```

環境変数で接続先を指定します (すべて必須):

```bash
VPS_HOST=<VPS_HOST> \
VPS_USER=<USER> \
SSH_KEY=<SSH_KEY_PATH> \
RELAY_DOMAIN=<RELAY_DOMAIN> \
TUNNEL_ID=<TUNNEL_ID> \
./scripts/deploy.sh
```

`config/` 内のテンプレート (`${RELAY_DOMAIN}`, `${TUNNEL_ID}`) はスクリプト実行時に環境変数の値で置換されます。

スクリプトが行う処理:

1. `chorus-bin/chorus` を VPS に転送・配置 (`--config-only` でスキップ)
2. `config/` 内の全設定ファイルを VPS に転送・配置
3. systemd ユニットを更新し `daemon-reload`
4. chorus, pfortner, cloudflared を再起動

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

### Chorus の設定

設定ファイルは `config/chorus.toml` で管理しています。

> **注意**: `chorus_is_behind_a_proxy` は `false` にしてください。
> cloudflared は chorus が要求する `X-Real-Ip` ヘッダーを送信しないため、
> `true` にすると `RealIpHeaderMissing` エラーで起動に失敗します。
> nginx 等のリバースプロキシを間に挟む場合は `true` にして `X-Real-Ip` を付与してください。

### Deno のインストール

```bash
sudo dnf install -y unzip  # RHEL 系の場合
curl -fsSL https://deno.land/install.sh | sh
sudo cp ~/.deno/bin/deno /usr/bin/deno
```

### Pfortner のセットアップ

```bash
sudo mkdir -p /opt/pfortner/{repo,etc,cache}
sudo git clone https://github.com/ikuradon/Pfortner /opt/pfortner/repo
sudo DENO_DIR=/opt/pfortner/cache deno cache /opt/pfortner/repo/scripts/serve.ts
sudo chown -R chorus:chorus /opt/pfortner
```

### Cloudflare Tunnel のセットアップ

```bash
sudo dnf install -y cloudflared  # RHEL 系
cloudflared tunnel login
cloudflared tunnel create <TUNNEL_NAME>
cloudflared tunnel route dns <TUNNEL_NAME> relay.example.com
```

設定ファイルは `config/cloudflared.yml` で管理しています。
トンネル認証情報 (`<TUNNEL_ID>.json`) は VPS の `/etc/cloudflared/` に配置してください。

> **注意**: `service` のポートは Pfortner の `3000` を指定してください (`8080` ではない)。

### サービスの初回登録

```bash
# deploy.sh で設定ファイルを配置後
sudo systemctl daemon-reload
sudo systemctl enable chorus pfortner cloudflared
sudo systemctl start chorus pfortner cloudflared
```

## 4. 動作確認

```bash
# WebSocket で接続テスト
echo '["REQ","test",{"limit":1}]' | websocat wss://relay.example.com/

# 期待されるレスポンス:
# ["AUTH","..."]
# ["EOSE","test"]
```

## 5. Kind フィルタリング設定

`config/pfortner.yaml` の `kind-filter` ポリシーで許可する kind を管理しています。

現在の許可リスト:

| Kind | 説明 |
|------|------|
| 0 | ユーザーメタデータ |
| 5 | イベント削除 |
| 7 | リアクション |
| 40 | チャンネル作成 |
| 42 | チャンネルメッセージ |
| 10002 | リレーリストメタデータ |
| 27235 | HTTP 認証イベント |

許可する kind を変更するには `config/pfortner.yaml` を編集し、`./scripts/deploy.sh --config-only` で反映してください。

## ディレクトリ構成 (VPS)

```
/opt/chorus/
  bin/chorus            # Chorus バイナリ
  etc/chorus.toml       # Chorus 設定ファイル
  var/chorus/           # データディレクトリ (chorus:chorus)
/opt/pfortner/
  repo/                 # Pfortner リポジトリ (git clone)
  etc/pfortner.yaml     # Pfortner 設定ファイル
  cache/                # Deno キャッシュ
/etc/cloudflared/
  config.yml            # cloudflared 設定 (→ :3000)
  <TUNNEL_ID>.json      # トンネル認証情報
```
