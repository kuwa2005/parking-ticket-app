---
feature: parking-ticket-app
status: delivered
specs:
  - docs/compose/specs/2026-08-07-parking-ticket-hearing.md
  - docs/compose/specs/2026-08-07-parking-ticket-app-spec.md
  - docs/compose/specs/2026-08-07-demo-mode-spec.md
  - docs/compose/specs/2026-08-07-day-detail-and-refresh-spec.md
  - docs/compose/specs/2026-08-09-calendar-layout-and-admin-usability-hearing.md
  - docs/compose/specs/2026-08-09-calendar-layout-and-admin-usability-spec.md
  - docs/compose/specs/2026-08-09-ssh-block-knowledge-cleanup-hearing.md
  - docs/compose/specs/2026-08-09-ssh-block-knowledge-cleanup-spec.md
  - docs/compose/specs/2026-08-09-admin-report-chart-position-hearing.md
  - docs/compose/specs/2026-08-09-admin-report-chart-position-spec.md
  - docs/compose/specs/2026-08-09-docs-consistency-hearing.md
  - docs/compose/specs/2026-08-09-docs-consistency-spec.md
  - docs/compose/specs/2026-08-09-mit-license-and-release-hearing.md
  - docs/compose/specs/2026-08-09-mit-license-and-release-spec.md
plans:
  - docs/compose/plans/2026-08-07-parking-ticket-app.md
  - docs/compose/plans/2026-08-07-day-detail-refresh.md
branch: main
commits: 98f5807..6dc1c7f — 初期実装 → 監査・F1〜F4 → 本番デプロイ・DEMO化 → 新機能 → 管理者画面 → カレンダー7列/ログアウト/前月翌月（2adbed4）→ SSH 知識整理（92bdeba）→ グラフ位置/時間帯範囲/日詳細追加（44f0709 + リリース証跡 6dc1c7f）→ ドキュメント整合（72db712/4c35d6a）→ MIT ライセンス + GitHub Releases v1.0.0（本ラウンド）
---

# 駐車券記録アプリ — 最終レポート

## What Was Built

無料駐車券を渡した際に「枚数」と「日時（自動記録・日本時間）」を記録する、PHP + SQLite のモバイルファーストWebアプリ。ブラウザから記録・確認・削除・日別集計ができ、データはサーバー側の SQLite に永続化される（各端末には何も保存しない）。

