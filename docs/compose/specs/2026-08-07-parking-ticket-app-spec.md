# 駐車券記録アプリ — 仕様書

> [!NOTE]
> This document may not reflect the current implementation.
> See the final report for up-to-date state:
> [Final Report](../reports/parking-ticket-app.md)

- 日付: 2026-08-07
- ステータス: 要件確定待ち（Requirements Lock）
- 関連文書: [ヒアリングログ](./2026-08-07-parking-ticket-hearing.md)

---

## [S1] 目的とスコープ

無料駐車券を渡した際に「枚数」と「日時」を記録する、店舗カウンター向けのシンプルなWebアプリ。
スマートフォンのブラウザから操作し、記録はサーバー側のSQLiteデータベースに集約保存する。端末には一切データを保存しない。

**主要ユースケース**
1. 従業員が客に駐車券を渡したとき、枚数を入力して記録（自動で現在日時が付与される）。
2. 今日の合計枚数と今日の記録一覧を常時確認。
3. 誤って記録した分を削除（要パスワード）。
4. 過去の日別合計を年・月を指定して確認（要パスワード）。

## [S2] 制約と非機能要件

| 項目 | 要件 |
|---|---|
| ランタイム | PHP（PDO SQLite対応）。できる限り汎用的なレンタルサーバーで動作させる。 |
| 拡張機能 | 標準的なPHP+PDO SQLiteのみ使用。特殊な拡張・ビルド手順を要しない。 |
| データ保存 | サーバー側SQLiteファイル。クライアント端末には保存しない。 |
| タイムゾーン | Asia/Tokyo 固定（コード内で設定し、ホストのTZ設定に依存しない）。 |
| ネットワーク | LAN内利用を前提。ポート4500で稼働。 |
| 認証 | 記録・閲覧（今日分）はPWなし。削除・日別集計は簡易PW(初期値 1234)。 |
| UI | モバイルファースト、日本語。大きなタップ領域。 |
| 保守性 | PHP以外の依存は Bootstrap 5.3.3 のみ（CDN版・jsDelivr参照）。デプロイはファイルコピーのみ。 |

**セキュリティ方針**: 簡易PWの用途は「店内LAN内での誤操作・悪用防止」。インターネット公開を想定しない。DBアクセスは全件プリペアドステートメント、画面描画は textContent によるエスケープ済み出力（XSS対策）、data/ ディレクトリは .htaccess で直接アクセスを拒否。

## [S3] データモデル

SQLiteデータベース `data/parking.db`、テーブル `records`:

```sql
CREATE TABLE IF NOT EXISTS records (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  count      INTEGER NOT NULL CHECK (count BETWEEN 1 AND 999),
  created_at TEXT    NOT NULL  -- 'Y-m-d H:i:s'（Asia/Tokyo のローカル時刻）
);
CREATE INDEX IF NOT EXISTS idx_records_created_at ON records (created_at);
```

- `count`: 1〜999 の整数。APIでも検証する。
- `created_at`: サーバーが記録時に自動付与。フォーマット `Y-m-d H:i:s`（JST）。
- 日付境界（「今日」「何日」）はすべて JST の `created_at` 文字列の日付部分で判定する。

## [S4] アーキテクチャとファイル構成

```
park/
  index.php            # 単一ページUI（HTML+CSS+JS を内包、モバイルファースト）
  api.php              # JSON API（HTTP層・セッション/PW検証のみ担当）
  lib/
    config.php         # 設定定数（DB_PATH, ADMIN_PW, APP_TZ）※テスト時に上書き可能
    db.php             # PDO接続 + スキーマ初期化
    store.php          # コアロジック（HTTPに依存しないテスト可能な関数群）
  data/
    .htaccess          # 外部からの直接アクセス拒否
    parking.db         # 実行時に自動作成（gitignore対象）
  tests/
    run_tests.php      # テストハーネス（PHP CLI、依存なし）
  docs/compose/specs/  # 本仕様書・ヒアリングログ
  reports/             # テスト結果レポート
```

