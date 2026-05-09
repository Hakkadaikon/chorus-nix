# chorus-nix

[Chorus](https://github.com/mikedilger/chorus) Nostr Relay のビルド・デプロイ環境です。

GitHub Actions で `x86_64-unknown-linux-musl` 静的バイナリをビルドし、
[Pfortner](https://github.com/ikuradon/Pfortner) による kind フィルタリングを経由して、
Linux VPS + Cloudflare Tunnel でホストします。

## 構成

```
cloudflared → Pfortner (:3000, kind フィルタ) → Chorus (:8080)
```

## ビルド

```bash
gh workflow run build.yml
gh run download <RUN_ID> --name chorus-linux-x86_64-musl --dir ./chorus-bin
```

## デプロイ

```bash
./scripts/deploy.sh             # バイナリ + 設定ファイルをデプロイ
./scripts/deploy.sh --config-only  # 設定ファイルのみデプロイ
```

## 設定ファイル

| ファイル | 配置先 (VPS) | 説明 |
|---------|-------------|------|
| `config/chorus.toml` | `/opt/chorus/etc/chorus.toml` | Chorus 設定 |
| `config/chorus.service` | `/etc/systemd/system/chorus.service` | Chorus systemd |
| `config/pfortner.yaml` | `/opt/pfortner/etc/pfortner.yaml` | Pfortner 設定 (kind フィルタ) |
| `config/pfortner.service` | `/etc/systemd/system/pfortner.service` | Pfortner systemd |
| `config/cloudflared.yml` | `/etc/cloudflared/config.yml` | Cloudflare Tunnel 設定 |
| `config/cloudflared.service` | `/etc/systemd/system/cloudflared.service` | cloudflared systemd |

詳細な手順は [docs/deploy.md](docs/deploy.md) を参照してください。
