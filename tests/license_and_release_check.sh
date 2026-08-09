#!/usr/bin/env bash
# ライセンス + リリースビルド整合チェック（spec 2026-08-09-mit-license-and-release-spec.md T1〜T7 + 2026-08-09-release-notes-friendly-spec.md T9〜T11 = 全 10 チェック・旧 T8 の git clean チェックは T11 へ移設）
# 読み取り専用（dist/ へのビルド生成のみ）・全 PASS で exit 0・結果は reports/ に記録。
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
echo "== T9: リリース説明文（scripts/release_notes.sh） =="
NOTES=$(bash scripts/release_notes.sh v1.0.0 2>/dev/null)
ok=1
LINES=$(printf '%s\n' "$NOTES" | wc -l)
BLANKS=$(printf '%s\n' "$NOTES" | grep -c '^$' || true)
printf '%s\n' "$NOTES" | grep -q '^parking-ticket-app v1.0.0' || ok=0
[ "$LINES" -ge 7 ] || ok=0
[ "$BLANKS" -ge 2 ] || ok=0
printf '%s\n' "$NOTES" | grep -q '^- 収録: .*LICENSE' || ok=0
printf '%s\n' "$NOTES" | grep -q 'github.com/kuwa2005/parking-ticket-app' || ok=0
check T9 "$ok" "release_notes.sh 出力: $LINES 行・空行 $BLANKS・収録箇条書き（10 ファイル）・README リンク"

echo
echo "== T10: release.yml が release_notes.sh を使用 =="
WF=.github/workflows/release.yml
ok=1
grep -q 'bash scripts/release_notes.sh' "$WF" || ok=0
grep -q -- '--notes "$(bash scripts/release_notes.sh)"' "$WF" || ok=0
python3 -c "import yaml; yaml.safe_load(open('$WF'))" 2>/dev/null || ok=0
check T10 "$ok" "release.yml が scripts/release_notes.sh 参照（--notes 生成）+ YAML パース"

echo
echo "== T11: git clean + origin/main 同期（本チェック自身の結果レポートを除く） =="
DIRTY=$(git status --porcelain | grep -v "reports/2026-08-09-mit-license-and-release-check.txt" | grep -v "reports/2026-08-09-release-notes-friendly-check.txt")
if [ -z "$DIRTY" ] && [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]; then
  check T11 1 "clean・origin/main 同期"
else
  check T11 0 "未コミット: [$DIRTY] または HEAD と origin/main が不一致"
fi

echo
if [ "$FAIL" = "0" ]; then
  echo "RESULT: ALL PASS (10/10)"
  exit 0
else
  echo "RESULT: FAILURES"
  exit 1
fi