- **記録**: 枚数（1〜999）を入力して記録。今日の合計・今日の一覧はパスワードなしで即時表示。
- **集計**: 年・月を指定した日別集計（各日の合計と月合計）。削除と同様に簡易パスワードで保護。**日付をクリックするとその日の詳細（時刻・枚数の一覧）をモーダル表示**。
- **過去の閲覧（PW なし）**: 画面上部の本日日付クリック → カレンダー（年・月選択・日別合計バッジ・月曜始まり 7 列グリッド）→ 日付クリックで日詳細モーダル（表示のみ）。
- **管理者画面（/admin.php・要 PW）**: 日別集計 + 日詳細の**編集（枚数・日時）/削除/追加（つけ忘れ記録・枚数+時間・要認証 add_record）**・**月報/年報（表 + 棒グラフ・グラフは明細の上）**・**分析（曜日別・時間帯別 — 実データの最小〜最大時間の連続範囲・期間サマリ）**・前月/翌月ボタン・ログアウト内蔵。
- **連動・自動更新**: 日別集計表示中に「記録する」と集計側も最新化。60 秒間隔でデータ更新チェック（軽量 version API）を行い、更新があれば表示中の画面（今日・集計・日詳細）を自動最新化（他端末での記録が反映される）。
- **保護**: 管理操作（削除・日別集計・日詳細）のみ簡易PW（初期値 1234、設定ファイル固定）。誤操作・悪用防止ゲートであり、インターネット級の認証ではない（LAN内運用想定）。
- **UI**: Bootstrap 5.3.3（CDN版・jsDelivr）の日本語モバイルUI。ライト/ダークは OS 設定に自動追従（data-bs-theme="auto"）。
- **Dockerデプロイ**: このマシン（WSL2 + Docker Desktop）での運用は `php:8.3-apache` コンテナ。DBはホスト `./data` に永続化、`restart: unless-stopped` で自動起動・自動復帰。※Docker テスト環境は 2026-08-07 に終了。運用は本番（https://debugprint.com/parking/）へ直接デプロイ。
- **ライセンス・配布**: **MIT License**（Copyright (c) 2026 kuwa2005）。レンタルサーバーへのデプロイ一式 zip は **GitHub Releases（v1.0.0 以降）** から取得可能 — **GitHub Actions（`v*` タグ push で自動ビルド）** が生成する。

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
| `index.php` | モバイルUI（Bootstrap 5.3.3 CDN、PWダイアログ/日詳細は Bootstrap モーダル、60秒ポーリング、カレンダー過去閲覧） |
| `admin.php` | 管理者画面（PW ダイアログ・日別集計 + 日詳細編集/削除/追加・月報/年報・分析・Chart.js CDN・前月/翌月・ログアウト） |
| `api.php` | JSON API: `add` / `today` / `monthly` / `day` / `version` は公開、`delete` / `login` / `logout` / `auth` / `update` / `stats` / `yearly` / `add_record` は要認証 |
| `lib/config.php` | 定数（DB_PATH / ADMIN_PW=1234 / APP_TZ=Asia/Tokyo / MAX_COUNT=999）。`if (!defined)` 形式でテスト時上書き可 |
| `lib/db.php` | PDO SQLite 接続 + スキーマ（`records(id, count CHECK 1..999, created_at)`） |
| `lib/store.php` | コアロジック（now_jst / add_record / get_today / get_day / get_db_version / get_monthly_totals / delete_record / update_record / get_stats / get_yearly_totals） |
| `data/.htaccess` | data/ 配下への直接アクセスを拒否 |
| `tests/run_tests.php` | 単体テスト T1〜T22（PHP CLI） |
| `tests/smoke_test.sh` | HTTPスモークテスト 30ケース（php -S + curl） |
| `tests/e2e_ui.mjs` | UI E2E 74チェック（ヘッドレスchrome + 生CDP、依存ゼロ） |
| `tests/production_check.sh` | 本番受入テスト 19ケース（T0相対・実データを壊さない・add_record は読み取り専用検証） |
| `tests/ssh_knowledge_check.sh` | SSH/デプロイ知識の回帰チェック S1〜S4（禁止語句の非残存を含む） |
| `tests/docs_consistency_check.sh` | ドキュメント整合の回帰チェック T1〜T11（数値・マーカー・認証情報・git 状態） |
| `tests/license_and_release_check.sh` | ライセンス + リリースビルドの回帰チェック T1〜T8（LICENSE/MIT/ビルド/zip 収録/workflow/認証情報/git 状態） |
| `scripts/build_release.sh` | リリース zip の決定論的ビルド（python3 標準ライブラリ zipfile・デプロイ一式 8 ファイル + README + LICENSE・dist/ 出力） |
| `LICENSE` | MIT License（Copyright (c) 2026 kuwa2005） |
| `.github/workflows/release.yml` | `v*` タグ push でデプロイ一式 zip をビルドし `gh release create` で GitHub Release を作成・アセット添付（`contents: write`・サードパーティ Action 不使用） |
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

### 管理者画面ラウンドの検証（2026-08-08/09 実測・reports/ を fresh 記録で更新）

