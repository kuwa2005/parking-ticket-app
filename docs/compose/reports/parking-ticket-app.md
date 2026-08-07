---
feature: parking-ticket-app
status: delivered
specs:
  - docs/compose/specs/2026-08-07-parking-ticket-hearing.md
  - docs/compose/specs/2026-08-07-parking-ticket-app-spec.md
  - docs/compose/specs/2026-08-07-demo-mode-spec.md
  - docs/compose/specs/2026-08-07-day-detail-and-refresh-spec.md
plans:
  - docs/compose/plans/2026-08-07-parking-ticket-app.md
  - docs/compose/plans/2026-08-07-day-detail-refresh.md
branch: main
commits: 98f5807..(最新) — 監査・F1〜F4・本番デプロイ・DEMO化・新機能（日詳細/連動更新/自動更新）
---

# 駐車券記録アプリ — 最終レポート

## What Was Built

無料駐車券を渡した際に「枚数」と「日時（自動記録・日本時間）」を記録する、PHP + SQLite のモバイルファーストWebアプリ。ブラウザから記録・確認・削除・日別集計ができ、データはサーバー側の SQLite に永続化される（各端末には何も保存しない）。

- **記録**: 枚数（1〜999）を入力して記録。今日の合計・今日の一覧はパスワードなしで即時表示。
- **集計**: 年・月を指定した日別集計（各日の合計と月合計）。削除と同様に簡易パスワードで保護。**日付をクリックするとその日の詳細（時刻・枚数の一覧）をモーダル表示**。
- **連動・自動更新**: 日別集計表示中に「記録する」と集計側も最新化。60 秒間隔でデータ更新チェック（軽量 version API）を行い、更新があれば表示中の画面（今日・集計・日詳細）を自動最新化（他端末での記録が反映される）。
- **保護**: 管理操作（削除・日別集計・日詳細）のみ簡易PW（初期値 1234、設定ファイル固定）。誤操作・悪用防止ゲートであり、インターネット級の認証ではない（LAN内運用想定）。
- **UI**: Bootstrap 5.3.3（CDN版・jsDelivr）の日本語モバイルUI。ライト/ダークは OS 設定に自動追従（data-bs-theme="auto"）。
- **Dockerデプロイ**: このマシン（WSL2 + Docker Desktop）での運用は `php:8.3-apache` コンテナ。DBはホスト `./data` に永続化、`restart: unless-stopped` で自動起動・自動復帰。※Docker テスト環境は 2026-08-07 に終了。運用は本番（https://debugprint.com/parking/）へ直接デプロイ。

## Architecture

PHP + PDO/SQLite の単一ページWebアプリ。汎用レンタルサーバー（Xserver系等）で動くことを目標に、標準PHP拡張のみを使用。

```
ブラウザ (Bootstrap 5.3.3 CDN / 標準JS)
   │  fetch / JSON
   ▼
api.php  (HTTP層: セッション + hash_equals PW検証 + JSON応答)
   │
   ▼
lib/store.php  (HTTP非依存のコアロジック: 記録・集計・削除)
   │
   ▼
lib/db.php → data/parking.db (SQLite, WAL)
```

ファイル構成:

| ファイル | 役割 |
|---|---|
| `index.php` | モバイルUI（Bootstrap 5.3.3 CDN、PWダイアログ/日詳細は Bootstrap モーダル、60秒ポーリング） |
| `api.php` | JSON API: `add` / `today` / `monthly` / `delete` / `login` / `logout` / `day` / `version` |
| `lib/config.php` | 定数（DB_PATH / ADMIN_PW=1234 / APP_TZ=Asia/Tokyo / MAX_COUNT=999）。`if (!defined)` 形式でテスト時上書き可 |
| `lib/db.php` | PDO SQLite 接続 + スキーマ（`records(id, count CHECK 1..999, created_at)`） |
| `lib/store.php` | コアロジック（now_jst / add_record / get_today / get_day / get_db_version / get_monthly_totals / delete_record） |
| `data/.htaccess` | data/ 配下への直接アクセスを拒否 |
| `tests/run_tests.php` | 単体テスト T1〜T16（PHP CLI） |
| `tests/smoke_test.sh` | HTTPスモークテスト 19ケース（php -S + curl） |
| `tests/e2e_ui.mjs` | UI E2E 25チェック（ヘッドレスchrome + 生CDP、依存ゼロ） |
| `tests/production_check.sh` | 本番受入テスト 13ケース（T0相対・実データを壊さない） |
| `scripts/seed_demo.php` | デモデータ決定的生成（401件・冪等） |
| `Dockerfile` | `php:8.3-apache` ベース（pdo_sqlite 同梱）。アプリ一式 + entrypoint を COPY |
| `docker-compose.yml` | ポート `4500:80`、`./data` バインドマウント、`restart: unless-stopped` |
| `entrypoint.sh` | 起動時に data/ を www-data へ chown + .htaccess を保証して Apache 起動 |

