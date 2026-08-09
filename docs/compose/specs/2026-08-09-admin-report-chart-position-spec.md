# 管理者画面 改修（グラフ位置・時間帯範囲・過去日への記録追加）— 仕様

> NOTE: 実装・検証の結果は ../reports/2026-08-09-admin-round-chart-add-check.txt に記録する（ヒアリングログ: ./2026-08-09-admin-report-chart-position-hearing.md）。

- 日付: 2026-08-09
- 依頼（ユーザー逐語）:
  1. 「管理者画面の日報、月報、年報に表示されているグラフは明細の上に移動して」
  2. 「分析の時間帯別（枚数）の時間帯は、２４時間は不要。実データに基づいて最小時間、最大時間より表示幅（時間）を決めて」
  3. 「日別集計で各日付をクリックした詳細画面に、「追加」ボタンを。あとから、その日につけ忘れたけど管理者権限で記録を追加したい。に対応。枚数と時間を入力。日付は選択されている日付」

## [S1] 問題

admin.php に 3 件の機能/表示上の課題がある。

1. **月報・年報タブのグラフ位置**: 現在「年/月セレクト → 明細テーブル → グラフ」の順で表示されており、グラフを明細（表）の上に表示したい（Q1 自律決定: 日別集計タブ・分析タブは対象外）。
2. **分析タブの時間帯別グラフ**: 0時〜23時 の 24 バーを常時表示しているが、実データの時間範囲だけを表示したい（Q2 自律決定: 最小〜最大の連続範囲・範囲内の 0 枚時間帯は 0 として表示）。
3. **過去日への記録追加手段がない**: 記録の追加はメイン画面（index.php）の「今日」のみ。日別集計の日詳細は閲覧・編集・削除のみで、過去日に記録を追加する手段がない（「その日につけ忘れた記録を管理者権限で追加したい」に対応できない）。

## [S2] 解決方針

admin.php の HTML/JS と api.php の新アクション追加（store.php は add_record が日時引数対応済みのため無変更）。index.php・メイン画面は無変更。

- **R1: 月報タブのグラフ位置** — 現在の順序「`#a-mreport-table` → `<h3>日別合計の推移</h3>` + `#a-mreport-chart`」を「`<h3>` + `#a-mreport-chart` → `#a-mreport-table`」に変更（表の上にグラフ）。JS（renderMonthlyReport）・API は無変更 — 描画ロジックは DOM 順序に依存しない。
- **R2: 年報タブのグラフ位置** — 現在の順序「`#a-yreport-table` → `<h3>月別合計の推移</h3>` + `#a-yreport-chart`」を「`<h3>` + `#a-yreport-chart` → `#a-yreport-table`」に変更（表の上にグラフ）。JS（renderYearlyReport）・API は無変更。
- **R3: 分析タブの時間帯別グラフの表示範囲** — `renderAnalysis`（admin.php:537-557）内で、`data.hour`（24 件・各 {count,sum}）の **sum > 0 の最小 hour（hMin）と最大 hour（hMax）** を求め、`hourLabels`（`i + '時'`）とデータを `[hMin..hMax]` にスライスして `drawChart('hour', ...)` に渡す（連続範囲・間の 0 枚時間帯は 0 として表示）。`data.summary.total === 0` の場合は既存の早期 return（「記録がありません」表示）で hMin/hMax の未定義ケースは発生しない。曜日別グラフ（0〜6 固定）・期間サマリは無変更。
- **R4: 日別集計の日詳細に「追加」ボタン（過去日への記録追加・管理者権限）**:
  - **UI**: `#a-day-dialog`（日詳細）に「追加」ボタンを追加。クリックで新規モーダル `#a-add-dialog`（既存 `#a-edit-dialog` と同型の Bootstrap Modal）を開き、タイトルで日付（YYYY-MM-DD）を明示。入力は「枚数」（number・1〜999・既存と同じバリデーション）+「時間」（type="time"・HH:MM・分単位・必須・Q3 自律決定）。確定で POST → 成功後、日詳細一覧 + 日別集計テーブルを再描画（既存の編集/削除後の再描画と同一経路・Q4 自律決定で別モーダル方式）+ toast「追加しました」。キャンセル/閉じるで破棄。作成日時 = 選択中の日付 + 入力時間（秒は 00 正規化・JST）。
  - **API**: 新アクション `case 'add_record'` — **`require_auth()`（管理者権限・ユーザー指示どおり）**。POST body `{count: int, date: 'YYYY-MM-DD', time: 'HH:MM'}`。検証: count は 1〜MAX_COUNT（is_int・既存 add と同じ）/ date は `^\d{4}-\d{2}-\d{2}$` + `checkdate()` で実在日付 / time は `^\d{2}:\d{2}$` + 時 0〜23・分 0〜59。成功 201 `{id, count, created_at}`・検証エラー 400・未認証 401。`add_record($db, $count, new DateTimeImmutable("$date $time:00", APP_TZ))` を呼ぶ（store は日時引数対応済み・無変更）。
  - 既存の公開 `add` アクション（今日のみ・無認証）は無変更 — バックデート追加は必ず要認証の新アクション経由（認証条件の分岐が無くバイパス不能）。