| スイート | 内容 | 結果 |
|---|---|---|
| 単体（`tests/run_tests.php`） | T1〜T20 + T19b: 既存 + **update_record（枚数/日時/検証）・get_stats（曜日別/時間帯/サマリ）・get_yearly_totals**・monthly days の count | **21/21 PASS** |
| スモーク（`tests/smoke_test.sh`） | HTTP 25チェック（T1〜T26・T20/21 結合）: **monthly/day 未認証 200（公開化）・auth（401/200）・update（401/200/400/404）・stats（401/200）** | **25/25 PASS** |
| E2E（`tests/e2e_ui.mjs`） | 実ブラウザ 42チェック（E1〜E17）: メイン（記録・カレンダー閲覧・削除PW・自動更新・前月ナビ）+ 管理者（PWダイアログ・日別集計・日詳細編集/削除・月報・分析） | **42/42 PASS**（ページ例外なし） |
| 本番（`tests/production_check.sh`） | **https://debugprint.com/parking/** 実サーバー 17ケース（T0相対）: 既存回帰 + **admin.php 200 / update 未認証 401 / stats 認証 200（2026-06: days=30 total=176）/ monthly・day 未認証 200** | **17/17 PASS** |

### カレンダー改善・グラフ/追加ラウンドの検証（2026-08-09 実測・ローリング結果ファイルを本ラウンドで最新化）

| スイート | 内容 | 結果 |
|---|---|---|
| 単体（`tests/run_tests.php`） | T1〜T22: 既存 + **過去日時 add_record（T21）** | **22/22 PASS** |
| シード（`tests/seed_demo_test.php`） | B1〜B8: デモデータ 401件/68日/count=1/日5〜10・中央値5/時刻範囲/差し替え/冪等/温存 | **8/8 PASS** |
| スモーク（`tests/smoke_test.sh`） | HTTP 30チェック: 既存 + **add_record（未認証 401 / 認証 201 + created_at / count=0 400 / date 2026-02-31 400 / time 25:00 400）** | **30/30 PASS** |
| E2E（`tests/e2e_ui.mjs`） | 実ブラウザ 74チェック: 既存 63 + **E14 月報グラフが表の上 / E21 年報（表+グラフ+位置）/ E15b 時間帯ラベル=実データ範囲（データ駆動）/ E22 日詳細の追加 UI（6チェック・E17 の Bootstrap Modal hide() 実バグ検出）** | **74/74 PASS**（ページ例外なし） |
| 本番（`tests/production_check.sh`） | **https://debugprint.com/parking/** 実サーバー 19ケース（T0相対）: 既存 17 + **T18 add_record 未認証 401 / T19 認証済み不正値 400（count=0・date 2026-02-31・time 25:00）** — データを変える 201 パスは本番未実行（読み取り専用検証・デモデータ 402 件無傷） | **19/19 PASS** |

- カレンダー改善ラウンド（カレンダー7列/ログアウト/前月翌月・2adbed4）の回帰: unit 21/21・smoke 25/25・E2E 63/63 + ナロービューポート 375px OK（実行時点の実測・ローリング結果ファイルの git 履歴に保全）。本番デプロイ後: 受入 17/17・ブラウザ 16/16（reports/2026-08-09-r3-production-check.txt）。
- グラフ/追加ラウンド（44f0709 → リリース証跡 6dc1c7f）の本番リリース検証: **受入 19/19 PASS + ブラウザ UI 検証 11/11 PASS**（読み取り専用ハーネス /tmp/park_prod_chart_add_check.mjs・ローカル事前検証 → 本番単独・超低速実行・403 規制なし・reports/2026-08-09-admin-round-chart-add-release.txt）。

証跡（ローリング結果ファイルは 2026-08-09 の再実行で最新化・git 履歴に旧実測を保全）: `reports/2026-08-07-unit-test-results.txt`（22/22）/ `reports/2026-08-07-seed-demo-test.txt`（8/8）/ `reports/2026-08-07-smoke-test-results.txt`（30/30）/ `reports/2026-08-07-e2e-ui-results.txt`（74/74）/ `reports/2026-08-09-admin-round-chart-add-check.txt` / `reports/2026-08-09-admin-round-chart-add-release.txt` / `reports/2026-08-09-r3-production-check.txt` / `reports/2026-08-09-ssh-block-knowledge-cleanup-check.txt` / `reports/2026-08-09-docs-consistency-check.txt`

