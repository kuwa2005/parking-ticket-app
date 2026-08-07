#!/usr/bin/env bash
# 本番デプロイ受入テスト（仕様: docs/compose/specs/2026-08-07-production-deploy-spec.md §3 T1-T10）
# 使用: PROD_PW=<本番管理PW> bash tests/production_check.sh <base_url>
# 注意: PROD_PW は出力に一切表示しない。
set -u
BASE="${1:?usage: PROD_PW=... bash tests/production_check.sh <base_url>}"
PW="${PROD_PW:?PROD_PW 環境変数が必要}"
JAR=$(mktemp /tmp/park_prod_cookies.XXXXXX)
OUT=$(mktemp /tmp/park_prod_out.XXXXXX)
PASS=0; FAIL=0
ok() { echo "PASS $1"; PASS=$((PASS+1)); }
ng() { echo "FAIL $1 — $2"; FAIL=$((FAIL+1)); }

# T1: index 200 + UI 文言
code=$(curl -sk --max-time 20 -o "$OUT" -w '%{http_code}' "$BASE/")
if [ "$code" = "200" ] && grep -q '駐車券' "$OUT"; then ok "T1 GET / → 200 + UI"; else ng "T1 GET /" "code=$code"; fi

# T2: today（未認証）→ デモデータ投入済みを前提に total≥5 を確認しベースライン T0 を取得
#     （2026-08-07 DEMO 化以降: 本番にはデモデータ 401件が投入済み。空DB前提の total=0 検証は廃止）
body=$(curl -sk --max-time 20 "$BASE/api.php?action=today")
T0=$(printf '%s' "$body" | sed -n 's/.*"total":\([0-9][0-9]*\).*/\1/p')
if [ -n "$T0" ] && [ "$T0" -ge 5 ]; then ok "T2 today → total=$T0（デモデータ投入済み）"; else ng "T2 today" "$body"; fi

# T3: add count=2（記録はPWなし・JSON body）→ 201 + id
resp=$(curl -sk --max-time 20 -X POST -H 'Content-Type: application/json' -d '{"count":2}' -w '\n%{http_code}' "$BASE/api.php?action=add")
b=$(printf '%s' "$resp" | head -1); c=$(printf '%s' "$resp" | tail -1)
ID=$(printf '%s' "$b" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
if [ "$c" = "201" ] && [ -n "$ID" ]; then ok "T3 add → 201 (id=$ID)"; else ng "T3 add" "code=$c body=$b"; fi

# T4: today → total = T0 + 2
body=$(curl -sk --max-time 20 "$BASE/api.php?action=today")
if printf '%s' "$body" | grep -q "\"total\":$((T0 + 2))"; then ok "T4 today → total $((T0 + 2))（T0+2）"; else ng "T4 today" "$body"; fi

# T5: login（正しいPW・JSON body）→ 200 ok:true
resp=$(curl -sk --max-time 20 -c "$JAR" -X POST -H 'Content-Type: application/json' --data "{\"pw\":\"$PW\"}" -w '\n%{http_code}' "$BASE/api.php?action=login")
b=$(printf '%s' "$resp" | head -1); c=$(printf '%s' "$resp" | tail -1)
if [ "$c" = "200" ] && printf '%s' "$b" | grep -q '"ok":true'; then ok "T5 login → 200"; else ng "T5 login" "code=$c body=$b"; fi

# T6: delete（認証済み・自レコードのみ）→ 204・today が T0 に復元
code=$(curl -sk --max-time 20 -b "$JAR" -X DELETE -o /dev/null -w '%{http_code}' "$BASE/api.php?action=delete&id=$ID")
body=$(curl -sk --max-time 20 "$BASE/api.php?action=today")
if [ "$code" = "204" ] && printf '%s' "$body" | grep -q "\"total\":$T0"; then ok "T6 delete → 204・total $T0 復元"; else ng "T6 delete" "code=$code today=$body"; fi

# T7: data/parking.db 直アクセス → 403/404
code=$(curl -sk --max-time 20 -o /dev/null -w '%{http_code}' "$BASE/data/parking.db")
if [ "$code" = "403" ] || [ "$code" = "404" ]; then ok "T7 /data/parking.db → $code"; else ng "T7 /data/parking.db" "code=$code (漏洩リスク)"; fi

# T8: 誤PWログイン → 401 + ≥1000ms（F1 スロットル）
t0=$(date +%s%N)
code=$(curl -sk --max-time 20 -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"pw":"0000"}' "$BASE/api.php?action=login")
ms=$(( ($(date +%s%N) - t0) / 1000000 ))
if [ "$code" = "401" ] && [ "$ms" -ge 1000 ]; then ok "T8 誤PW → 401（${ms}ms）"; else ng "T8 誤PW" "code=$code ms=$ms"; fi

# T9: F4 セキュリティヘッダ
hdr=$(curl -sk --max-time 20 -I "$BASE/")
if printf '%s' "$hdr" | grep -qi 'X-Content-Type-Options: nosniff' && printf '%s' "$hdr" | grep -qi 'X-Frame-Options: DENY'; then ok "T9 セキュリティヘッダあり"; else ng "T9 ヘッダ" "$(printf '%s' "$hdr" | grep -iE 'x-content|x-frame|referrer' | tr '\n' ' ')"; fi

# T10: probe.php / 一時スクリプトが残っていない（情報開示アーティファクトなし）
#     ※デプロイラウンドで probe.php は意図的に削除済み。PHP環境（8.5.2 + pdo_sqlite）は
#       デモデータ正規化時の一時トリガー出力（reports/2026-08-07-production-verify.txt）で確認済み。
code=$(curl -sk --max-time 20 -o /dev/null -w '%{http_code}' "$BASE/probe.php")
if [ "$code" = "403" ] || [ "$code" = "404" ]; then ok "T10 probe.php → $code（残存なし）"; else ng "T10 probe.php" "code=$code (情報開示リスク)"; fi

rm -f "$JAR" "$OUT"
echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
