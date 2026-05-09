# chorus-nix

[Chorus](https://github.com/mikedilger/chorus) Nostr Relay のビルド・デプロイ環境です。

GitHub Actions で `x86_64-unknown-linux-musl` 静的バイナリをビルドし、Sakura VPS + Cloudflare Tunnel でホストします。

## リレー URL

`wss://vim_relay.hakkadaikon.com/`

## ビルド

GitHub Actions の "Build chorus static binary" ワークフローを手動実行してください。

```bash
gh workflow run build.yml --repo Hakkadaikon/chorus-nix
```

## デプロイ

詳細な手順は [docs/deploy.md](docs/deploy.md) を参照してください。
