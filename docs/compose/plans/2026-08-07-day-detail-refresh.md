# 日付クリック詳細 + 集計連動更新 + 自動更新チェック Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use compose:subagent (recommended) or compose:execute to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 日別集計の日付クリックでその日の詳細をモーダル表示し、記録時の集計連動更新と 60 秒自動更新チェックを実装して本番へ直接デプロイする。

**Architecture:** store.php（HTTP非依存コア）に `get_day()` / `get_db_version()` を追加し、api.php に `action=day`（要認証）と `action=version`（認証不要）を追加。index.php は日付セルをクリック化し日詳細モーダルを新設、add 成功時の連動更新と 60 秒ポーリング（version 比較・表示中パネルのみ更新）を実装。

**Tech Stack:** PHP 8.3+ / PDO SQLite / Bootstrap 5.3.3 CDN / vanilla JS / テストは PHP 単体・bash smoke・CDP E2E

## Global Constraints

- 依存追加なし（標準 PHP + 標準 JS のみ）。認証情報（SFTP PW 等）をドキュメントに記載しない
- 日詳細は**表示のみ**（削除ボタンなし・Q29）。認証セッション中のみ応答（Q28）
- 自動更新間隔は固定 60 秒（Q30）。表示中のパネル（今日/集計/日詳細）のみ更新
- 本番 data/parking.db は**上書きしない**（デモデータ 401 件を保全）
- get_today は昇順（DEMO 化仕様）を維持。既存テストの期待値は変更しない
- 日本語 UI・Bootstrap 5.3.3・既存クラス名（record-row 等）を維持

---

### Task 1: store.php に get_day / get_db_version を追加（TDD）

**Covers:** [S3]

**Files:**
- Modify: `lib/store.php`
- Test: `tests/run_tests.php`

**Interfaces:**
- Produces: `get_day(PDO $db, string $date): array` → `['date','total','records'[{'id','count','created_at'}]]`（昇順）; `get_db_version(PDO $db): array` → `['count'=>int,'maxId'=>int]`

- [ ] **Step 1: 失敗テスト追加（run_tests.php 末尾・check 集計前に T13〜T16）**
- [ ] **Step 2: 実行して FAIL 確認** — `php tests/run_tests.php` → T13 undefined function
- [ ] **Step 3: store.php に実装**（下記コード・get_today は get_day へ委譲）
- [ ] **Step 4: 再実行して 16/16 PASS 確認**

```php
/** 指定日（YYYY-MM-DD）の記録一覧（時間昇順・同刻は id 昇順）と合計。形式不正は空の一覧。 */
function get_day(PDO $db, string $date): array {
    if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
        return ['date' => $date, 'total' => 0, 'records' => []];
    }
    $stmt = $db->prepare('SELECT id, count, created_at FROM records WHERE created_at LIKE ? ORDER BY created_at ASC, id ASC');
    $stmt->execute([$date . '%']);
    $records = array_map(
        fn($r) => ['id' => (int)$r['id'], 'count' => (int)$r['count'], 'created_at' => $r['created_at']],
        $stmt->fetchAll(PDO::FETCH_ASSOC)
    );
    return ['date' => $date, 'total' => array_sum(array_column($records, 'count')), 'records' => $records];
}

/** データ更新検出用: レコード総数と最大 id。 */
function get_db_version(PDO $db): array {
    $stmt = $db->query('SELECT COUNT(*) AS c, COALESCE(MAX(id), 0) AS m FROM records');
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    return ['count' => (int)$row['c'], 'maxId' => (int)$row['m']];
}
```
get_today は `return get_day($db, $now->format('Y-m-d'));` に置換（コメント「時間昇順」は get_day 側に集約）。

- [ ] **Step 5: Commit** — `git add lib/store.php tests/run_tests.php && git commit -m "feat: get_day/get_db_version を追加（日詳細・更新検出 API のコア）"`

### Task 2: api.php に action=day / action=version を追加（TDD）

**Covers:** [S2 R2/R8, S3]

**Files:**
- Modify: `api.php`（switch に 2 ケース追加）
- Test: `tests/smoke_test.sh`（15〜19 追加）

**Interfaces:**
- Consumes: `get_day`, `get_db_version`（Task 1）
- Produces: `GET ?action=day&date=`（401/400/200）; `GET ?action=version`（200）

- [ ] **Step 1: smoke テスト 15〜19 追加**（ログイン cookie は既存 JAR 使用）
- [ ] **Step 2: 実行して FAIL 確認** — 15/16/18 が unknown action
- [ ] **Step 3: api.php にケース追加**（下記コード）
- [ ] **Step 4: 再実行して 19/19 PASS 確認**

