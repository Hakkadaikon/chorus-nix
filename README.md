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

GitHub Actions の "Build chorus static binary" ワークフローを手動実行してください。

```bash
gh workflow run build.yml
```

## 設定

- `config/pfortner.yaml` — Pfortner 設定 (kind フィルタリングルール)
- `config/pfortner.service` — Pfortner systemd ユニットファイル

## デプロイ

詳細な手順は [docs/deploy.md](docs/deploy.md) を参照してください。
