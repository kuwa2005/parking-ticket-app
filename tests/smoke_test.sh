#!/usr/bin/env bash
# 駐車券記録アプリ HTTPスモークテスト（php -S + curl）
# 実データを汚さないよう、一時DB(PARK_DB_PATH)で実行する。
set -u
PORT=4500
BASE="http://127.0.0.1:${PORT}"
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DB=/tmp/park_smoke.db
JAR=/tmp/park_cookies.txt
JAR2=/tmp/park_cookies2.txt
rm -f "$TMP_DB" "$TMP_DB-wal" "$TMP_DB-shm" "$JAR" "$JAR2"

PASS=0; FAIL=0
ok() { echo "PASS $1"; PASS=$((PASS+1)); }
ng() { echo "FAIL $1 — $2"; FAIL=$((FAIL+1)); }

PARK_DB_PATH="$TMP_DB" php -S 127.0.0.1:${PORT} -t "$APP_DIR" >/tmp/park_smoke_server.log 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null' EXIT
sleep 1

YEAR=$(date +%Y)
MONTH=$(date +%-m)

# 1. index.php が 200 で「駐車券」「記録する」を含む
code=$(curl -s -o /tmp/park_idx.html -w '%{http_code}' "$BASE/index.php")
if [ "$code" = "200" ] && grep -q '駐車券' /tmp/park_idx.html && grep -q '記録する' /tmp/park_idx.html; then
  ok "1 index.php 200 + UI要素"
else
  ng "1 index.php" "code=$code"
fi

# 2. add(count=2) → 201（id を取得）
resp=$(curl -s -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"count":2}' "$BASE/api.php?action=add")
code=${resp##*$'\n'}; body=${resp%$'\n'*}
id=$(printf '%s' "$body" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
if [ "$code" = "201" ] && [ -n "$id" ]; then ok "2 add(count=2) 201 id=$id"; else ng "2 add" "code=$code body=$body"; fi

# 3. today の total に反映（一時DBなので2）
today=$(curl -s "$BASE/api.php?action=today")
total=$(printf '%s' "$today" | sed -n 's/.*"total":\([0-9]*\).*/\1/p')
if [ "$total" = "2" ]; then ok "3 today total=2"; else ng "3 today total" "total=$total body=$today"; fi

# 4. add(count=0) → 400
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"count":0}' "$BASE/api.php?action=add")
if [ "$code" = "400" ]; then ok "4 add(count=0) 400"; else ng "4 add invalid" "code=$code"; fi

# 5. monthly 未認証 → 401
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" "$BASE/api.php?action=monthly&year=$YEAR&month=$MONTH")
if [ "$code" = "401" ]; then ok "5 monthly no-auth 401"; else ng "5 monthly no-auth" "code=$code"; fi

# 6. login 誤PW → 401
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"pw":"9999"}' -c "$JAR" "$BASE/api.php?action=login")
if [ "$code" = "401" ]; then ok "6 login wrong pw 401"; else ng "6 login wrong pw" "code=$code"; fi

# 7. login 正PW(1234) → 200
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"pw":"1234"}' -c "$JAR" "$BASE/api.php?action=login")
if [ "$code" = "200" ]; then ok "7 login correct pw 200"; else ng "7 login correct pw" "code=$code"; fi

# 8. monthly 認証済み → 200 + 本日の日付を含む
resp=$(curl -s -b "$JAR" "$BASE/api.php?action=monthly&year=$YEAR&month=$MONTH")
today_ymd=$(date +%F)
if printf '%s' "$resp" | grep -q "$today_ymd"; then ok "8 monthly authed 200 + today included"; else ng "8 monthly authed" "resp=$resp"; fi

# 9. delete 未認証（別クッキー）→ 401
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR2" -X DELETE "$BASE/api.php?action=delete&id=$id")
if [ "$code" = "401" ]; then ok "9 delete no-auth 401"; else ng "9 delete no-auth" "code=$code"; fi

# 10. delete 認証済み → 204
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -X DELETE "$BASE/api.php?action=delete&id=$id")
if [ "$code" = "204" ]; then ok "10 delete authed 204"; else ng "10 delete authed" "code=$code"; fi