### Design Decisions

- **PW は設定ファイルに固定**（ADMIN_PW=1234）。LAN内の誤操作防止を目的とし、ログイン不要の一般利用にした。
- **保護範囲を削除と月別集計のみ**に限定（記録・今日の合計・一覧はPWなし）。記録を「自由にできる」ことを優先。
- **タイムゾーンはコード内で Asia/Tokyo に固定**。ホストTZに依存せず日付境界（23:59:59→00:00:00）を正しく分類する。
- **テスト分離**: DB_PATH は 環境変数 `PARK_DB_PATH` > 事前 define > 既定値 の優先順。単体テストは一時DBへ define、スモーク/E2E は /tmp の一時DBで php -S を起動し、実データを一切汚さない。
- **E2E は依存ゼロで構築**（playwright を導入せず、システムの google-chrome をヘッドレス起動し Node 組み込み WebSocket で CDP を直接駆動）。
- **Docker は Apache 構成を採用**（Q15）。`php:8.3-apache` は pdo_sqlite/sqlite3 を同梱しており `docker-php-ext-install` は不要。data/.htaccess（deny-all）が Apache で機能し、php -S 運用にあった「`/data/parking.db` が直接ダウンロード可能」という実証済みの穴を塞ぐ（検証で 403 を確認）。
- **Docker の DB はホスト `./data` に永続化**（Q13）。コンテナを破棄してもデータは残り、バックアップは従来どおり `data/parking.db` のファイル管理。コンテナ内 Apache（www-data）が書き込むため、entrypoint で起動時に所有権を www-data に調整する。
- **自動起動・自動復帰**（Q14）: `restart: unless-stopped` により docker 起動時に自動起動し、クラッシュ時は自動再起動。シェルのバックグラウンドで動く `php -S` と違い、ライフサイクルがシェルと独立しているため「サーバーが立ち上がってない」問題が再発しない。

## Usage

開発環境（php -S、共有ホスティング相当）:

```bash
php -S 0.0.0.0:4500 -t /path/to/park
```

このマシンでの運用（Docker）:

```bash
docker compose up -d --build   # ビルド＆起動（自動復帰付き）
docker compose down            # 停止（データは ./data に残る）
docker compose logs -f         # ログ確認
```

- ブラウザで `http://<ホスト>:4500/` を開く。
- 枚数を入力し「記録する」→ 今日の合計・一覧に即時反映。
- 「日別集計」タブ → 年・月を指定 → パスワード `1234` を入力 → 各日の合計と月合計を表示。
- 今日の一覧の「削除」→ パスワード `1234` を入力 → レコード削除。
- パスワードは `lib/config.php` の `ADMIN_PW` で変更可能。
- データベースは `data/parking.db`（このファイルのバックアップでデータ保全）。

## Verification

テストスイートをすべて実行し、全PASSを確認（2026-08-07）。結果は `reports/` に記録済み。

| スイート | 内容 | 結果 |
|---|---|---|
| 単体（`tests/run_tests.php`） | T1〜T16: 記録の妥当性・今日の合計/一覧（昇順）・月別集計（境界含む）・削除・TZ固定・**get_day（日詳細・境界）・get_db_version（更新検出）** | **16/16 PASS** |
| シード（`tests/seed_demo_test.php`） | B1〜B8: デモデータ 401件/68日/count=1/日5〜10・中央値5/時刻範囲/差し替え/冪等/温存 | **8/8 PASS** |
| スモーク（`tests/smoke_test.sh`） | HTTP 19ケース: 200/201/400/401/200/204/404、PWログイン、認証スコープ、誤PWスロットル(F1)・セキュリティヘッダ(F4)・**day API（未認証401/不正400/認証200）・version API（200/削除で減算）** | **19/19 PASS** |
| E2E（`tests/e2e_ui.mjs`） | 実ブラウザ 25チェック: 初期表示→記録→PWダイアログ→誤PW/正PW→月別テーブル→削除（昇順対応）→**日付クリック詳細モーダル（E9）→集計表示中の記録連動（E10）→__refreshNow 自動更新（E11）** | **25/25 PASS**（ページ例外なし） |
| 本番（`tests/production_check.sh`） | **https://debugprint.com/parking/** 実サーバー 13ケース（**T0相対化**: デモデータ投入済みでも実データを壊さない）: 記録→集計→認証→削除、DB直アクセス403、誤PWスロットル、セキュリティヘッダ、一時スクリプト残存なし、**version API・day API（未認証401/認証200）** | **13/13 PASS** |