- セレクト行（年/月 + 表示ボタン）は最上部のまま。グラフ描画はパネル表示後に実行される既存フロー（bindTab → render）を維持。見出し・高さ（220px）・CSS クラス等は維持。

## [S3] 非目標

- 日別集計タブへのグラフ新規追加（「表示されているグラフ」の移動のみ）
- 分析タブの曜日別グラフ・期間サマリ・集計データ（API stats）の変更
- 時間帯の間引き（「記録がある時間のみ」表示）— 最小〜最大の連続範囲（Q2 自律決定）
- メイン画面（index.php）の日詳細（公開・見るだけ）への追加ボタン — 依頼は日別集計（管理者画面）のみ（Q1/続報「日別集計」で確定）
- 既存 `add` アクション（今日のみ・公開）の仕様変更・過去日への公開追加
- store.php / DB スキーマの変更

## [S4] テスト仕様

テストプログラム: `tests/run_tests.php`（単体）・`tests/smoke_test.sh`（HTTP）・`tests/e2e_ui.mjs`（CDP 駆動 E2E）。E2E は空 DB から開始しテスト中に記録を追加するため、時間帯の期待値は**同じ API（stats）を再取得して最小/最大時間を再計算し Chart の labels と照合するデータ駆動方式**とする（タイムゾーン・シード非依存）。

- **T1: 月報タブでグラフが表の上** — E2E（E14 内に追加）: `#a-mreport-panel` 内で `#a-mreport-chart` が `#a-mreport-table` より前（`compareDocumentPosition` の FOLLOWING ビット）。
- **T2: 年報タブでグラフが表の上** — E2E（新規）: `#atab-yreport` アクティブ化 → 表表示（`#a-yreport-table.hidden === false`）・グラフ描画（`#a-yreport-chart.width > 0`）+ パネル内で chart が table より前。
- **T3: 時間帯別グラフが実データの最小〜最大のみ（R3）** — E2E（E15 内に追加）: `stats` API を再取得して sum > 0 の hMin/hMax を計算し、`Chart.getChart('a-hour-chart').data.labels` が「`[hMin..hMax]` の連続範囲（件数 = hMax−hMin+1・先頭 = hMin時・末尾 = hMax時）」であること・24 バーでないことを検証。
- **T4: 追加 API の動作（R4）** — 単体（tests/run_tests.php に追加）: `add_record` に過去の日時（DateTimeImmutable）を渡すとその created_at で挿入される。スモーク（tests/smoke_test.sh に追加）: ①未認証で `action=add_record` → 401 ②ログイン後 → 201 で指定日時（YYYY-MM-DD HH:MM:00）のレコード ③count=0/1000 → 400 ④date 形式不正（2026-02-31・bad）→ 400 ⑤time 形式不正（25:00・bad）→ 400。
- **T5: 追加 UI の動作（R4）** — E2E（新規）: admin ログイン → 日別集計タブ → 日付クリックで日詳細 → 「追加」クリック → モーダルに枚数 + 時間を入力 → 確定 → 日詳細一覧に新しい行（時刻・枚数一致）が増える + 日別集計テーブルのその日合計が更新される + 編集/削除ボタンが行にある。
- **T6: 既存機能の回帰** — 表・グラフが従来どおり描画（E14 既存チェック・E15 既存チェック）+ 全既存 E2E チェック PASS。
- **T7: 全体回帰** — `tests/run_tests.php` 全 PASS・`tests/smoke_test.sh` 全 PASS・`tests/e2e_ui.mjs` 全 PASS（store/PHP の変更は add_record 未変更・API 追加のみのため回帰確認中心）。

## [S5] 受入基準

- **A1**: 月報タブでグラフ（日別合計の推移）が明細テーブルの上に表示される（T1 PASS）
- **A2**: 年報タブでグラフ（月別合計の推移）が明細テーブルの上に表示される（T2 PASS）
- **A3**: 分析タブの時間帯別グラフが実データの最小時間〜最大時間のみを表示（T3 PASS）
- **A4**: 日別集計の日詳細に「追加」ボタンがあり、枚数 + 時間（分単位）を入力して選択日の記録を追加できる（T4/T5 PASS）
- **A5**: 過去日への追加は管理者権限（要認証）でのみ可能 — 未認証 401（T4 PASS）
- **A6**: 既存機能・全回帰 PASS（T6/T7）— 実行結果を reports/2026-08-09-admin-round-chart-add-check.txt に記録しコミット・push