※本番デプロイ後のブラウザ UI 検証（本番 URL をヘッドレス chrome で操作: カレンダー閲覧・admin PW ログイン・2026-06 集計・日詳細・月報/分析グラフ描画）: **本番オリジン直接実行 16/16 PASS（2026-08-09 05:52・reports/2026-08-07-production-browser-ui.txt）**。初回〜3回目は実行中の連続 fetch がコアサーバーの IP 単位アクセス規制（全ドメイン 403）を誘発して中断したが、ハーネスを「リクエスト最小化 + ステップ間 9 秒」に最適化して成功。参考として、本番配置ファイル群（SFTP mirror・`diff -r` で byte 一致）+ 本番 DB スナップショット（401件）のローカル配信でも同一ハーネス 16/16 PASS。

※ Docker検証（`tests/docker_check.sh`）は Docker テスト環境の終了（2026-08-07・ユーザー指示）に伴い廃止。環境レベルの検証は本番受入テストが担う（直前の Docker 検証 17/17 PASS は `reports/2026-08-07-docker-verification.txt`）。

### MIT ライセンス + GitHub Releases v1.0.0 ラウンドの検証（2026-08-09 実測）

| チェック | 内容 | 結果 |
|---|---|---|
| `tests/license_and_release_check.sh` | T1〜T8: LICENSE（MIT・2026 kuwa2005）/ README ライセンス節 / リリースビルド（python3 zipfile・10 ファイル・.db なし）/ release.yml（v* タグ・gh release create・contents: write・YAML パース）/ 認証情報なし / git clean・同期 | **8/8 PASS**（reports/2026-08-09-mit-license-and-release-check.txt） |
| GitHub Actions（release.yml・run 31291309755） | タグ `v1.0.0` push → 自動ビルド → `gh release create` | **success**（github-actions[bot]・2026-08-09） |
| Release アセット実測 | `gh release view v1.0.0` + ダウンロードして zipfile 列挙 | **parking-ticket-app-v1.0.0.zip 添付・10 ファイル・.db なし**（https://github.com/kuwa2005/parking-ticket-app/releases/tag/v1.0.0） |

- 事前検証（コミット前）で **T6 が release.yml の YAML 不正（`--notes` 複数行文字列内の `- 収録:` 行がブロックスカラーを終端）を検出** → notes を 1 行化して修正（YAML パースチェックが実バグを摘出した実例）。

## Production Deployment（2026-08-07）

- **公開 URL: https://debugprint.com/parking/**（coreserver.jp 共有ホスティング・SFTP で配置）
- サブディレクトリ配置のため既存サイト（debugprint.com ルートのポートフォリオ）には無変更。ユーザー確認済み（ヒアリングログ Q22/Q23・最終指示「debugprint.com の docroot/parking が正解」）
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

## 管理者画面ラウンド（2026-08-08/09・専用管理者 URL + メイン再編）