証跡: `reports/2026-08-07-unit-test-results.txt` / `reports/2026-08-07-seed-demo-test.txt` / `reports/2026-08-07-smoke-test-results.txt` / `reports/2026-08-07-e2e-ui-results.txt` / `reports/2026-08-07-production-verify.txt` / `reports/2026-08-07-production-deploy.txt`

※ Docker検証（`tests/docker_check.sh`）は Docker テスト環境の終了（2026-08-07・ユーザー指示）に伴い廃止。環境レベルの検証は本番受入テストが担う（直前の Docker 検証 17/17 PASS は `reports/2026-08-07-docker-verification.txt`）。

## Production Deployment（2026-08-07）

- **公開 URL: https://debugprint.com/parking/**（coreserver.jp 共有ホスティング・SFTP で配置）
- サブディレクトリ配置のため既存サイト（debugprint.com ルートのポートフォリオ）には無変更。ユーザー確認済み（ヒアリングログ Q22/Q23・最終指示「/virtual/pcm/public_html/debugprint.com/parking が正解」）
- **本番 ADMIN_PW はデモ用 1234 とは別のランダム値に変更**（値はリポジトリ外・ユーザーへ直接通知）
- DB は SQLite のまま空から開始（初回 API 呼び出しで `data/parking.db` 自動作成）。data/.htaccess により直アクセス 403 を実測
- 本番環境: PHP 8.5.2・pdo_sqlite 有効・display_errors Off・expose_php Off。F1（誤PW 401・1181ms）と F4（セキュリティヘッダ）も共有ホストで動作確認
- 途中 docomo2.com/parking/ に一時配置したが、ユーザー再指示で debugprint.com/parking/ に最終確定（docomo2 分は削除）
- 仕様: `docs/compose/specs/2026-08-07-production-deploy-spec.md`（Q19〜Q23 はヒアリングログに記録）

## 新機能ラウンド（2026-08-07・日付クリック詳細 + 集計連動更新 + 自動更新チェック）

- **依頼（逐語）**: 「日別集計で日付をクリックしたらその日の詳細が見られるようにして」「日別集計表示時、記録するを押下したら集計表示側も更新して」「時々データが更新されていないかチェックし、更新されていたら最新を表示して。」
- **設計（Q27〜Q32・[Never-Ask] 自律決定・Requirements Lock Approved）**: ①日詳細は **Bootstrap モーダル**表示（時刻・枚数の一覧・表示のみ・削除ボタンなし）②アクセス制御は**認証セッション中のみ**（日別集計と同一保護・未認証 401）③更新チェックは **60 秒間隔**・軽量 `version` API（count+maxId）の比較で変化時のみ再取得④デプロイは **本番へ直接**（Docker テスト環境終了・data/parking.db は保全・ダウンタイム許容）
- **API 追加**: `GET api.php?action=day&date=YYYY-MM-DD`（要認証・形式不正 400・該当日なしは total:0/records:[]・時間昇順）/ `GET api.php?action=version`（認証不要・`{count,maxId}`）。store.php に `get_day` / `get_db_version` を追加し、`get_today` は `get_day` へ委譲（重複ロジック削除）
- **UI 追加**: 日付セルをクリック化（`day-link text-primary`・下線）→ 日詳細モーダル（タイトル「M月D日（N件・T枚）」・今日一覧と同一の行スタイル）・add 成功時に集計/日詳細も連動更新・`window.__refreshNow` 公開 + 60 秒 `setInterval` ポーリング
- **実装方式**: TDD — unit T13〜T16 → smoke 15〜19 → E2E E9〜E11（RED→GREEN を実測）。コミット: e9ab00a（store.php コア）/ acc35f6（api.php）/ 1dd7841（index.php + E2E）
- **本番デプロイ（直接）**: SFTP（lftp mirror -R）で index.php / api.php / lib / scripts を上書き（data/parking.db は未送信・401件を保全）→ 受入テスト **13/13 PASS**（T11 version 401件 / T12 day 未認証 401 / T13 day 認証 200・5件）。既存ポートフォリオ（ルート・/about/）無傷確認

## Journey Log

