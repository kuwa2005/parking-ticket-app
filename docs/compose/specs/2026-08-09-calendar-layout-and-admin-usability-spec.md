# 仕様 — カレンダーレイアウト修正・管理者ログアウト・日別集計の前月/翌月ボタン（2026-08-09）

H1 直下 NOTE: 本仕様の実装計画は [`../plans/2026-08-09-calendar-layout-and-admin-usability-plan.md`](../plans/2026-08-09-calendar-layout-and-admin-usability-plan.md)、最終レポートは [`../reports/parking-ticket-app.md`](../reports/parking-ticket-app.md)。

ヒアリングログ: [2026-08-09-calendar-layout-and-admin-usability-hearing.md](2026-08-09-calendar-layout-and-admin-usability-hearing.md)（Q44〜Q46）

## [S1] Problem

ユーザーから 3 件の要求/報告が同時に発生した:

1. **メイン画面のカレンダー表示がレイアウト崩壊**（Q44）: `#cal-grid` が Bootstrap `row row-cols-7 g-1` で実装されているが、**Bootstrap 5.3.3 標準 CSS に `.row-cols-7` が存在しない**（標準は row-cols-1〜6 まで・`$grid-row-columns: 6`）。実測ではヘッダーと全日付セルが同一行に横並びし、セル幅 10〜25px に潰れる。
2. **管理者画面にログアウト手段がない**（Q45）: 「← 記録画面へ」は通常リンクでセッションを破棄しない。ユーザー指示: このボタンにログアウトを内蔵・確認不要。
3. **日別集計に前月/翌月ボタンがない**（Q46）: 月移動がセレクト 2 回操作のみ。ワンクリック移動が欲しい。

## [S2] R1 — カレンダー 7 列固定レイアウト（index.php）

- `#cal-grid` のクラスを `row row-cols-7 g-1 text-center` から**素の div（`text-center` のみ）**へ変更し、CSS で固定 7 列を定義する:
  ```css
  #cal-grid{display:grid;grid-template-columns:repeat(7,1fr);gap:.25rem}
  ```
- ヘッダー行（月〜日）と日付セルは現行どおり同じグリッド内に 7 個ずつ並び、自動で折り返す（子はすべて 1 セル = 1 列）。
- `.cal-cell` の崩れ対策:
  - `min-height:44px` を維持（grid の行は行内最大高に自動で揃う）。
  - **バッジの有無で行の高さが揃うよう、セルを常時 2 段構造にする**: `flex-direction:column; justify-content:space-between` とし、total=0 の日もバッジ用の空要素を置く（`visibility:hidden` で高さを確保）。これにより「バッジがある日だけ行が高くなる」不均一が消える。
- 既存の表示仕様（月曜始まり・`data-date`/`data-day` 属性・total>0 のみバッジ表示・今日 `today` 強調・セルクリックで日詳細）は**変更しない**。
- 月移動（`#cal-prev`/`#cal-next`/年・月セレクト）と `renderCalendar()` のロジックは変更しない。

## [S3] R2 — 管理者ログアウト（admin.php）

- admin.php 26 行目の「← 記録画面へ」を `<a href="index.php" id="a-logout">` に変更（見た目は現行ボタンどおり）。
- クリック時の動作（確認ダイアログなし）:
  1. `preventDefault` で通常遷移を止める
  2. `fetch('api.php?action=logout', { method: 'POST' })` を呼び出しセッションを破棄（api.php の `case 'logout'` は method 非依存・`$_SESSION = []; session_destroy();`）
  3. `location.href = 'index.php'` で記録画面へ遷移
- ログアウト失敗時（ネットワーク異常等）も `location.href` で遷移する（記録画面への導線を妨げない）。
- 以後、admin.php を開くと PW ダイアログが再表示される（`$_SESSION['auth']` 未設定のため）— 仕様どおり。

## [S4] R3 — 日別集計の前月/翌月ボタン（admin.php）

- 日別集計パネル（`#a-monthly-panel`）の月セレクト `#a-month` の横にボタン 2 個を追加:
  - `#a-month-prev` = `‹ 前月`（`btn btn-outline-secondary btn-lg flex-shrink-0`）
  - `#a-month-next` = `翌月 ›`（同クラス）
  - 配置はメインカレンダー（`#cal-prev`/`#cal-next`）と同型の `d-flex gap-2` 内。レイアウト崩れを避けるため、モバイル幅ではセレクト+ボタンが 1 行に収まるよう `flex-wrap` を許容する。
- クリック時の動作:
  1. 現在の `#a-month` 値を ±1 する
  2. 年跨ぎを自動処理: 1 月の前月 → `#a-year` を前年に変更し月 = 12 / 12 月の翌月 → `#a-year` を翌年に変更し月 = 1
  3. セレクトの `value` を同期（`#a-year` の選択肢は populateYears で nowYear-10〜nowYear のため、範囲内の年跨ぎのみ有効。範囲外（nowYear の 12 月で翌月 = nowYear+1）は何もしない）
  4. `renderMonthly()` を実行（既存の表示ボタン・change リスナーと同じ経路で表と集計を再描画）
