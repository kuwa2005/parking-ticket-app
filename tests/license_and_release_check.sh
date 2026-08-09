#!/usr/bin/env bash
# ライセンス + リリースビルド整合チェック（spec 2026-08-09-mit-license-and-release-spec.md の T1〜T8）
# 読み取り専用（dist/ へのビルド生成のみ）・全 PASS で exit 0・結果は reports/2026-08-09-mit-license-and-release-check.txt に記録。
set -u
cd "$(dirname "$0")/.." || exit 2
FAIL=0

check() {
  local id="$1" ok="$2" detail="$3"
  if [ "$ok" = "1" ]; then echo "PASS $id: $detail"; else echo "FAIL $id: $detail"; FAIL=1; fi
}

echo "== T1〜T3: LICENSE / README =="
grep -q "MIT License" LICENSE \
  && check T1 1 "LICENSE 存在 + MIT License 記載" || check T1 0 "LICENSE に MIT License なし"
grep -q "Copyright (c) 2026 kuwa2005" LICENSE \
  && check T2 1 "Copyright (c) 2026 kuwa2005" || check T2 0 "著作権表記なし"
grep -q "MIT" README.md \
  && check T3 1 "README にライセンス節（MIT）" || check T3 0 "README に MIT 記載なし"

echo
echo "== T4〜T5: リリースビルド（scripts/build_release.sh） =="
rm -f dist/parking-ticket-app-local.zip
if bash scripts/build_release.sh > /tmp/park_build_release.log 2>&1; then
  check T4 1 "ビルド成功（dist/parking-ticket-app-local.zip 生成）"
else
  check T4 0 "ビルド失敗: $(cat /tmp/park_build_release.log)"
fi
python3 - <<'PY' dist/parking-ticket-app-local.zip
import sys, zipfile
path = sys.argv[1]
expected = [
    "parking-ticket-app-local/index.php",
    "parking-ticket-app-local/admin.php",
    "parking-ticket-app-local/api.php",
    "parking-ticket-app-local/lib/config.php",
    "parking-ticket-app-local/lib/db.php",
    "parking-ticket-app-local/lib/store.php",
    "parking-ticket-app-local/data/.htaccess",
    "parking-ticket-app-local/scripts/seed_demo.php",
    "parking-ticket-app-local/README.md",
    "parking-ticket-app-local/LICENSE",
]
try:
    names = zipfile.ZipFile(path).namelist()
except Exception as e:
    print(f"zip open error: {e}")
    sys.exit(1)
missing = [e for e in expected if e not in names]
extra = [n for n in names if n not in expected]
dbs = [n for n in names if ".db" in n]
if not missing and not extra and not dbs:
    print(f"zip contains {len(expected)} expected files, no .db")
    sys.exit(0)
print(f"missing={missing} extra={extra} db={dbs}")
sys.exit(1)
PY
[ $? -eq 0 ] && check T5 1 "zip 収録 10 ファイル一致・.db なし" || check T5 0 "zip 収録が期待と不一致（上記参照）"
rm -f /tmp/park_build_release.log

echo
echo "== T6: GitHub Actions ワークフロー =="
WF=.github/workflows/release.yml
ok=1
[ -f "$WF" ] || ok=0
grep -q "v\*" "$WF" || ok=0
grep -q "gh release create" "$WF" || ok=0
grep -q "contents: write" "$WF" || ok=0
grep -q "actions/checkout" "$WF" || ok=0
python3 -c "import yaml,sys; yaml.safe_load(open('$WF'))" 2>/dev/null || ok=0
check T6 "$ok" "release.yml 存在 + v* タグトリガー + gh release create + contents: write + YAML パース"

echo
echo "== T7: 認証情報がコミット対象ドキュメントに存在しない =="
CREDS_FILE="${CREDS_FILE:-/tmp/park_creds_check.txt}"
LEAK_EXC="reports/2026-08-09-github-leak-check.txt"
if [ -f "$CREDS_FILE" ]; then
  LEAKED=""
  UNTRACKED=$(git ls-files --others --exclude-standard)
  while IFS= read -r val; do
    [ -z "$val" ] && continue
    HIT=""
    if git grep -q -- "$val" -- . 2>/dev/null; then
      HIT=$(git grep -l -- "$val" -- . 2>/dev/null | grep -v "^$LEAK_EXC$")
    fi
    if [ -n "$UNTRACKED" ]; then
      for u in $UNTRACKED; do
        if [ "$u" != "$LEAK_EXC" ] && grep -q -- "$val" "$u" 2>/dev/null; then HIT="$HIT $u"; fi
      done
    fi
    [ -n "$HIT" ] && LEAKED="$LEAKED [$val ->$HIT]"
  done < "$CREDS_FILE"
  if [ -z "$LEAKED" ]; then
    check T7 1 "外部値ファイルの全認証情報がコミット対象に未記載（leak-check 記録を除く）"
  else
    check T7 0 "認証情報が漏えい:$LEAKED"
  fi
else
  check T7 0 "外部値ファイル（$CREDS_FILE）不在 — 値チェック不可"
fi

echo
echo "== T8: git clean + origin/main 同期（本チェック自身の結果レポートを除く） =="
DIRTY=$(git status --porcelain | grep -v "reports/2026-08-09-mit-license-and-release-check.txt")
if [ -z "$DIRTY" ] && [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]; then
  check T8 1 "clean・origin/main 同期"
else
  check T8 0 "未コミット: [$DIRTY] または HEAD と origin/main が不一致"
fi

echo
if [ "$FAIL" = "0" ]; then
  echo "RESULT: ALL PASS (8/8)"
  exit 0
else
  echo "RESULT: FAILURES"
  exit 1
fi