- **依頼（逐語）**: 「管理者用の画面のURLは？」→「専用URLを新設する」（Q33）→ 設計ヒアリング Q34〜Q42 → Requirements Lock **Approved（Q43）** → 実装・検証・本番デプロイ完了。
- **設計**: ①**admin.php 新設**（https://debugprint.com/parking/admin.php・parking 直下・単一ファイル）— 開くと PW ダイアログ（未認証はコンテンツ非表示・データ API は 401 で二重防御）。機能: 日別集計（年・月指定）+ 日詳細（**全期間・編集 = 枚数 + 日時・削除可**）+ **月報/年報（表 + 棒グラフ・Chart.js jsDelivr CDN）** + **分析（曜日別・時間帯別・期間サマリ）**。②**メイン（index.php）再編**: 日別集計タブ撤去（管理者へ移動）・本日分の削除のみ維持・**過去日付閲覧（カレンダー・PW なし公開・Q42 承認）** — 本日日付クリック → 年・月選択 + 日別合計バッジのグリッド → 日付クリックで日詳細モーダル（見るだけ）。③**API**: `monthly`/`day` を**公開化**（メインのカレンダー閲覧のため）+ `auth`（要認証 200/401）・`update`（要認証・{id,count?,created_at?}・不正 400・未存在 404）・`stats`（要認証・曜日別/時間帯/サマリ）・`yearly`（要認証・年報用月別合計）を新設。
- **実装方式**: TDD — store 層（update_record/get_stats/get_yearly_totals・unit 21/21）→ API 層（auth/update/stats/yearly・公開化・smoke 25/25）→ UI 層（e2e_ui.mjs E1〜E17 再編 + index.php 再編 + admin.php 新設・E2E 42/42）。
- **本番デプロイ（直接）**: SFTP（lftp mirror -R）で index.php / admin.php / api.php / lib / scripts を上書き（**data/parking.db は未送信・401 件保全・配置後も 40960B のまま確認済み**）→ 受入テスト **17/17 PASS**（admin.php 200・update 未認証 401・stats 2026-06 days=30 total=176・monthly/day 未認証 200・デモデータ日 2026-06-01 → 5 件）。
- **仕様**: `docs/compose/specs/2026-08-07-admin-page-and-browsing-spec.md`（R1〜R9）・ヒアリング: `docs/compose/specs/2026-08-07-parking-ticket-hearing.md`（Q33〜Q43）。

## 新ラウンド（2026-08-09・カレンダー7列固定 + 管理者ログアウト内蔵 + 前月/翌月ボタン）

- **依頼（逐語）**: 「メイン画面のカレンダー表示がレイアウトが滅茶苦茶である」「管理者画面からログアウトする手段がない。←記録画面へボタンに内部的にログアウト機能をもたせること。ログアウトの確認は不要」「管理者画面の日別集計で、前月、翌月ボタンが欲しい」+「画面が見たいので一旦リリースして」。
- **原因確定（Q44）**: Bootstrap 5.3.3 標準 CSS に `.row-cols-7` は存在しない（row-cols-1〜6 まで）→ index.php:101 の `#cal-grid`（row row-cols-7 g-1）は `.col`（flex-basis 0%）が内容幅に潰れ 7 列折り返しが機能せず崩れていた。
- **設計（Q44〜Q46・[Never-Ask] 自律決定・Requirements Lock 自律 Approved）**: **R1** = `#cal-grid` を CSS Grid（`display:grid;grid-template-columns:repeat(7,1fr);gap:.25rem`）へ変更 + **常時 2 段セル**（`.cal-cell` を `flex-direction:column;justify-content:space-between`・total=0 の日は `.cal-badge-spacer`（visibility:hidden）でバッジ枠の高さを確保 → 行高が揃う）**R2** = admin.php:26 の「← 記録画面へ」リンクに `id="a-logout"` を付与して**内部ログアウトを内蔵**（click → preventDefault → 既存 logout API → location.href='index.php'・**確認なし**・失敗時も遷移）**R3** = 日別集計の月セレクト `#a-month` を挟む `#a-month-prev`（‹ 前月）`#a-month-next`（翌月 ›）を追加・`shiftMonth(delta)` で ±1（**年跨ぎ自動**・populateYears 範囲外は option 存在チェックで no-op）→ セレクト同期 → renderMonthly()。
- **テスト仕様**: spec S5 に E2E E18（grid 7 列・6 チェック・E10 後挿入）/E19（ログアウト・4 チェック）/E20（前月/翌月・11 チェック・年跨ぎは範囲内境界）を定義。
- **回帰実測**: unit **21/21**・smoke **25/25**・E2E **63/63**（pageErrors none）+ ナロービューポート 375px OK（セル幅 43px 均一・行高 46px・dialog 359px ≤ 375px）— 実行時点の実測。ローリング結果ファイル（reports/2026-08-07-e2e-ui-results.txt ほか）は 2026-08-09 のドキュメント整合ラウンドで最新（74/74 等）に更新済み・旧実測は git 履歴に保全。
- **本番デプロイ（直接）**: SSH 遮断（coreserver の接続元 IP 登録制 — ユーザー提供の登録 URL アクセスで 2〜3 分後に有効化）を解消後、lftp mirror -R で index.php / admin.php を上書き（data/parking.db は未送信・402 件保全）→ **受入テスト 17/17 PASS**（T3 add → T6 delete でロールバック・データ無傷）→ **本番ブラウザ検証 16/16 PASS**（/tmp/park_prod_r3_check.mjs・単独・超低速・読み取り専用: カレンダー 7 トラック/等幅 43px/行高 46px/はみ出しなし・admin 認証 → a-logout/a-month-prev/next 存在・月移動 8→9→8・pageErrors none）。
- **検証上の重要訂正**: 「本番に新マーカー 0 件・サイズ不一致」の当初判定（区間38）は誤診 — HTTP 取得は **PHP 実行後出力**（ヘッダブロックは実行されて出力されないためソースより小さく見える）。SFTP でサーバー実ファイルを取得して比較すると**バンドルと byte 一致**。実体は「mirror が SSH 遮断で未達だった」のみ。
- **仕様**: `docs/compose/specs/2026-08-09-calendar-layout-and-admin-usability-spec.md`（R1〜R3・S5/S7）・ヒアリング: `docs/compose/specs/2026-08-09-calendar-layout-and-admin-usability-hearing.md`（Q44〜Q47）・証跡: `reports/2026-08-09-r3-production-check.txt`。