# 11. 再削除 → 404
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -X DELETE "$BASE/api.php?action=delete&id=$id")
if [ "$code" = "404" ]; then ok "11 delete again 404"; else ng "11 delete again" "code=$code"; fi

# 12. today 削除後 → total 0
today=$(curl -s "$BASE/api.php?action=today")
total=$(printf '%s' "$today" | sed -n 's/.*"total":\([0-9]*\).*/\1/p')
if [ "$total" = "0" ]; then ok "12 today total=0 after delete"; else ng "12 today after delete" "total=$total"; fi

# 13. 誤PWログインは1秒以上かかる（監査F1: ブルートフォース抑止）
S=$(date +%s%N)
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"pw":"8888"}' "$BASE/api.php?action=login")
E=$(date +%s%N)
ms=$(( (E - S) / 1000000 ))
if [ "$code" = "401" ] && [ "$ms" -ge 1000 ]; then ok "13 login wrong pw throttled (${ms}ms)"; else ng "13 login throttle" "code=$code ms=${ms}ms"; fi

# 14. index.php セキュリティヘッダ3種（監査F4）
HDRS=$(curl -sI "$BASE/index.php")
XFO=$(printf '%s' "$HDRS" | grep -i '^X-Frame-Options: DENY' | head -1)
XCT=$(printf '%s' "$HDRS" | grep -i '^X-Content-Type-Options: nosniff' | head -1)
RP=$(printf '%s' "$HDRS" | grep -i '^Referrer-Policy: no-referrer' | head -1)
if [ -n "$XFO" ] && [ -n "$XCT" ] && [ -n "$RP" ]; then
  ok "14 index.php セキュリティヘッダ3種"
else
  ng "14 index.php セキュリティヘッダ" "XFO=$XFO XCT=$XCT RP=$RP"
fi

# 15. day 未認証（別クッキー）→ 401
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR2" "$BASE/api.php?action=day&date=$today_ymd")
if [ "$code" = "401" ]; then ok "15 day no-auth 401"; else ng "15 day no-auth" "code=$code"; fi

# 16. day 不正な日付形式 → 400
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" "$BASE/api.php?action=day&date=2026/08/07")
if [ "$code" = "400" ]; then ok "16 day invalid date 400"; else ng "16 day invalid date" "code=$code"; fi

# 17. day 認証済み（今日・2件追加後）→ 200 + total 2
resp2=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"count":1}' "$BASE/api.php?action=add")
id2=$(printf '%s' "$resp2" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
resp3=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"count":1}' "$BASE/api.php?action=add")
id3=$(printf '%s' "$resp3" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
dayresp=$(curl -s -b "$JAR" "$BASE/api.php?action=day&date=$today_ymd")
if printf '%s' "$dayresp" | grep -q '"total":2' && printf '%s' "$dayresp" | grep -q '"records":\['; then
  ok "17 day authed 200 + total 2"
else
  ng "17 day authed" "$dayresp"
fi

# 18. version → 200 + count≥2・maxId≥1（認証不要）
ver=$(curl -s "$BASE/api.php?action=version")
vcount=$(printf '%s' "$ver" | sed -n 's/.*"count":\([0-9]*\).*/\1/p')
vmax=$(printf '%s' "$ver" | sed -n 's/.*"maxId":\([0-9]*\).*/\1/p')
if [ -n "$vcount" ] && [ "$vcount" -ge 2 ] && [ -n "$vmax" ] && [ "$vmax" -ge 1 ]; then
  ok "18 version 200 (count=$vcount maxId=$vmax)"
else
  ng "18 version" "$ver"
fi

# 19. 削除後に version の count が減る
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -X DELETE "$BASE/api.php?action=delete&id=$id2")
ver2=$(curl -s "$BASE/api.php?action=version")
vcount2=$(printf '%s' "$ver2" | sed -n 's/.*"count":\([0-9]*\).*/\1/p')
if [ "$code" = "204" ] && [ "$vcount2" = "$((vcount - 1))" ]; then
  ok "19 version count decrements"
else
  ng "19 version decrement" "code=$code count=$vcount->$vcount2"
fi
curl -s -o /dev/null -b "$JAR" -X DELETE "$BASE/api.php?action=delete&id=$id3" # 後片付け（today=0 維持）

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
