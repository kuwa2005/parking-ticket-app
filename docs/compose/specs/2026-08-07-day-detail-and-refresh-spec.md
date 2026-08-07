# 日付クリック詳細 + 集計連動更新 + 自動更新チェック仕様 — 要件・テスト仕様

- 日付: 2026-08-07
- 依頼: ①「日別集計で日付をクリックしたらその日の詳細が見られるようにして」②「日別集計表示時、記録するを押下したら集計表示側も更新して」③「時々データが更新されていないかチェックし、更新されていたら最新を表示して。」④「本番環境が構築されたので、dockerテスト環境は終了。本番環境に直接デプロイして、本番環境側で確認して。」（ヒアリングログ Q27〜Q31・[Never-Ask] 自律決定・Requirements Lock 取得後）
- 前提: DEMO 化反映済み（コミット 571fd22・get_today 昇順・デモデータ 401件・ADMIN_PW=1234）。本番 = https://debugprint.com/parking/。

## [S1] 問題と目的

日別集計（年・月指定の日別テーブル）は「日付と枚数の合計」しか表示されない。どの時刻に何枚記録されたかは今日の一覧でしか見られず、過去日にさかのぼって確認できない。また、複数端末で同時に使う場合、片方の端末で記録してももう片方の表示（今日・集計）は更新されず、手動で再表示が必要だった。

目的:
- 集計表の日付をクリックすると、その日の記録一覧（時刻・枚数）をモーダルで表示する
- 日別集計を表示中に「記録する」を押すと、集計側も最新化する
- 一定間隔でデータの更新有無をチェックし、更新があれば表示中の画面（今日・集計・日詳細）を最新化する

## [S2] 要件

| # | 要件 |
|---|---|
| R1 | 日別集計テーブルの各行（日付）をクリック可能にし、その日の記録一覧（時刻 HH:MM・枚数・時間昇順）を Bootstrap モーダルで表示する（Q27: モーダル） |
| R2 | 日詳細 API はセッション認証中のみ応答する（Q28: 日別集計と同じ保護。未認証は 401） |
| R3 | 日詳細は表示のみ（削除ボタンなし・Q29）。削除導線は従来どおり今日の一覧のみ |
| R4 | 日別集計表示中に「記録する」で記録が成功したら、表示中の集計テーブルも再取得して更新する |
| R5 | 日詳細モーダル表示中にデータが更新されたら、モーダル内容も最新化する（R7 の仕組みに含む） |
| R6 | 60 秒間隔でデータ更新チェックを行い、更新があれば表示中の画面（今日一覧 / 日別集計 / 日詳細モーダル）を最新化する（Q30: 60秒・表示中のみ） |
| R7 | 更新チェックは軽量な API（`action=version`）を利用し、前回値（レコード数 + 最大 id）と比較して変化時のみ再取得する |
| R8 | 日詳細の日付入力は `YYYY-MM-DD` 形式のみ許可（形式不正は 400）。集計テーブル以外からの直接呼び出しも安全 |
| R9 | 本番（https://debugprint.com/parking/）へ直接デプロイし、本番環境側で受入確認する（Q31・data/parking.db は保全・ダウンタイム許容） |
| R10 | 既存テストスイート（単体・スモーク・E2E）を回帰させ、新規テスト（day API・version API・UI連動）を含めて全 PASS |
| R11 | Docker テスト環境は終了済みのため、Docker 関連の検証は実施しない（docker_check.sh は廃止扱い・README 記載済み） |

## [S3] API 設計

### `GET api.php?action=day&date=YYYY-MM-DD`（要認証）

- 認証: `require_auth()`（未認証 401）
- 入力: `date` = `^\d{4}-\d{2}-\d{2}$`（それ以外は 400）
- 応答 200: `{"date":"YYYY-MM-DD","total":N,"records":[{"id":..,"count":..,"created_at":".."}]}`（時間昇順・同刻 id 昇順 — get_today と同じ並び）
- 該当日が無ければ `total:0, records:[]`（200）
- 実装: `lib/store.php` に `get_day(PDO $db, string $date): array` を追加し、`get_today` は `get_day($db, $now->format('Y-m-d'))` に委譲（重複ロジック削除）

### `GET api.php?action=version`（認証不要）

- 応答 200: `{"count":N,"maxId":M}`（レコード総数 + 最大 id。データ更新の検出用）
- 実装: `lib/store.php` に `get_db_version(PDO $db): array` を追加（`SELECT COUNT(*), COALESCE(MAX(id),0) FROM records`）
- 用途: 60 秒ポーリングで前回値と比較。変化があれば表示中のパネルを再取得（R6/R7）

## [S4] UI 設計（index.php）

### 日付セルのクリック化

- `loadMonthly` の日付セル（`td`）を `<td class="text-start day-link">` とし、クリックで `openDayDetail('YYYY-MM-DD')` を呼ぶ
- 見た目: Bootstrap のリンク色（`text-primary`）+ `text-decoration: underline` を付与してクリック可能を明示

### 日詳細モーダル

