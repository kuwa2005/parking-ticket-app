#!/usr/bin/env bash
# SSH 遮断対応ノウハウ整理の検証（仕様 2026-08-09-ssh-block-knowledge-cleanup-spec.md の S1〜S4）
# 対象: プロジェクトメモリ + 証跡ドキュメント
set -u
MEMORY_DIR="$HOME/.local/share/oimo/memory/projects/569a0d3f-d772-41e4-b70d-9a6b47f82c9f"
M1="$MEMORY_DIR/MEMORY.md"
M2="$MEMORY_DIR/MEMORY-e2e-test-tooling.md"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
H_DOC="$REPO_DIR/docs/compose/specs/2026-08-09-ssh-block-knowledge-cleanup-hearing.md"
S_DOC="$REPO_DIR/docs/compose/specs/2026-08-09-ssh-block-knowledge-cleanup-spec.md"
FAIL=0

check() {
  local id="$1" ok="$2" detail="$3"
  if [ "$ok" = "1" ]; then echo "PASS $id: $detail"; else echo "FAIL $id: $detail"; FAIL=1; fi
}

echo "== 対象ファイル存在確認 =="
[ -f "$M1" ] && echo "M1 OK: $(basename "$M1")" || { echo "FAIL 前提: $M1 なし"; exit 2; }
[ -f "$M2" ] && echo "M2 OK: $(basename "$M2")" || { echo "FAIL 前提: $M2 なし"; exit 2; }

echo
echo "== S1: MEMORY.md に正しい知識（登録 URL + 2〜3 分）が存在 =="
L=$(grep -n "docomo2.com/ipaddress/b45" "$M1" | head -1 | cut -d: -f1)
if [ -n "$L" ] && grep -q "2〜3 分" "$M1"; then
  check S1 1 "MEMORY.md:$L に登録 URL・同ファイルに「2〜3 分」記載あり"
else
  check S1 0 "登録 URL または「2〜3 分」が見つからない"
fi

echo
echo "== S2: MEMORY-e2e-test-tooling.md に正しい知識が存在（複数ファイル整合） =="
L2=$(grep -n "docomo2.com/ipaddress/b45" "$M2" | head -1 | cut -d: -f1)
if [ -n "$L2" ]; then check S2 1 "MEMORY-e2e-test-tooling.md:$L2 に登録 URL あり"; else check S2 0 "登録 URL が見つからない"; fi

echo
echo "== S3: 誤診ベースのノウハウが除去されている =="
for f in "$M1" "$M2"; do
  # ①プローブ連発（ブロック延長仮説）
  if grep -q "プローブ連発" "$f"; then check S3 0 "$(basename "$f"): 「プローブ連発」が残存"; else check S3 1 "$(basename "$f"): 「プローブ連発」0 件"; fi
  # ②20 分間隔規律
  if grep -qE "20 ?分(以上 )?間隔" "$f"; then check S3 0 "$(basename "$f"): 「20 分間隔」が残存"; else check S3 1 "$(basename "$f"): 「20 分間隔」0 件"; fi
  # ③接続完全停止
  if grep -q "接続完全停止" "$f"; then check S3 0 "$(basename "$f"): 「接続完全停止」が残存"; else check S3 1 "$(basename "$f"): 「接続完全停止」0 件"; fi
  # ④DEMO 版誤診
  if grep -q "ユーザー直接改修の DEMO 版" "$f"; then check S3 0 "$(basename "$f"): 「ユーザー直接改修の DEMO 版」が残存"; else check S3 1 "$(basename "$f"): 「ユーザー直接改修の DEMO 版」0 件"; fi
  # ⑤サイズ比較が決定的という誤診
  if grep -q "サイズ比較" "$f" && grep -q "決定的" "$f"; then check S3 0 "$(basename "$f"): 「サイズ比較」×「決定的」が残存"; else check S3 1 "$(basename "$f"): 「サイズ比較×決定的」0 件"; fi
  # ⑥スロットリングされる（訂正文脈 誤診/廃止/登録制 を含む行は除外）
  HITS=$(grep "スロットリングされる" "$f" | grep -vE "誤診|廃止|登録制" | wc -l)
  if [ "$HITS" = "0" ]; then check S3 1 "$(basename "$f"): 「スロットリングされる」（訂正外）0 件"; else check S3 0 "$(basename "$f"): 「スロットリングされる」が $HITS 件残存"; fi
done

echo
echo "== S4: 証跡ドキュメントが存在し認証情報を含まない =="
if [ -f "$H_DOC" ] && [ -f "$S_DOC" ]; then check S4 1 "ヒアリングログ + 仕様が存在"; else check S4 0 "証跡ドキュメント不足（hearing/spec）"; fi
CREDS_FILE="${CREDS_FILE:-/tmp/park_creds_check.txt}"
if [ -f "$CREDS_FILE" ]; then
  LEAKED=""
  while IFS= read -r val; do
    [ -z "$val" ] && continue
    if grep -q -- "$val" "$H_DOC" "$S_DOC" 2>/dev/null; then LEAKED="$LEAKED $val"; fi
  done < "$CREDS_FILE"
  if [ -z "$LEAKED" ]; then check S4 1 "外部値ファイルの全認証情報が証跡ドキュメントに未記載"; else check S4 0 "認証情報が漏えい:$LEAKED"; fi
else
  echo "NOTE S4: 外部値ファイル（$CREDS_FILE）不在のため値チェックはスキップ（リポジトリに実値を埋め込まない設計）"
  check S4 1 "実値はリポジトリ外管理（値チェックは外部ファイル依存）"
fi

echo
if [ "$FAIL" = "0" ]; then echo "RESULT: ALL PASS"; exit 0; else echo "RESULT: FAILURES"; exit 1; fi