**関心の分離**: `store.php` はPDOと純粋関数のみ（HTTP/SESSIONに非依存）で、テストハーネスから直接呼び出せる。`api.php` はリクエスト解析・PW検証・JSON応答のみ。`index.php` は fetch で `api.php` を呼ぶ。

**テスト時のDB切替**: `config.php` は `if (!defined('DB_PATH'))` 形式で定義する。テストは `DB_PATH` を一時ファイルに define してから読み込むことで、本番DBを汚さずに検証できる。

## [S5] API仕様（すべて JSON、UTF-8）

`api.php` は `action` クエリパラメータで処理を分岐。レスポンスは `application/json`。

### 5.1 記録の追加（PW不要）

```
POST api.php?action=add
Body: {"count": <1..999の整数>}
```

- 成功: `201` `{"id": 12, "count": 3, "created_at": "2026-08-07 14:32:05"}`
- 検証エラー（countが整数でない・1未満・999超・欠落）: `400` `{"error": "..."}`
- サーバーエラー: `500` `{"error": "..."}`

### 5.2 今日の記録と合計（PW不要）

```
GET api.php?action=today
```

- 成功: `200`
  ```json
  {"date": "2026-08-07", "total": 12, "records": [{"id": 12, "count": 3, "created_at": "2026-08-07 14:32:05"}, ...]}
  ```
- `records` は新しい順（created_at 降順、同刻は id 降順）。`total` は今日の合計枚数。

### 5.3 日別合計（要PW）

```
GET api.php?action=monthly&year=2026&month=8
```

- PW未認証: `401` `{"error": "unauthorized"}`
- 成功: `200`
  ```json
  {"year": 2026, "month": 8, "days": [{"date": "2026-08-01", "total": 0}, ..., {"date": "2026-08-07", "total": 12}, ...]}
  ```
- `days` はその月の全日（1日〜月末）を日付昇順で返し、記録のない日は `total: 0`。日付は `Y-m-d`。
- パラメータ検証: `year` は 2000〜2100 の整数、`month` は 1〜12 の整数。不正は `400`。

### 5.4 記録の削除（要PW）

```
DELETE api.php?action=delete&id=12
```

- PW未認証: `401` `{"error": "unauthorized"}`
- 成功: `204`（ボディなし）
- 対象レコードなし: `404` `{"error": "not found"}`

### 5.5 ログイン/ログアウト

```
POST api.php?action=login
Body: {"pw": "1234"}
```

- PW一致: `200` `{"ok": true}`（PHPセッションに認証フラグ設定）
- PW不一致: `401` `{"error": "unauthorized"}`
- 比較は `hash_equals` を使用。セッションCookieは HttpOnly / SameSite=Lax。
- 認証はセッション有効期間中（既定のセッションライフタイム）保持される。

```
POST api.php?action=logout
```
- 成功: `200` `{"ok": true}`（セッション破棄）

## [S6] UI仕様（index.php・モバイルファースト）

**画面構成（1ページ・日本語）**

1. **ヘッダー部**: アプリ名「駐車券 記録」、今日の日付。
2. **今日の合計**: 大きな数字で表示（例: 「今日の合計 12 枚」）。
3. **記録フォーム**: 枚数 number 入力（初期値 1、min=1、max=999、`inputmode="numeric"` で数字キーパッド表示）+ 大きな「記録する」ボタン。ボタン押下で即時API登録し、成功後は入力値をリセットし一覧・合計を更新。クライアント側でも 1〜999 を検証。
4. **今日の記録一覧**: 「14:32 — 3枚」形式のリスト。各行に削除ボタン（🗑）。押下時、未認証ならPW入力ダイアログを表示し、認証後に削除実行。
5. **日別集計セクション（タブ切替）**: 年セレクト・月セレクト・「表示」ボタン。未認証ならPWダイアログを表示。認証後、指定月の日別合計テーブル（日付 | 枚数）を表示。
6. **PWダイアログ**: モーダル。数字入力 + 「確定」。失敗時はエラーメッセージ表示。

**デザイン**: CSSフレームワークは Bootstrap 5.3.3（CDN版・jsDelivr参照）。`data-bs-theme="auto"` によりライト/ダークを端末設定に追従。タップ領域は Bootstrap 標準コンポーネント（btn / btn-lg / form-control-lg 等）で確保。PWダイアログは Bootstrap モーダル、フォントはシステムUI。アプリロジックは標準JS（フレームワーク不使用）。