- 既存 PW モーダルと同様の `modal fade modal-dialog-centered` 構成。id は `day-dialog`
- タイトル: `8月3日（3件・5枚）` 形式（日付・件数・合計枚数）
- 本文: 記録一覧（時刻 `HH:MM`・`N 枚`・`text-body-secondary small`）— 今日一覧と同じ行スタイル（`.record-row`）だが削除ボタンなし
- 空の日: 「記録がありません」を表示
- 開閉: 集計テーブルのみが起点（直接 URL 遷移はない）

### 集計連動（R4）

- `add-btn` 成功時: `loadToday()` に加え、`panel-month` が表示中なら `loadMonthly()` も実行。日詳細モーダルが開いていれば `openDayDetail(表示中日付)` を再実行して内容更新

### 自動更新ポーリング（R6/R7）

- 起動時と以後 60 秒ごとに `action=version` を取得し、前回値（count+maxId）と比較
- 変化時: `loadToday()` + （集計表示中なら `loadMonthly()`）+ （日詳細モーダル表示中ならその日付を再取得）
- 比較用の前回値はモジュール変数 `lastVersion` に保持。初回は取得のみ（表示変更なし）
- ポーリング関数は `window.__refreshNow` に公開（E2E から即時実行して連動を検証するため）

## [S5] エラー処理

- day API の不正 date → 400 `{"error":"invalid date"}`
- day API 未認証 → 401 `{"error":"unauthorized"}`（monthly と同じ挙動）
- version API は認証不要・常に 200
- ポーリング失敗（ネットワーク断等）は無視して次の間隔で再試行（UI にエラー表示しない）

## [S6] テスト仕様

### 単体テスト（tests/run_tests.php・既存 T1〜T12 に追加）

| # | 内容 | 期待 |
|---|---|---|
| T13 | `get_day` が指定日の記録を時間昇順で返す | 追加順 = 時刻昇順 |
| T14 | `get_day` が存在しない日付で `total:0, records:[]` を返す | 空配列 |
| T15 | `get_day` の日付境界（該当日のみ含む・前後日は含まない） | 0 件/該当件 |
| T16 | `get_db_version` が count と maxId を返す | 追加後 count+1・maxId 更新 |

### HTTP スモーク（tests/smoke_test.sh・既存 14 ケースに追加）

| # | 内容 | 期待 |
|---|---|---|
| 15 | `action=day` 未認証 → 401 | 401 |
| 16 | `action=day&date=YYYY-MM-DD` 不正形式（`2026/08/07` 等）→ 400 | 400 |
| 17 | ログイン後 `action=day&date=<本日の日付>` → 200 で今日のレコードを含む | 200 + total≥2 |
| 18 | `action=version` → 200 で count≥2・maxId≥1 | 200 |
| 19 | 削除後に `action=version` の count が減る | 変化を確認 |

### UI E2E（tests/e2e_ui.mjs・既存 17 チェックに追加）

| # | 内容 | 期待 |
|---|---|---|
| E9 | 日別集計の日付セルクリック → 日詳細モーダルが開き、その日の行（時刻+枚数）を表示 | モーダル表示・件数一致 |
| E10 | 日別集計表示中に「記録する」→ 集計テーブルの合計が更新される | 合計変化 |
| E11 | `window.__refreshNow()` 実行後、他パネル（今日一覧）が最新化される（ポーリング連動の検証） | 表示更新 |

### 本番受入（tests/production_check.sh + 追加確認）

- 既存 T1〜T10（T0 相対）を再実行し 10/10 PASS
- 追加: `action=version` 200 / `action=day` 認証なし 401 / 認証後 200・デモデータの日（例: 2026-06-01）に 5〜10 件表示

## [S7] デプロイ手順（本番）

1. ローカルで全テスト（unit/smoke/E2E）GREEN を確認
2. SFTP（lftp・相対パス `public_html/debugprint.com/parking/`）で以下を上書き配置:
   - `index.php` / `api.php` / `lib/config.php` / `lib/db.php` / `lib/store.php` / `data/.htaccess`（現行と同一）
   - `scripts/seed_demo.php`（参考配置・実行しない）
3. `data/parking.db` は**上書きしない**（本番デモデータ 401 件を保全）
4. 本番で `tests/production_check.sh`（T0 相対）を実行し 10/10 PASS + 新機能確認（day/version API・UI）
5. 既存ポートフォリオ（https://debugprint.com/ ルート）が無傷であることを確認

## [S8] 非目標・注意

- 日詳細からの削除は実装しない（Q29）
- 集計テーブル以外からの日詳細表示（今日一覧から過去日へ遷移等）は今回のスコープ外
- 更新チェック間隔は固定 60 秒（設定 UI は作らない）
- 本番 DB はデモデータのため、day/version API の実測値はデモデータ前提（テストは相対/範囲検証）
- 認証情報（SFTP PW 等）はドキュメント・レポートに記載しない

## [S9] 検証証跡

- reports/2026-08-07-unit-test-results.txt（12→16 ケース）
- reports/2026-08-07-smoke-test-results.txt（14→19 ケース）
- reports/2026-08-07-e2e-ui-results.txt（17→25 チェック・実測）
- reports/2026-08-07-production-verify.txt（本番受入・新機能確認）
