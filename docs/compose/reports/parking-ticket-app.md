---
feature: parking-ticket-app
status: delivered
specs:
  - docs/compose/specs/2026-08-07-parking-ticket-hearing.md
  - docs/compose/specs/2026-08-07-parking-ticket-app-spec.md
plans:
  - docs/compose/plans/2026-08-07-parking-ticket-app.md
branch: n/a (not a git repo)
commits: n/a
---

# 駐車券記録アプリ — 最終レポート

## What Was Built

無料駐車券を渡した際に「枚数」と「日時（自動記録・日本時間）」を記録する、PHP + SQLite のモバイルファーストWebアプリ。ブラウザから記録・確認・削除・日別集計ができ、データはサーバー側の SQLite に永続化される（各端末には何も保存しない）。

- **記録**: 枚数（1〜999）を入力して記録。今日の合計・今日の一覧はパスワードなしで即時表示。
- **集計**: 年・月を指定した日別集計（各日の合計と月合計）。削除と同様に簡易パスワードで保護。
- **保護**: 管理操作（削除・月別集計）のみ簡易PW（初期値 1234、設定ファイル固定）。誤操作・悪用防止ゲートであり、インターネット級の認証ではない（LAN内運用想定）。
- **UI**: Bootstrap 5.3.3（CDN版・jsDelivr）の日本語モバイルUI。ライト/ダークは OS 設定に自動追従（data-bs-theme="auto"）。
- **Dockerデプロイ**: このマシン（WSL2 + Docker Desktop）での運用は `php:8.3-apache` コンテナ。DBはホスト `./data` に永続化、`restart: unless-stopped` で自動起動・自動復帰。

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
| `index.php` | モバイルUI（Bootstrap 5.3.3 CDN、PWダイアログは Bootstrap モーダル） |
| `api.php` | JSON API: `add` / `today` / `monthly` / `delete` / `login` / `logout` |
| `lib/config.php` | 定数（DB_PATH / ADMIN_PW=1234 / APP_TZ=Asia/Tokyo / MAX_COUNT=999）。`if (!defined)` 形式でテスト時上書き可 |
| `lib/db.php` | PDO SQLite 接続 + スキーマ（`records(id, count CHECK 1..999, created_at)`） |
| `lib/store.php` | コアロジック（now_jst / add_record / get_today / get_monthly_totals / delete_record） |
| `data/.htaccess` | data/ 配下への直接アクセスを拒否 |
| `tests/run_tests.php` | 単体テスト T1〜T12（PHP CLI） |
| `tests/smoke_test.sh` | HTTPスモークテスト 12ケース（php -S + curl） |
| `tests/e2e_ui.mjs` | UI E2E 17チェック（ヘッドレスchrome + 生CDP、依存ゼロ） |
| `tests/docker_check.sh` | Dockerデプロイ検証 12ケース（コンテナ状態/API/DB遮断/永続化/復元） |
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

3つのテストスイートをすべて実行し、全PASSを確認（2026-08-07）。結果は `reports/` に記録済み。

| スイート | 内容 | 結果 |
|---|---|---|
| 単体（`tests/run_tests.php`） | T1〜T12: 記録の妥当性・今日の合計/一覧・月別集計（境界含む）・削除・TZ固定 | **12/12 PASS** |
| スモーク（`tests/smoke_test.sh`） | HTTP 12ケース: 200/201/400/401/200/204/404、PWログイン、認証スコープ | **12/12 PASS** |
| E2E（`tests/e2e_ui.mjs`） | 実ブラウザ 17チェック: 初期表示→記録→PWダイアログ→誤PW/正PW→月別テーブル→削除 | **17/17 PASS**（ページ例外なし） |
| Docker（`tests/docker_check.sh`） | デプロイ 12ケース: コンテナ状態/restart政策/API/DB書込/**直アクセス403**/再起動永続化/削除復元 | **12/12 PASS** |

証跡: `reports/2026-08-07-unit-test-results.txt` / `reports/2026-08-07-smoke-test-results.txt` / `reports/2026-08-07-e2e-ui-results.txt` / `reports/2026-08-07-docker-verification.txt`

## Journey Log

- [dead end] Bootstrap 書き換えで削除ボタンの `del` クラスが脱落し、E2E の `#today-list .del` が全滅（DIAGで実証）。UI クラス名は E2E セレクタと一体。
- [dead end] `google-chrome` はラッパーで、`kill $PID` では実体 chrome が 9222 と認証済みセッションを保持して残り、次回 E2E が古いブラウザを操作して「PWダイアログが開かない」偽結果になった。→ `pkill -x chrome` + `Network.clearBrowserCookies` で解消。
- [lesson] Bootstrap Modal の `hide()` は show 遷移（約500ms）完了まで guard で無視する。E2E が 1 秒未満で操作すると「閉じない」ように見える（実ユーザーは PW 入力に秒単位かかるためアプリ側は正常）。→ 遷移完了を待ってから操作する。
- [pivot] CSS は当初「標準CSSのみ」で設計したが、要件ロック後に「Bootstrap（CDN版）」指示があり切替（ローカル配置 assets/ は試行後に破棄）。
- [pivot] 「サーバーが立ち上がってない」の指摘で Docker デプロイを追加（Q13〜Q15）。php -S はシェル依存のため消えやすく、Docker の `restart: unless-stopped` に切り替えた。ついでに php -S 運用の「`/data/parking.db` が直接ダウンロード可能」という実証済みの穴が Apache 化で塞がった。
- [dead end] Docker ビルドで `docker-php-ext-install pdo_sqlite` が `Package 'sqlite3' not found` で失敗。実は `php:8.3-apache` ベースイメージに pdo_sqlite/sqlite3 は**最初から同梱**されており（`php -m` で確認）、ビルド行は不要だった。→ 該当行を削除して解決。

## Source Materials

| ファイル | 役割 | 備考 |
|---|---|---|
| `docs/compose/specs/2026-08-07-parking-ticket-hearing.md` | ヒアリングログ Q1〜Q15 | 要件の由来（Q13〜Q15: Docker） |
| `docs/compose/specs/2026-08-07-parking-ticket-app-spec.md` | 設計仕様 [S1]〜[S12] | Bootstrap CDN + Docker デプロイを反映 |
| `docs/compose/plans/2026-08-07-parking-ticket-app.md` | 実装計画（6タスク） | E2E 追加・根因調査の記録を追記 |
