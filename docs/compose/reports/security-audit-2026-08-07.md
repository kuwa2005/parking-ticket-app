# 駐車券記録アプリ — セキュリティ監査レポート

- 日付: 2026-08-07
- 対象: park-app コンテナ（kuwa2005/parking-ticket-app、`php:8.3-apache`、ポート 4500）
- 種別: 監査のみ（修正は未実施・指示待ち）
- 方法: ① 全ソースの静的レビュー（OWASP Top 10 ベース）② 稼働中コンテナへの攻撃的アクセステスト（SQLi / 認証バイパス / 機微ファイル / メソッド乱用 / ブルートフォース / セッション / ペイロード境界）

## 総評

**クリティカル・高危険度の脆弱性は検出されず。** 小さな攻撃面（2つのAPIエンドポイント群 + 入力検証）に対し、注入・認証・セッション・CSRF・データ保護は堅牢。検出は「運用上の注意」レベル（F1〜F4）で、いずれも LAN 内運用 + デモ用PW という前提で許容範囲。**→ 監査後にユーザー指示により F1〜F4 はすべて修正済み（2026-08-07・検証全スイート PASS・末尾「対応状況」参照）。**

## テスト結果サマリ（実測）

| # | テスト | 想定 | 実測 | 結果 |
|---|---|---|---|---|
| 1 | SQLi: `action=today'` / monthly `year=2026' OR '1'='1`（URLエンコード）/ `id=1 OR 1=1` / `DROP TABLE` 混入 / delete 注入 | 400/404・DB無傷 | 400/404、DB無傷（レコード破壊なし） | 防御OK |
| 2 | 認証バイパス: delete / monthly を未認証で | 401 | 401 | 防御OK |
| 3 | XSS: 描画 API（textContent のみ / innerHTML・eval ゼロ、静的確認） | 注入不能 | サーバー出力は検証済み整数・日時のみ | 防御OK |
| 4 | ソース漏洩: /lib/config.php・store.php・db.php 直GET | 空応答（ソース非表示） | 0バイト空応答 | 防御OK |
| 5 | 機微ファイル: /.git/config・/reports/・/docs/・/Dockerfile | 404（イメージに不在） | 全て404 | 防御OK |
| 6 | DB直アクセス: /data/parking.db・-wal・-shm・.htaccess | 403 | 全て403（.htaccess 退避テストで 200 に変化 → 実効性を実証） | 防御OK |
| 7 | パストラバーサル: `/%2e%2e/etc/passwd` | 400 | 400 | 防御OK |
| 8 | メソッド乱用: TRACE / GET-add / PUT-index.php | 405 / 副作用なし | 405 / 400 / PHP実行（書込なし） | 防御OK |
| 9 | 入力境界: count=1000・0・-5・"3"・3.5・巨大数・null・不正JSON・month=13/00 | 400 | 全て400（`count` は is_int 1〜999 厳格、JSON パース失敗も400） | 防御OK |
| 10 | セッションフィクセーション: ログイン前後でID変化 | 再生成される | ID が変化（session_regenerate_id） | 防御OK |
| 11 | CSRF: SameSite=Lax + JSONボディ + DELETE専用 + CORSヘッダなし | クロスサイト不可 | ブラウザがクロスサイト状態変更を遮断（形式検証） | 防御OK |
| 12 | ブルートフォース: 連続PW試行 | レート制限なし | 5回連続401→正解200（制限・ロックアウトなし） | **F1** |

## 発見事項

### F1（中）ログインにレート制限・ロックアウトがない
- **証拠**: 連続で誤PW 5回（0000/1111/2222/3333/9999）→ すべて即時 401、直後に正解 1234 → 200。遅延・回数制限・ロックなし。
- **影響**: 4桁のPW（1234、かつソース公開済み）は最大 10,000 通り。Docker Desktop はポートを 0.0.0.0 に公開するため LAN 全体から到達可能。決意のある LAN 内攻撃者は数分で全管理操作（削除・月別集計）を掌握できる。→ 本アプリの脅威モデル（「LAN内の誤操作・悪用防止」）に対しては、**意図的攻撃者の想定外**である点は限界として認識する。
- **推奨**: 認証失敗時に固定遅延（例: `sleep(1)`）を入れる、あるいは試行回数制限。デモ用途のままでも許容（ユーザー方針による）。

### F2（低〜中）コンテナ PHP が display_errors=1
- **証拠**: `docker exec park-app php -r 'echo ini_get("display_errors")'` → `1`。
- **影響**: DB ロック・ディスク満杯等で未捕捉例外（PDOException）が発生すると、HTTP 応答にスタックトレースと絶対パスが漏れる。リモートから意図的に発生させるのは困難だが、障害時に情報開示する。
- **推奨**: `docker-php-ext` の設定あるいは環境変数（`PHP_INI_DIR` の production 設定適用、または `display_errors=Off`）で本番設定にする。

### F3（低）バージョン開示
- **証拠**: `Server: Apache/2.4.68 (Debian)` / `X-Powered-By: PHP/8.3.33`（expose_php=1）/ 404 ページに `Apache/2.4.68 (Debian) Server at 127.0.0.1 Port 4500`（ServerSignature On）。
- **影響**: 既知CVE を狙う攻撃者の情報収集を助ける。
- **推奨**: `ServerTokens Prod` / `ServerSignature Off` / `expose_php=Off`。

