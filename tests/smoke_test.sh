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
today_ymd=$(date +%F)

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

# 5. monthly 未認証でも 200（公開化・Q42: メインの過去閲覧のため）+ 本日の日付を含む
resp=$(curl -s -b "$JAR2" "$BASE/api.php?action=monthly&year=$YEAR&month=$MONTH")
if printf '%s' "$resp" | grep -q "$today_ymd"; then ok "5 monthly no-auth 200 + today included"; else ng "5 monthly no-auth" "resp=$resp"; fi

# 6. login 誤PW → 401
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"pw":"9999"}' -c "$JAR" "$BASE/api.php?action=login")
if [ "$code" = "401" ]; then ok "6 login wrong pw 401"; else ng "6 login wrong pw" "code=$code"; fi

# 7. login 正PW(1234) → 200
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"pw":"1234"}' -c "$JAR" "$BASE/api.php?action=login")
if [ "$code" = "200" ]; then ok "7 login correct pw 200"; else ng "7 login correct pw" "code=$code"; fi

# 8. monthly 認証済み → 200 + 本日の日付を含む
resp=$(curl -s -b "$JAR" "$BASE/api.php?action=monthly&year=$YEAR&month=$MONTH")
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

# 15. day 未認証でも 200（公開化・Q42）
resp=$(curl -s -b "$JAR2" "$BASE/api.php?action=day&date=$today_ymd")
if printf '%s' "$resp" | grep -q '"records":\['; then ok "15 day no-auth 200"; else ng "15 day no-auth" "resp=$resp"; fi

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

# 20. auth 未認証（別クッキー）→ 401 / 21. auth 認証済み → 200
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR2" "$BASE/api.php?action=auth")
code2=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" "$BASE/api.php?action=auth")
if [ "$code" = "401" ] && [ "$code2" = "200" ]; then ok "20/21 auth no-auth 401 / authed 200"; else ng "20/21 auth" "no-auth=$code authed=$code2"; fi

# 22. update 未認証 → 401（対象レコードを追加）
resp4=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"count":5}' "$BASE/api.php?action=add")
id4=$(printf '%s' "$resp4" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR2" -X POST -H 'Content-Type: application/json' -d "{\"id\":$id4,\"count\":8}" "$BASE/api.php?action=update")
if [ "$code" = "401" ]; then ok "22 update no-auth 401"; else ng "22 update no-auth" "code=$code"; fi

# 23. update 認証済み（count 5→8）→ 200 + today total=8
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -X POST -H 'Content-Type: application/json' -d "{\"id\":$id4,\"count\":8}" "$BASE/api.php?action=update")
today=$(curl -s "$BASE/api.php?action=today")
total=$(printf '%s' "$today" | sed -n 's/.*"total":\([0-9]*\).*/\1/p')
if [ "$code" = "200" ] && [ "$total" = "8" ]; then ok "23 update authed 200 + total=8"; else ng "23 update authed" "code=$code total=$total"; fi

# 24. update 不正（count=0 → 400 / 日時形式不正 → 400 / 存在しない id → 404）
c1=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -X POST -H 'Content-Type: application/json' -d "{\"id\":$id4,\"count\":0}" "$BASE/api.php?action=update")
c2=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -X POST -H 'Content-Type: application/json' -d "{\"id\":$id4,\"created_at\":\"2026-08-07\"}" "$BASE/api.php?action=update")
c3=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -X POST -H 'Content-Type: application/json' -d '{"id":999999,"count":1}' "$BASE/api.php?action=update")
if [ "$c1" = "400" ] && [ "$c2" = "400" ] && [ "$c3" = "404" ]; then ok "24 update invalid 400/400/404"; else ng "24 update invalid" "c1=$c1 c2=$c2 c3=$c3"; fi

# 25. stats 未認証 → 401
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR2" "$BASE/api.php?action=stats&year=$YEAR&month=$MONTH")
if [ "$code" = "401" ]; then ok "25 stats no-auth 401"; else ng "25 stats no-auth" "code=$code"; fi

# 26. stats 認証済み → 200（当月: days=1 total=8 max=today）+ yearly 認証済み → 200（12ヶ月）
resp=$(curl -s -b "$JAR" "$BASE/api.php?action=stats&year=$YEAR&month=$MONTH")
yresp=$(curl -s -b "$JAR" "$BASE/api.php?action=yearly&year=$YEAR")
mcount=$(printf '%s' "$yresp" | grep -o '"month":' | wc -l)
if printf '%s' "$resp" | grep -q '"total":8' && printf '%s' "$resp" | grep -q '"days":1' \
   && printf '%s' "$resp" | grep -q "\"date\":\"$today_ymd\"" && [ "$mcount" = "12" ]; then
  ok "26 stats authed 200 (total=8 days=1) + yearly 12 months"
else
  ng "26 stats authed" "stats=$resp yearly=$yresp"
fi

# 27. add_record 未認証（別クッキー）→ 401（過去日追加は管理者権限・R4）
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR2" -X POST -H 'Content-Type: application/json' \
  -d '{"count":2,"date":"2026-08-01","time":"09:30"}' "$BASE/api.php?action=add_record")
if [ "$code" = "401" ]; then ok "27 add_record no-auth 401"; else ng "27 add_record no-auth" "code=$code"; fi

# 28. add_record 認証済み（過去日 2026-08-01 09:30）→ 201 + created_at が指定日時
resp=$(curl -s -w '\n%{http_code}' -b "$JAR" -X POST -H 'Content-Type: application/json' \
  -d '{"count":2,"date":"2026-08-01","time":"09:30"}' "$BASE/api.php?action=add_record")
code=${resp##*$'\n'}; body=${resp%$'\n'*}
if [ "$code" = "201" ] && printf '%s' "$body" | grep -q '"created_at":"2026-08-01 09:30:00"'; then
  ok "28 add_record authed 201 (2026-08-01 09:30:00)"
else
  ng "28 add_record authed" "code=$code body=$body"
fi

# 29. add_record count=0 → 400
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -X POST -H 'Content-Type: application/json' \
  -d '{"count":0,"date":"2026-08-01","time":"09:30"}' "$BASE/api.php?action=add_record")
if [ "$code" = "400" ]; then ok "29 add_record count=0 400"; else ng "29 add_record count=0" "code=$code"; fi

# 30. add_record date 形式不正（2026-02-31 は実在しない日付）→ 400
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -X POST -H 'Content-Type: application/json' \
  -d '{"count":1,"date":"2026-02-31","time":"09:30"}' "$BASE/api.php?action=add_record")
if [ "$code" = "400" ]; then ok "30 add_record invalid date 400"; else ng "30 add_record invalid date" "code=$code"; fi

# 31. add_record time 形式不正（25:00）→ 400
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -X POST -H 'Content-Type: application/json' \
  -d '{"count":1,"date":"2026-08-01","time":"25:00"}' "$BASE/api.php?action=add_record")
if [ "$code" = "400" ]; then ok "31 add_record invalid time 400"; else ng "31 add_record invalid time" "code=$code"; fi

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
