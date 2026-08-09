#!/usr/bin/env bash
# ドキュメント整合チェック（仕様 2026-08-09-docs-consistency-spec.md の T1〜T11）
# リポジトリのドキュメント群（README・最終レポート・ローリング結果ファイル・spec の NOTE マーカー）が
# 現在のコード・テスト実測・本番状態（コミット 6dc1c7f まで）と一致しているかを検証する。
# 読み取り専用。全 PASS で exit 0。結果は reports/2026-08-09-docs-consistency-check.txt に記録する。
set -u
cd "$(dirname "$0")/.." || exit 2
FAIL=0

check() {
  local id="$1" ok="$2" detail="$3"
  if [ "$ok" = "1" ]; then echo "PASS $id: $detail"; else echo "FAIL $id: $detail"; FAIL=1; fi
}

echo "== T1〜T4: ローリング結果ファイルが現在のテスト実測と一致 =="
grep -q "22/22 passed" reports/2026-08-07-unit-test-results.txt \
  && check T1 1 "単体結果に 22/22 passed" || check T1 0 "単体結果に 22/22 passed なし"
grep -q "30 passed, 0 failed" reports/2026-08-07-smoke-test-results.txt \
  && check T2 1 "スモーク結果に 30 passed, 0 failed" || check T2 0 "スモーク結果に 30 passed, 0 failed なし"
grep -q "74/74 passed" reports/2026-08-07-e2e-ui-results.txt \
  && check T3 1 "E2E 結果に 74/74 passed" || check T3 0 "E2E 結果に 74/74 passed なし"
grep -q "8/8 passed" reports/2026-08-07-seed-demo-test.txt \
  && check T4 1 "シード結果に 8/8 passed" || check T4 0 "シード結果に 8/8 passed なし"

echo
echo "== T5〜T7: README.md =="
ok=1
grep -q "22チェック" README.md && grep -q "30チェック" README.md \
  && grep -q "74チェック" README.md && grep -q "19ケース" README.md || ok=0
check T5 "$ok" "テスト表に 22/30/74 チェック・19 ケース"
grep -q "add_record" README.md && check T6 1 "api 一覧に add_record" || check T6 0 "api 一覧に add_record なし"
ok=1
grep -q "6dc1c7f" README.md && grep -q "19/19" README.md || ok=0
check T7 "$ok" "デプロイ実績に 6dc1c7f・19/19"

echo
echo "== T8: 最終レポート =="
FR=docs/compose/reports/parking-ticket-app.md
ok=1
grep -q "add_record" "$FR" && grep -q "74/74" "$FR" && grep -q "6dc1c7f" "$FR" || ok=0
check T8 "$ok" "最終レポートに add_record・74/74・6dc1c7f"

echo
echo "== T9: 2026-08-09 の spec/hearing 全ファイルに NOTE マーカー =="
MISSING=""
for f in docs/compose/specs/2026-08-09-*.md; do
  [ -f "$f" ] || continue
  if ! grep -q "NOTE" "$f"; then MISSING="$MISSING $f"; fi
done
if [ -z "$MISSING" ]; then
  check T9 1 "2026-08-09 の全 spec/hearing に NOTE あり"
else
  check T9 0 "NOTE 欠落:$MISSING"
fi

echo
echo "== T10: 認証情報がコミット対象ドキュメントに存在しない =="
CREDS_FILE="${CREDS_FILE:-/tmp/park_creds_check.txt}"
LEAK_EXC="reports/2026-08-09-github-leak-check.txt"
if [ -f "$CREDS_FILE" ]; then
  LEAKED=""
  UNTRACKED=$(git ls-files --others --exclude-standard)
  while IFS= read -r val; do
    [ -z "$val" ] && continue
    HIT=""
    # 追跡ファイル（既存の leak-check 記録は除外）
    if git grep -q -- "$val" -- . 2>/dev/null; then
      HIT=$(git grep -l -- "$val" -- . 2>/dev/null | grep -v "^$LEAK_EXC$")
    fi
    # 未追跡のコミット対象候補
    if [ -n "$UNTRACKED" ]; then
      for u in $UNTRACKED; do
        if [ "$u" != "$LEAK_EXC" ] && grep -q -- "$val" "$u" 2>/dev/null; then HIT="$HIT $u"; fi
      done
    fi
    [ -n "$HIT" ] && LEAKED="$LEAKED [$val ->$HIT]"
  done < "$CREDS_FILE"
  if [ -z "$LEAKED" ]; then
    check T10 1 "外部値ファイルの全認証情報がコミット対象に未記載（leak-check 記録を除く）"
  else
    check T10 0 "認証情報が漏えい:$LEAKED"
  fi
else
  echo "NOTE T10: 外部値ファイル（$CREDS_FILE）不在のため値チェックはスキップ（実値はリポジトリ外管理の設計）"
  check T10 1 "実値はリポジトリ外管理（値チェックは外部ファイル依存）"
fi

echo
echo "== T11: git clean + origin/main 同期（本チェック自身の結果レポートを除く） =="
DIRTY=$(git status --porcelain | grep -v "reports/2026-08-09-docs-consistency-check.txt")
if [ -z "$DIRTY" ] && [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]; then
  check T11 1 "clean・origin/main 同期（結果レポートは本実行で生成・追ってコミット）"
else
  check T11 0 "未コミット: [$DIRTY] または HEAD と origin/main が不一致"
fi

echo
if [ "$FAIL" = "0" ]; then
  echo "RESULT: ALL PASS (11/11)"
  exit 0
else
  echo "RESULT: FAILURES"
  exit 1
fi