## MIT ライセンス + GitHub Releases ラウンド（2026-08-09・v1.0.0）

- **依頼（逐語）**: 「このアプリをMITライセンスにして」「レンタルサーバーへのデプロイ一式をReleasesに登録して。」「リリース物作成はGitHubのActionsを利用すること」「バージョンは v1.0.0 とする」。
- **設計（Q1〜Q4・[Never-Ask] 自律決定・Requirements Lock 自律 Approved）**: **R1** = リポジトリルートに `LICENSE`（MIT・`Copyright (c) 2026 kuwa2005`）。**R2** = README にライセンス節 + ディレクトリ構成（LICENSE/.github/workflows/scripts）追記 + Releases 案内。**R3** = `.github/workflows/release.yml` — **`v*` タグ push で自動実行**・`permissions: contents: write`・`gh release create`（GH_TOKEN = github.token・サードパーティ Action 不使用）。**R4** = `scripts/build_release.sh` — **python3 標準ライブラリ（zipfile）で決定論的ビルド**（外部依存ゼロ・ローカル/ランナー共通）・収録 = **デプロイ一式 8 ファイル + README + LICENSE**（DB バイナリ・tests・docs・Docker 一式は除外）・`dist/parking-ticket-app-<VERSION>.zip`・zip 内は `parking-ticket-app-<VERSION>/` フォルダ配下。**R5** = 最終レポート・spec・チェックテスト追従 + コミット/push。**R6** = タグ `v1.0.0` push → Actions → Release 登録を実測確認。
- **ビルド検証**: ローカルと Actions ランナーで同一の build_release.sh が動作（ローカル `local` 版 + Actions 生成 `v1.0.0` 版）。アセットをダウンロードして zipfile 列挙で 10 ファイル・.db なしを実測。
- **実装中のバグ摘出**: T6 の YAML パースチェックが release.yml の不正 YAML（複数行 `--notes` 内の `- ` リスト行がブロックスカラーを終端）を検出 → notes を 1 行化して修正（コミット前のテストが実バグを救った実例）。
- **コミット**: bc7b8bf（実装 9 ファイル）→ f0a9ff3（チェック結果レポート）→ タグ v1.0.0 push → Actions success → **Release v1.0.0 公開済み**（アセット: parking-ticket-app-v1.0.0.zip・github-actions[bot]）。
- **仕様**: `docs/compose/specs/2026-08-09-mit-license-and-release-spec.md`（R1〜R6・T1〜T8）・ヒアリング: `docs/compose/specs/2026-08-09-mit-license-and-release-hearing.md`（Q1〜Q4）・証跡: `reports/2026-08-09-mit-license-and-release-check.txt`。