```php
    case 'day': {
        require_auth();
        $date = $_GET['date'] ?? null;
        if (!is_string($date) || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
            respond(400, ['error' => 'invalid date']);
        }
        respond(200, get_day($db, $date));
        break;
    }
    case 'version': {
        respond(200, get_db_version($db));
        break;
    }
```
※ `preg_match` は `1` を返すため `!== 1` でなく `!` 判定（match 0 も不正扱い）。

- [ ] **Step 5: Commit** — `git add api.php tests/smoke_test.sh && git commit -m "feat: day/version API を追加（日詳細・更新検出）"`

### Task 3: index.php に日詳細モーダル + 連動更新 + ポーリングを実装（TDD）

**Covers:** [S2 R1/R4/R5/R6/R7, S4, S5]

**Files:**
- Modify: `index.php`
- Test: `tests/e2e_ui.mjs`（E9〜E11 追加）

**Interfaces:**
- Consumes: `api('GET','day&date='+d)` / `api('GET','version')`（Task 2）
- Produces: `openDayDetail(date)`（モジュール関数・再呼び出しで更新）; `window.__refreshNow`（ポーリング連動を即時実行する公開関数）

- [ ] **Step 1: E2E テスト E9〜E11 追加**
- [ ] **Step 2: 実行して FAIL 確認**（E9 day-dialog 未存在）
- [ ] **Step 3: index.php に実装**（下記要点）
  - HTML: `#day-dialog` モーダル（`#day-title`・`#day-list`）を PW モーダルの後に追加
  - `loadMonthly`: 日付セル `td.text-start` に `class="text-start day-link text-primary"` とクリックハンドラ付与（`tdDate.addEventListener('click', () => openDayDetail(d.date))`）。`style` に `cursor:pointer;text-decoration:underline` 相当
  - `openDayDetail(date)`: `api('GET','day&date='+date)` → 401 なら `showPwDialog(() => openDayDetail(date))` → 200 でタイトル「M月D日（N件・T枚）」+ `#day-list` に行ノード（時刻+枚数・削除なし）描画 → `dayModal.show()`
  - `add-btn` 成功時: `loadToday()` に加え、`!$('panel-month').hidden && loadMonthly()` と、`dayModalVisibleDate !== null && openDayDetail(dayModalVisibleDate)` を実行
  - ポーリング: `let lastVersion = null; async function checkVersion(){ const {status,data} = await api('GET','version'); if(status!==200) return; const sig = data.count+':'+data.maxId; if(lastVersion!==null && lastVersion!==sig){ await loadToday(); if(!$('panel-month').hidden) await loadMonthly(); if(dayModalVisibleDate!==null) await openDayDetail(dayModalVisibleDate);} lastVersion = sig; } window.__refreshNow = checkVersion; setInterval(checkVersion, 60000);` 初回起動時に `checkVersion()` を一度実行してベースライン確立
  - `dayModalVisibleDate` はモーダル表示中に現在の日付を保持（`day-dialog` の `hidden.bs.modal` で null に戻す）
- [ ] **Step 4: E2E 再実行して 20/20 PASS 確認**
- [ ] **Step 5: 全回帰**（unit 16/16・smoke 19/19・E2E 20/20）→ reports/ に fresh 記録
- [ ] **Step 6: Commit** — `git add index.php tests/e2e_ui.mjs reports/ && git commit -m "feat: 日付クリック詳細モーダル + 集計連動更新 + 60秒自動更新チェック"`

### Task 4: 本番へ直接デプロイ + 本番受入確認

**Covers:** [S2 R9, S7]

**Files:**
- Deploy: `index.php` `api.php` `lib/` `scripts/seed_demo.php` `data/.htaccess` → `public_html/debugprint.com/parking/`（lftp・data/parking.db は不送）
- Test: `tests/production_check.sh` + 新機能 curl 確認

- [ ] **Step 1: バンドル作成**（/tmp/park_deploy2・data/parking.db 除外）
- [ ] **Step 2: lftp で上書き配置**（chmod 755）
- [ ] **Step 3: 本番で production_check.sh 10/10 + day/version API + 既存ポートフォリオ無傷確認**
- [ ] **Step 4: reports/2026-08-07-production-verify.txt に記録**

### Task 5: docs 更新 + 最終コミット + push

**Covers:** [S6, S9]

- [ ] **Step 1: README**（機能表に日詳細・自動更新追記・テスト表 16/19/20 更新）
- [ ] **Step 2: 最終レポート** docs/compose/reports/parking-ticket-app.md（新機能節 + Journey Log）
- [ ] **Step 3: 全コミット push**・`git log` 確認