- [dead end] Bootstrap 書き換えで削除ボタンの `del` クラスが脱落し、E2E の `#today-list .del` が全滅（DIAGで実証）。UI クラス名は E2E セレクタと一体。
- [dead end] `google-chrome` はラッパーで、`kill $PID` では実体 chrome が 9222 と認証済みセッションを保持して残り、次回 E2E が古いブラウザを操作して「PWダイアログが開かない」偽結果になった。→ `pkill -x chrome` + `Network.clearBrowserCookies` で解消。
- [lesson] Bootstrap Modal の `hide()` は show 遷移（約500ms）完了まで guard で無視する。E2E が 1 秒未満で操作すると「閉じない」ように見える（実ユーザーは PW 入力に秒単位かかるためアプリ側は正常）。→ 遷移完了を待ってから操作する。
- [pivot] CSS は当初「標準CSSのみ」で設計したが、要件ロック後に「Bootstrap（CDN版）」指示があり切替（ローカル配置 assets/ は試行後に破棄）。
- [pivot] 「サーバーが立ち上がってない」の指摘で Docker デプロイを追加（Q13〜Q15）。php -S はシェル依存のため消えやすく、Docker の `restart: unless-stopped` に切り替えた。ついでに php -S 運用の「`/data/parking.db` が直接ダウンロード可能」という実証済みの穴が Apache 化で塞がった。
- [dead end] Docker ビルドで `docker-php-ext-install pdo_sqlite` が `Package 'sqlite3' not found` で失敗。実は `php:8.3-apache` ベースイメージに pdo_sqlite/sqlite3 は**最初から同梱**されており（`php -m` で確認）、ビルド行は不要だった。→ 該当行を削除して解決。
- [lesson] 共有ホスティングのデプロイ先は「ドキュメントルート = 既存サイト」であることが多く、ルート配置は既存サイトと衝突する。SFTP の実パスは chroot のため絶対パス（/public_html/...）が通らず、ホーム相対パス（public_html/...）で操作する必要がある（coreserver.jp で実証）。
- [pivot] 配置先はユーザー指示の変遷で確定: debugprint.com/parking/（自律決定）→ docomo2.com/parking/（ユーザー指示）→ 最終的に「/virtual/pcm/public_html/debugprint.com/parking が正解」で **debugprint.com/parking/ に確定**。一時配置した docomo2.com/parking/ は撤回・削除。
- [lesson] 本番の管理PW は公開リポジトリ記載のデモ値（1234）のままにせず、ランダム値に変更する（値はリポジトリ外で管理）。
- [pivot] DEMO 化（2026-08-07）: ユーザーが本番を直接改修（タイトル(DEMO)・PWダイアログ表示/初期値 1234・get_today 昇順・デモデータ 401件投入・ADMIN_PW=1234）→「本番環境側で直接改修したので、こちらも反映して」でリポジトリへ反映。デモデータは DB バイナリでなく**シードスクリプト（scripts/seed_demo.php・決定的・冪等）**で再現。
- [lesson] 固定期待の HTTP テストは外部要因で破綻する（smoke 12/14 FAIL の実証）: smoke の「today total=2」等の固定期待が、ポート 4500 が Docker コンテナ（シード済み実DB）に占有された状態で破綻した（実データのレコードが混入）。原因（Docker コンテナ消滅 + 4500 空き）解消後に再実行で 14/14 に復帰。→ テストは T0 相対方式（本番受入）や一時DBの完全隔離（smoke）を徹底。
- [lesson] 新機能の E2E は「表示中パネルの連動」を検証するため、初回ポーリング（checkVersion のベースライン確立）とモーダルの show 遷移（hide の guard 約500ms）に注意。E9 は show 遷移完了を待ってから hide する（既存 E5/E6 と同じ Bootstrap Modal の guard 問題）。
- [lesson] デプロイは「ローカル全検証 GREEN → SFTP 直接配置 → 本番受入テスト（T0 相対）+ 既存サイト無傷確認」の順序で安全に実施できる（Docker テスト環境終了後の新標準手順）。

## Source Materials

| ファイル | 役割 | 備考 |
|---|---|---|
| `docs/compose/specs/2026-08-07-parking-ticket-hearing.md` | ヒアリングログ Q1〜Q32 | 要件の由来（Q13〜Q15: Docker・Q19〜Q23: 本番デプロイ・Q24〜Q26: DEMO化・Q27〜Q32: 新機能） |
| `docs/compose/specs/2026-08-07-parking-ticket-app-spec.md` | 設計仕様 [S1]〜[S12] | Bootstrap CDN + Docker デプロイを反映 |
| `docs/compose/specs/2026-08-07-demo-mode-spec.md` | DEMO 化仕様 R1〜R9・デモデータ仕様 | シードスクリプト + 検証（seed 8/8） |
| `docs/compose/specs/2026-08-07-day-detail-and-refresh-spec.md` | 新機能仕様 R1〜R11・API/UI/テスト仕様 | 日詳細 + 連動更新 + 自動更新チェック |
| `docs/compose/specs/2026-08-07-security-audit-report-spec.md` | 監査レポート配布の要件・テスト仕様 | 受入テスト: tests/acceptance_audit_report.sh |
| `docs/compose/specs/2026-08-07-production-deploy-spec.md` | 本番デプロイの要件・テスト仕様 | 受入テスト: tests/production_check.sh |
| `docs/compose/plans/2026-08-07-parking-ticket-app.md` | 実装計画（6タスク） | E2E 追加・根因調査の記録を追記 |
| `docs/compose/plans/2026-08-07-day-detail-refresh.md` | 新機能実装計画（5タスク） | store→api→UI→本番デプロイ→docs |