**データ更新**: 記録後は「今日の合計」と「今日の一覧」を自動再取得。ページを開いたときにも今日のデータを取得。

## [S7] エラーハンドリング

| ケース | 挙動 |
|---|---|
| count 不正（0以下・1000以上・非数値・欠落・小数） | `400` + エラーメッセージ。UIではダイアログ/入力欄のエラー表示 |
| 不正な year/month | `400` + エラーメッセージ |
| PW未認証で削除・集計を実行 | `401`。UIではPWダイアログを表示 |
| 削除対象が存在しない | `404`。UIでは「既に削除済み」メッセージ + 一覧更新 |
| JSONリクエストがパース不能 | `400` |
| DBエラー | `500`。UIでは汎用エラーメッセージ |
| ネットワークエラー | クライアント側でエラーメッセージ表示（記録失敗時は入力値を保持） |

## [S8] テスト仕様（必須・合格条件）

テストは `tests/run_tests.php`（PHP CLI、外部依存なし）で実行する。`DB_PATH` を一時ファイルに設定した `store.php` を直接呼び、assertで検証する。実行結果は各テスト行 + 合計を出力し、全PASSで exit 0、1件でも失敗で exit 1。結果を `reports/` にも記録する。

### テストケース

| # | テスト | 期待結果 |
|---|---|---|
| T1 | 記録追加（正常）: count=3 | id・count・`created_at`（`Y-m-d H:i:s`形式）が返る。DBに1件存在 |
| T2 | 記録追加（異常）: 0, -1, 1000, 1.5, "abc", "", 欠落 | すべて拒否（null または例外） |
| T3 | 今日の合計: 3枚+2枚+1枚 | total=6 |
| T4 | 今日の一覧: 順序 | created_at 降順（同刻は id 降順）で返る |
| T5 | 月別集計: 2026-08 指定 | 8/1〜8/31 の全日を返し、記録日の total が正しく、記録のない日は 0 |
| T6 | 月別集計: 別月除外 | 7月・9月のレコードは8月の集計に含まれない |
| T7 | 月別集計: パラメータ検証 | year=1999 / 2101、month=0 / 13 / 非数値 → 不正扱い |
| T8 | 日付境界: 23:59:59 と 00:00:00（JST） | それぞれ正しい日付に分類される |
| T9 | 削除（正常） | 削除後、一覧・合計から消える |
| T10 | 削除（存在しないID） | 失敗（false）を返す |
| T11 | TZ設定 | `date_default_timezone_get()` が Asia/Tokyo になる |
| T12 | タイムスタンプ形式 | `created_at` が `Y-m-d H:i:s` の正規表現に一致 |

### HTTPスモークテスト（verify工程で実行）

`php -S 0.0.0.0:4500` で起動し、curl で以下を検証する（結果を reports/ に記録）。

1. `index.php` が `200` で「駐車券」を含むHTMLを返す
2. `POST add` count=2 → `201`、`GET today` の total に反映
3. `POST add` count=0 → `400`
4. `GET monthly` 未認証 → `401`
5. `POST login` 誤PW → `401`、正PW(1234) → `200`（cookie保持）
6. `GET monthly` 認証済み → `200`、days に記録日の total 反映
7. `DELETE` 未認証 → `401`、認証済み → `204`、再削除 → `404`
8. `GET today` 削除後 → 合計から減算

**合格条件**: T1〜T12 すべてPASS、かつ HTTPスモークテストの全ケースが期待結果どおり。

### UI E2Eテスト（verify工程で実行・実績追記）

`tests/e2e_ui.mjs`（依存ゼロ: ヘッドレスchrome + 生CDP + Node組み込みWebSocket）で実ブラウザのUI操作を検証する。E1〜E8 の17チェック（初期表示 / 記録→合計・行表示 / 月別タブ→PWダイアログ表示 / 誤PWエラー / 正PW→ダイアログ閉鎖・月別テーブル合計 / 削除→合計減算・空メッセージ復帰）。**実績: 17/17 PASS（reports/2026-08-07-e2e-ui-results.txt）**。

