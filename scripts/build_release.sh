#!/usr/bin/env bash
# レンタルサーバーデプロイ一式の zip を生成する（GitHub Actions のリリースビルド用・ローカルでも決定論的に実行可能）
# 出力: dist/parking-ticket-app-<VERSION>.zip（収録 = デプロイ一式 8 ファイル + README.md + LICENSE）
# VERSION: 第 1 引数 / 未指定時は GITHUB_REF_NAME（例: v1.0.0）/ どちらもなければ local
set -eu
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  VERSION="${GITHUB_REF_NAME:-local}"
fi

TOP="parking-ticket-app-$VERSION"
FILES=(
  index.php
  admin.php
  api.php
  lib/config.php
  lib/db.php
  lib/store.php
  data/.htaccess
  scripts/seed_demo.php
  README.md
  LICENSE
)

for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "missing: $f" >&2
    exit 1
  fi
done

OUT="dist/parking-ticket-app-$VERSION.zip"
mkdir -p dist
python3 - "$OUT" "$TOP" "${FILES[@]}" <<'PY'
import sys, zipfile
out, top = sys.argv[1], sys.argv[2]
files = sys.argv[3:]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        z.write(f, f"{top}/{f}")
print(f"created {out} ({len(files)} files)")
PY