### F4（低）HTML ページにセキュリティヘッダなし
- **証拠**: `curl -sI /` → X-Content-Type-Options / X-Frame-Options / CSP / Referrer-Policy なし（API 側には nosniff あり）。
- **影響**: MIME スニッフィング・クリックジャッキングの残余リスク。ただし CSRF は SameSite+Lax と JSON/DELETE 制約で実質遮断済み。
- **推奨**: `X-Content-Type-Options: nosniff` / `X-Frame-Options: DENY` / `Referrer-Policy: no-referrer` を index.php 応答に追加。CSP はインラインJS + CDN のため `'unsafe-inline'` 前提になる（効果限定的）。

### 注意事項（設計上許容・変更不要）

- **PW は平文でソースに固定**（ADMIN_PW=1234、公開リポジトリに掲載）— デモ用PW としてユーザー承諾済み（Q17）。実運用で露出範囲を広げる場合は必ず変更。
- **記録（add）は無認証** — 仕様どおり「記録は自由」。LAN 内の誰でも枚数を記録できる（DoS 的な大量記録も可能だが、今日一覧から削除可能）。
- **セッションクッキーに Secure フラグなし** — LAN 内 HTTP が前提のため正常。HTTPS 化する場合は付与。
- **認証済みセッションは任意のレコードIDを削除可能**（ID列挙）— 「誤記録の削除」を目的とした設計上の範囲。

## 対応状況（2026-08-07 修正完了）

ユーザー指示「F1〜F4を修正して」により、全指摘を修正済み。実装は TDD（F1/F4）または設定変更（F2/F3）で行い、4スイートすべてで再検証した。

| 指摘 | 修正内容 | 検証（実測） |
|---|---|---|
| F1 ログインにレート制限なし | api.php の login 失敗パスに `sleep(1)` を追加（非文字列・PW不一致の両パス）。ステートレスでセッション/IP追跡なしの最小実装。4桁PW 10,000通り → 最低約2.8時間に拡大 | smoke テスト13: 誤PWログイン応答 **1019ms**（≥1000ms を PASS 判定） |
| F2 コンテナ display_errors=1 | Dockerfile で `/usr/local/etc/php/conf.d/zz-security.ini` に `display_errors = Off`・`log_errors = On`・`expose_php = Off`（log_errors=On で docker logs デバッグ維持） | docker_check テスト9: `docker exec` で display_errors=Off を確認 |
| F3 バージョン開示 | Dockerfile で `/etc/apache2/conf-available/zz-security.conf` に `ServerTokens Prod`・`ServerSignature Off` + `a2enconf zz-security`。expose_php=Off は F2 の設定で同時解消 | docker_check テスト8: `Server: Apache`（バージョンなし）+ X-Powered-By なし / テスト11: 404ページに署名なし |
| F4 HTML にセキュリティヘッダなし | index.php の PHP `header()` で `X-Content-Type-Options: nosniff` / `X-Frame-Options: DENY` / `Referrer-Policy: no-referrer` を追加（共有レンタルサーバーでも効くポータブル実装。CSP は inline JS + CDN のため不採用） | smoke テスト14 + docker_check テスト10: 3ヘッダとも検出 |

**再検証結果（2026-08-07・fresh 実行）**: 単体 12/12 PASS / HTTPスモーク 14/14 PASS / UI E2E 17/17 PASS（pageErrors none）/ Docker検証 17/17 PASS — 証跡は reports/2026-08-07-{unit-test-results,smoke-test-results,e2e-ui-results,docker-verification}.txt。

**付随改善**: tests/docker_check.sh を「実DBは空」前提から安全設計（ベースライン T0 取得 → 自レコード id のみ削除 → T0 復元）に修正。ユーザーデータが混入していても誤削除しないことを実データ（T0=6）で実証した。

## 監査で確認した防御（実装側の良い点）

- PDO プリペアドステートメントのみ使用、動的SQLなし。入力は全て型・範囲を厳格検証（is_int / ctype_digit / 2000-2100・1-12 / 1〜999）。
- 認証は `hash_equals`（定数時間比較）、ログイン時に `session_regenerate_id(true)`（フィクセーション対策）。
- クッキー: `HttpOnly` + `SameSite=Lax`。削除操作は DELETE メソッドのみ + JSON ボディ → クロスサイトフォームでは再現不能。
- 描画は全て `textContent`（XSS 面なし）。エラーメッセージは具体情報を含まない汎用文言。
- data/ は .htaccess（deny-all）で遮断され、entrypoint が .htaccess 不在時に再作成（バインドマウント欠落対策）— 退避テストで実効性を確認。
- 画像に .git・ドキュメント・テスト・レポートを含めない構成（COPY はアプリファイルのみ）。

## 監査実施時の注意事項

- 監査中のデータ変更: **なし**（データベースの記録は監査前から存在した id=3 の1件のみ。SQLi プローブ後の整合性確認で total=1 のまま）。
- .htaccess 退避テストはコンテナ内で1秒未満の実施・即復元（LAN 内の自コンテナであり、露出は生じていない）。
