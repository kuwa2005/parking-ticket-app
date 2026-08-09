#!/usr/bin/env bash
# GitHub Release の説明文を stdout に生成する（release.yml の --notes とローカル検証で共用）
# VERSION: 第 1 引数 / 未指定時は GITHUB_REF_NAME（例: v1.0.0）/ どちらもなければ local
set -eu

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  VERSION="${GITHUB_REF_NAME:-local}"
fi

cat <<EOF
parking-ticket-app $VERSION（MIT License・Copyright (c) 2026 kuwa2005）

レンタルサーバー（PHP + SQLite・汎用ホスティング）へのデプロイ一式 zip。

- 収録: index.php / admin.php / api.php / lib/config.php / lib/db.php / lib/store.php / data/.htaccess / scripts/seed_demo.php / README.md / LICENSE
- 配置: zip を展開してドキュメントルートへアップロード（data/ を書き込み可能に）

詳細: https://github.com/kuwa2005/parking-ticket-app#readme
デモ運用例: https://debugprint.com/parking/
EOF
