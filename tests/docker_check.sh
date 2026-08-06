#!/usr/bin/env bash
# 駐車券記録アプリ — Docker デプロイ検証
# 前提: プロジェクトルートで実行し、docker compose up -d --build 済みであること
set -u
BASE="http://127.0.0.1:4500"
JAR=/tmp/park_docker_cookies.txt
rm -f "$JAR"

PASS=0; FAIL=0
ok()  { echo "PASS $1"; PASS=$((PASS+1)); }
ng()  { echo "FAIL $1 — $2"; FAIL=$((FAIL+1)); }
total_of() { printf '%s' "$1" | sed -n 's/.*"total":\([0-9]*\).*/\1/p' | head -1; }

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

# 2. today 初期 total=0（実DBは空）
today=$(curl -s "$BASE/api.php?action=today")
[ "$(total_of "$today")" = "0" ] && ok "2 today 初期 total=0" || ng "2 today 初期" "body=$today"

# 3. add(count=2) → 201
resp=$(curl -s -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"count":2}' "$BASE/api.php?action=add")
code=${resp##*$'\n'}; body=${resp%$'\n'*}
[ "$code" = "201" ] && ok "3 add(count=2) → 201" || ng "3 add" "code=$code body=$body"

# 4. today total=2（コンテナからホストDBへの書き込み確認）
today=$(curl -s "$BASE/api.php?action=today")
[ "$(total_of "$today")" = "2" ] && ok "4 today total=2（DB書込OK）" || ng "4 today total" "body=$today"

# 5. DB直アクセス遮断（php -S 運用の穴が Apache で解消されているか）
for p in data/parking.db data/.htaccess; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/$p")
  [ "$code" = "403" ] && ok "5 GET /$p → 403（直アクセス遮断）" || ng "5 GET /$p" "code=$code"
done

# 6. コンテナ再起動後もレコードが残る（永続化）
docker compose restart >/dev/null 2>&1
sleep 2
today=$(curl -s "$BASE/api.php?action=today")
[ "$(total_of "$today")" = "2" ] && ok "6 restart 後も total=2（永続化OK）" || ng "6 restart 永続化" "body=$today"

# 7. 後始末: PW認証で削除し、DBを空の状態に復元
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"pw":"1234"}' -c "$JAR" "$BASE/api.php?action=login")
[ "$code" = "200" ] && ok "7 login(pw=1234) → 200" || ng "7 login" "code=$code"
id=$(printf '%s' "$today" | sed -n 's/.*"id":\([0-9]*\).*/\1/p' | head -1)
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -X DELETE "$BASE/api.php?action=delete&id=$id")
[ "$code" = "204" ] && ok "7 delete → 204" || ng "7 delete" "code=$code"
today=$(curl -s "$BASE/api.php?action=today")
[ "$(total_of "$today")" = "0" ] && ok "7 today total=0（元の状態に復元）" || ng "7 復元" "body=$today"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
