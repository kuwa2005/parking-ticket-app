#!/usr/bin/env bash
# 駐車券記録アプリ — Docker デプロイ検証（+ セキュリティ監査 F2-F4 の回帰チェック）
# 前提: プロジェクトルートで実行し、docker compose up -d --build 済みであること
# 注意: 実DB（./data）にユーザーデータが存在しても安全に動作する（自レコードのみ削除）
set -u
BASE="http://127.0.0.1:4500"
JAR=/tmp/park_docker_cookies.txt
rm -f "$JAR"

PASS=0; FAIL=0
ok()  { echo "PASS $1"; PASS=$((PASS+1)); }
ng()  { echo "FAIL $1 — $2"; FAIL=$((FAIL+1)); }
total_of() { printf '%s' "$1" | sed -n 's/.*"total":\([0-9]*\).*/\1/p' | head -1; }
id_first() { printf '%s' "$1" | sed -n 's/.*"id":\([0-9]*\).*/\1/p' | head -1; }

# 0. コンテナ状態と再起動ポリシー
STATUS=$(docker inspect -f '{{.State.Status}}' park-app 2>/dev/null)
[ "$STATUS" = "running" ] && ok "0 コンテナ running" || ng "0 コンテナ running" "status=$STATUS"
RP=$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' park-app 2>/dev/null)
[ "$RP" = "unless-stopped" ] && ok "0 restart=unless-stopped" || ng "0 restart policy" "policy=$RP"

# 1. index.php 200 + UI要素（Bootstrap CDN リンク含む）
code=$(curl -s -o /tmp/park_docker_idx.html -w '%{http_code}' "$BASE/index.php")
if [ "$code" = "200" ] && grep -q '駐車券' /tmp/park_docker_idx.html \
   && grep -q 'cdn.jsdelivr.net/npm/bootstrap@5.3.3' /tmp/park_docker_idx.html; then
  ok "1 index.php 200 + 駐車券UI"
else
  ng "1 index.php" "code=$code"
fi

# 2. ベースライン記録（実DBは空とは限らない — ユーザーデータを壊さないため基準値を保持）
T0=$(total_of "$(curl -s "$BASE/api.php?action=today")")
ok "2 today baseline total=$T0"

# 3. add(count=2) → 201（自レコードの id を保持）
resp=$(curl -s -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"count":2}' "$BASE/api.php?action=add")
code=${resp##*$'\n'}; body=${resp%$'\n'*}
id_own=$(id_first "$body")
if [ "$code" = "201" ] && [ -n "$id_own" ]; then ok "3 add(count=2) → 201 id=$id_own"; else ng "3 add" "code=$code body=$body"; fi

# 4. today total = T0+2（コンテナからホストDBへの書き込み確認）
today=$(curl -s "$BASE/api.php?action=today")
[ "$(total_of "$today")" = "$((T0+2))" ] && ok "4 today total=$((T0+2))（DB書込OK）" || ng "4 today total" "body=$today"

# 5. DB直アクセス遮断（php -S 運用の穴が Apache で解消されているか）
for p in data/parking.db data/.htaccess; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/$p")
  [ "$code" = "403" ] && ok "5 GET /$p → 403（直アクセス遮断）" || ng "5 GET /$p" "code=$code"
done

# 6. コンテナ再起動後もレコードが残る（永続化）
docker compose restart >/dev/null 2>&1
sleep 2
today=$(curl -s "$BASE/api.php?action=today")
[ "$(total_of "$today")" = "$((T0+2))" ] && ok "6 restart 後も total=$((T0+2))（永続化OK）" || ng "6 restart 永続化" "body=$today"

# 7. 後始末: 自レコード（id_own）のみ削除し、ベースライン T0 に復元（ユーザーデータは不変）
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"pw":"1234"}' -c "$JAR" "$BASE/api.php?action=login")
[ "$code" = "200" ] && ok "7 login(pw=1234) → 200" || ng "7 login" "code=$code"
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -X DELETE "$BASE/api.php?action=delete&id=$id_own")
[ "$code" = "204" ] && ok "7 delete(id=$id_own) → 204" || ng "7 delete" "code=$code"
today=$(curl -s "$BASE/api.php?action=today")
[ "$(total_of "$today")" = "$T0" ] && ok "7 today total=$T0（ベースラインに復元）" || ng "7 復元" "body=$today"

# 8. バージョン開示なし（監査F3: ServerTokens Prod / expose_php=Off）
SRV=$(curl -sI "$BASE/api.php?action=today" | tr -d '\r' | grep -i '^Server:' | head -1)
printf '%s' "$SRV" | grep -qiE '^Server: Apache$' && ok "8 Server=Apache（バージョン非開示）" || ng "8 Server ヘッダ" "$SRV"
XP=$(curl -sI "$BASE/api.php?action=today" | tr -d '\r' | grep -i '^X-Powered-By:' | head -1)
[ -z "$XP" ] && ok "8 X-Powered-By なし（expose_php=Off）" || ng "8 X-Powered-By" "$XP"

# 9. display_errors=Off（監査F2・コンテナ内実測。PHPのboolean iniはOff時 ini_get が空文字を返す）
DE=$(docker exec park-app php -r 'echo ini_get("display_errors");')
[ "$DE" != "1" ] && [ "$DE" != "On" ] && ok "9 display_errors=Off" || ng "9 display_errors" "=$DE"

# 10. index.php セキュリティヘッダ3種（監査F4）
HDRS=$(curl -sI "$BASE/index.php")
XFO=$(printf '%s' "$HDRS" | grep -i '^X-Frame-Options: DENY' | head -1)
XCT=$(printf '%s' "$HDRS" | grep -i '^X-Content-Type-Options: nosniff' | head -1)
RP=$(printf '%s' "$HDRS" | grep -i '^Referrer-Policy: no-referrer' | head -1)
if [ -n "$XFO" ] && [ -n "$XCT" ] && [ -n "$RP" ]; then
  ok "10 index.php セキュリティヘッダ3種"
else
  ng "10 セキュリティヘッダ" "XFO=$XFO XCT=$XCT RP=$RP"
fi

# 11. 404ページに Apache バージョン署名なし（監査F3: ServerSignature Off）
P404=$(curl -s "$BASE/no_such_path_xyz_audit")
if printf '%s' "$P404" | grep -qE 'Apache/2\.[0-9]|Port 4500|Server at'; then
  ng "11 404署名なし" "署名あり"
else
  ok "11 404ページに署名なし"
fi

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
