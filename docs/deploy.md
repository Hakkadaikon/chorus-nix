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

## 3. VPS の初期セットアップ

初回のみ必要な手順です。

### 前提条件

VPS 上で Cloudflare Tunnel を作成しておく必要があります (対話操作が必要なため手動):

```bash
ssh <USER>@<VPS_HOST>
sudo dnf install -y cloudflared
cloudflared tunnel login
cloudflared tunnel create <TUNNEL_NAME>
cloudflared tunnel route dns <TUNNEL_NAME> <RELAY_DOMAIN>
# 生成された認証情報が /etc/cloudflared/<TUNNEL_ID>.json に配置されていることを確認
```

### セットアップスクリプト

`scripts/setup.sh` で swap 作成、ユーザー作成、Deno/Pfortner/cloudflared のインストールをまとめて行います。

```bash
VPS_HOST=<VPS_HOST> VPS_USER=<USER> SSH_KEY=<SSH_KEY_PATH> \
./scripts/setup.sh
```

スクリプトが行う処理:

1. swap 1GB 作成 (既存の場合はスキップ)
2. unzip, git インストール
3. chorus ユーザー作成、ディレクトリ作成
4. Deno インストール
5. Pfortner クローン、依存関係キャッシュ
6. cloudflared インストール
7. systemd サービス有効化

セットアップ完了後、`./scripts/deploy.sh` で設定ファイルとバイナリをデプロイしてください。

### 設定上の注意

- `chorus_is_behind_a_proxy` は `false` にしてください。cloudflared は chorus が要求する `X-Real-Ip` ヘッダーを送信しないため、`true` にすると `RealIpHeaderMissing` エラーで起動に失敗します。
- cloudflared の `service` ポートは Pfortner の `3000` を指定してください (`8080` ではない)。

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