- 表示ボタン `#a-month-btn`・年/月セレクトは現行どおり維持。

## [S5] テスト仕様

テストは既存テストスイートに**追加**する形で実施（既存ケースの回帰も必須）。

### [S5.1] カレンダーレイアウト（E2E 追加: E18）

e2e_ui.mjs に追加。デモ相当データ（当月に数件 add）がある状態でカレンダーを開き、CDP `Runtime.evaluate` で検査:

- E18a: `#cal-grid` の computed `display` = `grid`・`gridTemplateColumns` が 7 トラック
- E18b: 1 行目（ヘッダー月〜日）の 7 セルの x 座標が等間隔・幅が grid 幅の約 1/7（±10%）
- E18c: 日付セルは 7 列ずつ折り返す（2 行目以降の先頭セルの x 座標が 1 行目先頭と一致・y が増加）
- E18d: 同一行内のセル高さが一致（バッジ有無で高さがバラバラにならない）
- E18e: バッジ表示セルでも `scrollWidth <= clientWidth`（はみ出しなし）

### [S5.2] 管理者ログアウト（E2E 追加: E19）

- E19a: admin.php を開き PW ログイン → `#admin-content` が表示される
- E19b: `#a-logout`（記録画面へ）をクリック → index.php に遷移
- E19c: 再度 admin.php を開く → **PW ダイアログが表示される**（`#a-pw-dialog` が show・`#admin-content` が hidden = セッション破棄の確認）

### [S5.3] 日別集計の前月/翌月（E2E 追加: E20）

- E20a: admin ログイン → 日別集計タブで年・月を 2026-06 に設定し表示 → `#a-month-prev` クリック → `#a-month` の value が 5・`#a-year` が 2026・表が再描画（タイトル/行数が 2026-05 の内容）
- E20b: `#a-month-next` ×2 クリック → 2026-07 に移動（+1 ずつ・セレクト同期）
- E20c: 年跨ぎ: `#a-month` を 1 に設定して表示 → `#a-month-prev` → `#a-year` が前年・`#a-month` が 12 に変化
- E20d: 12 月の翌月: `#a-month` を 12 に設定して表示 → `#a-month-next` → `#a-year` が翌年・`#a-month` が 1

### [S5.4] 回帰

既存スイートを全件再実行（変更は index.php/admin.php の UI 層のみで、api.php/lib は変更しない）:

- unit: `php tests/run_tests.php` → 21/21 維持（実測 21/21 PASS）
- smoke: `bash tests/smoke_test.sh` → 25/25 維持（実測 25/25 PASS）
- E2E: `node tests/e2e_ui.mjs` → 既存 42/42 + 追加分（E18〜E20 = 21 件）が全て PASS・pageErrors none（**実測 63/63 PASS**・reports/2026-08-07-e2e-ui-results.txt）
- ナロービューポート（375px 相当・CDP Emulation.setDeviceMetricsOverride）でカレンダーを開き、7 列・等幅・行高統一・モーダル収まり・バッジはみ出しなしを確認（**実測 OK**・tracks=7・セル幅 43px 均一・行高 46px 均一・dialog 359px ≤ 375px）

## [S6] 非目標

- カレンダーのデザイン刷新（配色・サイズ等）— 現行デザインの意図を維持し崩れのみ修正
- ログアウト確認ダイアログ・ログアウト専用ボタン・タイムアウト自動ログアウト
- 日別集計以外のタブ（月報/年報/分析）への前月/翌月ボタン
- モバイル専用の追加表示調整（7 列のまま、崩れないことのみ保証）

## [S7] 検証と成功基準

- ローカル（php -S + 一時 DB + シード済み 401 件）で E2E を実行し、E18〜E20 + 既存 42 件が全て PASS すること（**実測: 63/63 PASS・pageErrors none**・reports/2026-08-07-e2e-ui-results.txt）
- unit/smoke の回帰（21/21・25/25）が維持されること（**実測: 21/21・25/25 PASS**）
- ブラウザ実測（CDP）で「7 列固定・行高統一・バッジはみ出しなし」を確認（**実測: E18a〜e 全 PASS — grid 7 トラック・ヘッダー等幅 63px・間隔 67px 均一・折返し y=112→145・行高 46px 統一・バッジはみ出しなし**。ナロービューポート 375px でも 7 列・セル幅 43px 均一・行高 46px・dialog 359px ≤ 375px）
- 本番（https://debugprint.com/parking/）へ再配置後、本番受入 17/17 と読み取り専用ブラウザ検証（管理者ログアウトはデータ非破壊のため含められる場合は含む）で確認する
