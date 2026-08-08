#!/usr/bin/env bash
# 本番デプロイ受入テスト（仕様: docs/compose/specs/2026-08-07-admin-page-and-browsing-spec.md R7.4）
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

# T2: today（未認証）→ 数値 total を取得しベースライン T0 を確定
#     ※デモデータは 2026-06-01〜08-07 の固定スナップショットのため、実日付が 08-07 を過ぎると
#       今日は 0 件（正常）。デモデータ存在確認は T11（count≥400）が担う。T4/T6 は T0 相対。
body=$(curl -sk --max-time 20 "$BASE/api.php?action=today")
T0=$(printf '%s' "$body" | sed -n 's/.*"total":\([0-9][0-9]*\).*/\1/p')
if [ -n "$T0" ]; then ok "T2 today → total=$T0（ベースライン）"; else ng "T2 today" "$body"; fi

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

# T11: version → 200 + count≥400（デモデータ401件前提）・maxId≥1（認証不要）
ver=$(curl -sk --max-time 20 "$BASE/api.php?action=version")
vc=$(printf '%s' "$ver" | sed -n 's/.*"count":\([0-9][0-9]*\).*/\1/p')
vm=$(printf '%s' "$ver" | sed -n 's/.*"maxId":\([0-9][0-9]*\).*/\1/p')
if [ -n "$vc" ] && [ "$vc" -ge 400 ] && [ -n "$vm" ] && [ "$vm" -ge 1 ]; then ok "T11 version → count=$vc maxId=$vm"; else ng "T11 version" "$ver"; fi

# T12: day 未認証 → 200（公開化・Q42: メインの過去閲覧のため）
code=$(curl -sk --max-time 20 -o /dev/null -w '%{http_code}' "$BASE/api.php?action=day&date=2026-06-01")
if [ "$code" = "200" ]; then ok "T12 day no-auth → 200（公開化）"; else ng "T12 day no-auth" "code=$code"; fi

# T13: day（2026-06-01・デモデータ日）→ 200 + 5〜10件
body=$(curl -sk --max-time 20 -b "$JAR" "$BASE/api.php?action=day&date=2026-06-01")
n=$(printf '%s' "$body" | grep -o '"id":' | wc -l)
if printf '%s' "$body" | grep -q '"date":"2026-06-01"' && [ "$n" -ge 5 ] && [ "$n" -le 10 ]; then ok "T13 day 2026-06-01 → 200（$n 件）"; else ng "T13 day" "$body"; fi

# T14: admin.php → 200（未認証でも HTML は 200・データ API は 401 で保護）
code=$(curl -sk --max-time 20 -o "$OUT" -w '%{http_code}' "$BASE/admin.php")
if [ "$code" = "200" ] && grep -q '管理者画面' "$OUT"; then ok "T14 admin.php → 200 + UI"; else ng "T14 admin.php" "code=$code"; fi

# T15: update 未認証 → 401（データ操作 API は保護）
code=$(curl -sk --max-time 20 -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"id":1,"count":2}' "$BASE/api.php?action=update")
if [ "$code" = "401" ]; then ok "T15 update no-auth → 401"; else ng "T15 update no-auth" "code=$code"; fi

# T16: stats 認証済み（2026-06・デモデータ期間）→ 200 + 曜日別7/時間帯24/サマリ値
body=$(curl -sk --max-time 20 -b "$JAR" "$BASE/api.php?action=stats&year=2026&month=06")
dd=$(printf '%s' "$body" | grep -o '"dow":' | wc -l)
hh=$(printf '%s' "$body" | grep -o '"hour":' | wc -l)
# summary.total は JSON 中で最初の "total": なので awk 分割の先頭桁で抽出（sed は max_day.total を拾うため不可）
sd=$(printf '%s' "$body" | awk -F'"days":' '{print $2}' | grep -o '^[0-9]*')
st=$(printf '%s' "$body" | awk -F'"total":' '{print $2}' | grep -o '^[0-9]*')
if [ "$dd" = "8" ] && [ "$hh" = "25" ] && [ -n "$sd" ] && [ "$sd" -ge 28 ] && [ -n "$st" ] && [ "$st" -ge 100 ]; then
  ok "T16 stats authed → 200（days=$sd total=$st dow=$dd hour=$hh）"
else
  ng "T16 stats authed" "days=$sd total=$st dow=$dd hour=$hh"
fi

# T17: monthly・day 未認証 → 200（公開化確認）
mresp=$(curl -sk --max-time 20 "$BASE/api.php?action=monthly&year=2026&month=06")
mday=$(printf '%s' "$mresp" | grep -o '"date":' | wc -l)
code=$(curl -sk --max-time 20 -o /dev/null -w '%{http_code}' "$BASE/api.php?action=day&date=2026-06-01")
if [ "$mday" = "30" ] && [ "$code" = "200" ]; then ok "T17 monthly no-auth 200（30日）+ day no-auth 200"; else ng "T17 monthly/day no-auth" "monthly_days=$mday day_code=$code"; fi

rm -f "$JAR" "$OUT"
echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