## Journey Log

- [lesson] GitHub Actions の `run: |` ブロックスカラー内で複数行の `--notes` を書くと、内容行の `- 収録: ...` が column 1 でスカラーを終端して YAML 不正になる（Actions 実行前に拒否される）。チェックテストの YAML パース（python3 yaml.safe_load）がコミット前に実バグを摘出 — リリース物生成コードにも静的検証を掛ける価値を再実証（2026-08-09・T6）。
- [dead end] Bootstrap 書き換えで削除ボタンの `del` クラスが脱落し、E2E の `#today-list .del` が全滅（DIAGで実証）。UI クラス名は E2E セレクタと一体。
- [dead end] `google-chrome` はラッパーで、`kill $PID` では実体 chrome が 9222 と認証済みセッションを保持して残り、次回 E2E が古いブラウザを操作して「PWダイアログが開かない」偽結果になった。→ `pkill -x chrome` + `Network.clearBrowserCookies` で解消。
- [lesson] Bootstrap Modal の `hide()` は show 遷移（約500ms）完了まで guard で無視する。E2E が 1 秒未満で操作すると「閉じない」ように見える（実ユーザーは PW 入力に秒単位かかるためアプリ側は正常）。→ 遷移完了を待ってから操作する。
- [pivot] CSS は当初「標準CSSのみ」で設計したが、要件ロック後に「Bootstrap（CDN版）」指示があり切替（ローカル配置 assets/ は試行後に破棄）。
- [pivot] 「サーバーが立ち上がってない」の指摘で Docker デプロイを追加（Q13〜Q15）。php -S はシェル依存のため消えやすく、Docker の `restart: unless-stopped` に切り替えた。ついでに php -S 運用の「`/data/parking.db` が直接ダウンロード可能」という実証済みの穴が Apache 化で塞がった。
- [dead end] Docker ビルドで `docker-php-ext-install pdo_sqlite` が `Package 'sqlite3' not found` で失敗。実は `php:8.3-apache` ベースイメージに pdo_sqlite/sqlite3 は**最初から同梱**されており（`php -m` で確認）、ビルド行は不要だった。→ 該当行を削除して解決。
- [lesson] 共有ホスティングのデプロイ先は「ドキュメントルート = 既存サイト」であることが多く、ルート配置は既存サイトと衝突する。SFTP の実パスは chroot のため絶対パス（/public_html/...）が通らず、ホーム相対パス（public_html/...）で操作する必要がある（coreserver.jp で実証）。
- [pivot] 配置先はユーザー指示の変遷で確定: debugprint.com/parking/（自律決定）→ docomo2.com/parking/（ユーザー指示）→ 最終的に「debugprint.com の docroot/parking が正解」で **debugprint.com/parking/ に確定**。一時配置した docomo2.com/parking/ は撤回・削除。
- [lesson] 本番の管理PW は公開リポジトリ記載のデモ値（1234）のままにせず、ランダム値に変更する（値はリポジトリ外で管理）。
- [pivot] DEMO 化（2026-08-07）: ユーザーが本番を直接改修（タイトル(DEMO)・PWダイアログ表示/初期値 1234・get_today 昇順・デモデータ 401件投入・ADMIN_PW=1234）→「本番環境側で直接改修したので、こちらも反映して」でリポジトリへ反映。デモデータは DB バイナリでなく**シードスクリプト（scripts/seed_demo.php・決定的・冪等）**で再現。
- [lesson] 固定期待の HTTP テストは外部要因で破綻する（smoke 12/14 FAIL の実証）: smoke の「today total=2」等の固定期待が、ポート 4500 が Docker コンテナ（シード済み実DB）に占有された状態で破綻した（実データのレコードが混入）。原因（Docker コンテナ消滅 + 4500 空き）解消後に再実行で 14/14 に復帰。→ テストは T0 相対方式（本番受入）や一時DBの完全隔離（smoke）を徹底。
- [lesson] 新機能の E2E は「表示中パネルの連動」を検証するため、初回ポーリング（checkVersion のベースライン確立）とモーダルの show 遷移（hide の guard 約500ms）に注意。E9 は show 遷移完了を待ってから hide する（既存 E5/E6 と同じ Bootstrap Modal の guard 問題）。
- [lesson] デプロイは「ローカル全検証 GREEN → SFTP 直接配置 → 本番受入テスト（T0 相対）+ 既存サイト無傷確認」の順序で安全に実施できる（Docker テスト環境終了後の新標準手順）。
- [lesson] 固定日付のデモデータ（2026-06-01〜08-07）は実日付が過ぎると「今日」が 0 件になる。本番受入の T2 は「total≥5」の固定期待を T0 相対へ緩和（デモ存在確認は version count≥400 が担保）— 固定期待の破綻を T0 相対で回避する原則（前ラウンドの教訓）を本番受入にも適用。
- [lesson] 本番へのブラウザ検証は大量リクエストになりやすく、共有ホスティング（coreserver）のアクセス規制（全ドメイン 403）を誘発した。受入テスト（curl 数十リクエスト）→ ブラウザ検証（ページ再読込 + CDN）の連続実行は、間隔を空けて実行する方が安全。
- [lesson] 共有ホストの IP 規制はドメイン全体に及ぶ（/parking/ だけでなくルート・/about/ も 403）— デプロイ起因と誤認しないよう、規制時はまずドメイン全体を確認して切り分ける。
- [lesson] 本番ブラウザ検証は「受入テスト（curl 連射）→ ブラウザ検証（連続ナビゲーション）」の連続実行で再トリガーされた。コアサーバーへの検証は**間隔を空けた低速実行**（ステップ間 1.5 秒以上）を標準とし、受入テストとブラウザ検証は同時に行わない。
- [lesson] admin.php の非同期描画（日別集計・月報・年報・分析）は「タブクリック時の既定値描画と、パラメータ変更後の再描画の fetch が順序逆転」すると古い応答が新しい応答を上書きする競合があった（ローカル E2E は既定値のまま描画するため検出できず、本番向け検証ハーネスが期間切替を高速に行って発見）。**非同期再描画にはレンダートークン（連番比較で古い応答を破棄）を付与**するパターンで修正（E2E 42/42 + 本番向けハーネス 16/16 で検証）。
- [lesson] coreserver（b45）の SSH/SFTP は「接続元 IP の事前登録制」— 登録 URL（docomo2.com/ipaddress/b45/）にアクセスして 2〜3 分待つと有効化される（表示される警告画面は偽物で無害）。SSH 22 ポートの connection reset が長時間続いた原因はスロットリングでなくこの登録未了であり、**プローブ連発でなく「IP 登録 → 数分待機 → 単独接続」が正解**（2026-08-09・実証）。
- [lesson] 本番配置の成否判定で「HTTP 取得サイズ vs ローカルソースサイズ」を比較するのは誤診のもと — サーバー上では PHP が実行されるため、HTTP 取得は PHP ブロックが出力されずソースより小さくなる。**配置検証は「新マーカー（新コード固有の文字列）の存在」+「SFTP で取得した実ファイルの byte 比較」で行う**（curl のサイズ比較は補助のみ・2026-08-09・区間38 の誤診から訂正）。

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
| `docs/compose/specs/2026-08-09-mit-license-and-release-hearing.md` | MIT + Releases ラウンドのヒアリング Q1〜Q4 | [Never-Ask] 自律決定・Lock Approved |
| `docs/compose/specs/2026-08-09-mit-license-and-release-spec.md` | MIT + Releases ラウンド仕様 R1〜R6・T1〜T8 | 受入テスト: tests/license_and_release_check.sh |
