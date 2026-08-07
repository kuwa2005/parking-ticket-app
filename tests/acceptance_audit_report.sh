#!/usr/bin/env bash
# セキュリティ監査レポート.md デリバラブルの受入テスト（仕様: docs/compose/specs/2026-08-07-security-audit-report-spec.md §3）
# プロジェクトルートで実行: bash tests/acceptance_audit_report.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PASS=0; FAIL=0
ok() { echo "PASS $1"; PASS=$((PASS+1)); }
ng() { echo "FAIL $1 — $2"; FAIL=$((FAIL+1)); }

F="セキュリティ監査レポート.md"

# T1: ファイル存在・サイズ
if [ -f "$F" ] && [ "$(stat -c%s "$F")" -gt 1000 ]; then ok "T1 $F exists (>1000B)"; else ng "T1 $F" "size=$(stat -c%s "$F" 2>/dev/null)"; fi

# T2: 必須節
missing=""
for s in 総評 発見と対応 結論; do grep -q "$s" "$F" || missing="$missing $s"; done
[ -z "$missing" ] && ok "T2 必須節（総評/発見と対応/結論）あり" || ng "T2 必須節" "missing:$missing"

# T3: README リンク
grep -q 'セキュリティ監査レポート.md' README.md && ok "T3 README にリンクあり" || ng "T3 README リンク" "not found"

# T4: レポート内の相対リンク先が実在
miss=""
for t in docs/compose/reports/security-audit-2026-08-07.md \
         reports/2026-08-07-unit-test-results.txt \
         reports/2026-08-07-smoke-test-results.txt \
         reports/2026-08-07-e2e-ui-results.txt \
         reports/2026-08-07-docker-verification.txt; do
  [ -f "$t" ] || miss="$miss $t"
done
[ -z "$miss" ] && ok "T4 相対リンク先5ファイル実在" || ng "T4 リンク先" "missing:$miss"

# T5: コミット履歴
git log --oneline | grep -q '9127051 セキュリティ監査レポート.md' && ok "T5 コミット 9127051 存在" || ng "T5 コミット" "9127051 not in log"

# T6: push 済み（origin/main と同期）
st=$(git status -sb | head -1)
case "$st" in
  "## main...origin/main") ok "T6 origin/main と同期";;
  *) ng "T6 push 状態" "$st";;
esac

# T7: GitHub にファイルが存在（gh api）
out=$(gh api "repos/kuwa2005/parking-ticket-app/contents/$F" --jq '.name + " " + (.size|tostring)' 2>&1)
if printf '%s' "$out" | grep -q "^$F "; then ok "T7 gh api で存在確認（$out）"; else ng "T7 gh api" "$out"; fi

# T8: raw URL が 200
url=$(gh api "repos/kuwa2005/parking-ticket-app/contents/$F" --jq '.download_url' 2>/dev/null)
code=$(curl -s -o /dev/null -w '%{http_code}' "$url")
[ "$code" = "200" ] && ok "T8 raw URL 200" || ng "T8 raw URL" "code=$code"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
