# chorus-nix

[Chorus](https://github.com/mikedilger/chorus) Nostr Relay のビルド・デプロイ環境です。

GitHub Actions で `x86_64-unknown-linux-musl` 静的バイナリをビルドし、Linux VPS + Cloudflare Tunnel でホストします。

## ビルド

GitHub Actions の "Build chorus static binary" ワークフローを手動実行してください。

```bash
gh workflow run build.yml
```

## デプロイ

詳細な手順は [docs/deploy.md](docs/deploy.md) を参照してください。