## [S9] 非目標（Non-goals）

- ユーザー別ログイン・権限管理
- インターネット公開・HTTPS対応・多要素認証（LAN内簡易PWの範囲）
- CSV/Excelエクスポート（サーバー永続化によりバックアップはDBファイル管理で代替）
- グラフ・統計表示
- 編集（既存レコードの枚数変更）— 誤りは削除して再登録する運用
- 多言語対応

## [S10] デプロイ方法

**ローカル（開発・検証）**
```
php -S 0.0.0.0:4500 -t /home/ubuntu/workspace/park
```
スマホは `http://<サーバーIP>:4500` でアクセス。※このマシンでの常時運用は [S12] Docker を使用する（php -S は検証用。php -S では data/.htaccess が無効のため `/data/parking.db` がダウンロード可能になる点に注意）。

**レンタルサーバー（一般的なPHPホスティング）**
1. アプリ一式をドキュメントルート（public_html 等）にアップロード。
2. `data/` ディレクトリがPHPプロセスから書き込み可能であることを確認（必要に応じて chmod 775 / ディレクトリ所有者変更）。
3. `data/.htaccess` により DB ファイルへの直接アクセスは拒否される（Apache環境）。
4. DBパスを変更したい場合は `lib/config.php` の `DB_PATH` を編集（例: ドキュメントルート外のディレクトリを指定）。
5. PWを変更したい場合は `lib/config.php` の `ADMIN_PW` を編集。
6. Bootstrap は CDN（jsDelivr）参照のため、アプリはPHPファイルのみのアップロードで動作する。完全オフラインのLANで使う場合は Bootstrap をローカル配置（assets/）に切り替える。

**起動確認**: ブラウザで `http://<ホスト>:4500/` を開き、記録→一覧反映→削除（PW）→月別集計（PW）の一連が動作することを確認。

## [S12] Dockerデプロイ（要件ロック後の追加要件）

このマシン（WSL2 + Docker Desktop）での運用は Docker コンテナで行う（Q13〜Q15）。

**構成**:
- `Dockerfile`: `php:8.3-apache` ベース。`docker-php-ext-install pdo_sqlite` で SQLite 拡張を追加。`docker-php-ext-enable` 不要（pdo_sqlite はビルド時に有効化される）。
- `docker-compose.yml`: ポート `4500:80`、ボリューム `./data:/var/www/html/data`、`restart: unless-stopped`。
- エントリポイント: 起動時に `data/` の所有権を `www-data:www-data` に調整してから Apache を起動（バインドマウントされたホスト側ディレクトリは uid が異なるため）。

**要件**:
1. DBはホスト `./data` に永続化（コンテナ再作成でデータ消失しない）。
2. 自動起動・自動復帰（`restart: unless-stopped`）。docker デーモン起動時に自動起動、クラッシュ時は自動再起動。
3. `data/.htaccess`（deny-all）が Apache 環境で機能し、`/data/parking.db` への直接アクセスは 403。※php -S 運用では .htaccess が無効のため DB がダウンロード可能だった（実証済みの穴）が、Apache 化で解消。
4. ブラウザアクセスは従来どおり `http://<ホスト>:4500/`（4500→コンテナ80にマッピング）。
5. アプリコードは共有ホスティング用のまま（Docker はこのマシン用の追加デプロイ手段であり、PHP の実行環境は同一構成の Apache + pdo_sqlite）。

**起動 / 停止**:
```
docker compose up -d --build   # ビルド＆起動（自動復帰付き）
docker compose down            # 停止（データは ./data に残る）
```

## [S11] 成功基準

1. スマホブラウザから記録操作ができ、即座に今日の合計・一覧に反映される。
2. 削除・日別集計は PW(1234) 入力後にのみ操作できる。
3. サーバー再起動後も記録が保持される（SQLite永続化）。
4. 年・月を指定した日別合計が正しく表示される。
5. `tests/run_tests.php` の T1〜T12 がすべてPASSし、HTTPスモークテストも全ケース期待どおり。
6. モバイルファーストの日本語UIで快適に操作できる。
