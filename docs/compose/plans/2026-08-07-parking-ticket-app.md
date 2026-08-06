# 駐車券記録アプリ Implementation Plan

> [!NOTE]
> This document may not reflect the current implementation.
> See the final report for up-to-date state:
> [Final Report](../reports/parking-ticket-app.md)

> **For agentic workers:** REQUIRED SUB-SKILL: Use compose:subagent (recommended) or compose:execute to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 無料駐車券を渡した際に枚数と日時（自動・JST）を記録する、PHP + SQLite のモバイルファーストWebアプリを構築し、単体テストとHTTPスモークテストをすべてPASSさせる。

**Architecture:** サーバー側SQLiteに記録を集約保存するPHPアプリ。`lib/store.php` がHTTPに依存しないテスト可能なコアロジックを持ち、`api.php` がJSON API層（セッション・簡易PW検証）、`index.php` がfetchでAPIを叩くモバイルファーストUIを提供する。削除・日別集計はPW(1234)で保護。

**Tech Stack:** PHP 8.3（PDO SQLite）。外部ライブラリ・依存パッケージなし。テストはPHP CLI（`tests/run_tests.php`）+ curlスモークテスト。

## Global Constraints

- ランタイムはPHP（PDO SQLite対応）。特殊な拡張・ビルド手順を要しない（S2）。
- データはサーバー側SQLite `data/parking.db` のみ。クライアント端末には保存しない（S2）。
- タイムゾーンは `Asia/Tokyo` 固定。コード内で `date_default_timezone_set` する（S2）。
- ポート4500で稼働。LAN内・ログインなし共有。簡易PWは初期値 `1234`、設定ファイル固定（S2, S5）。
- 枚数は 1〜999 の整数のみ許可（S3）。
- DBアクセスは全件プリペアドステートメント。画面描画は textContent 使用（XSS対策）（S2）。
- `data/` は `.htaccess` で直接アクセス拒否（S4, S10）。
- テスト合格条件: `tests/run_tests.php` T1〜T12 全PASS、HTTPスモークテスト全ケース期待どおり（S8）。
- このディレクトリは git リポジトリではない。コミット手順は省略し、検証証跡は `reports/` に記録する。

---

### Task 1: プロジェクト基盤（設定・DB接続・データ保護）

**Covers:** S3, S4, S10

**Files:**
- Create: `lib/config.php`
- Create: `lib/db.php`
- Create: `data/.htaccess`
- Create: `.gitignore`

**Interfaces:**
- Consumes: なし（プロジェクト初期化）
- Produces:
  - `config.php`: 定数 `APP_TZ`, `DB_PATH`, `ADMIN_PW`, `MAX_COUNT`（すべて `if (!defined(...))` 形式でテスト時に上書き可能）
  - `db.php`: `db_open(?string $path = null): PDO` — SQLite接続 + スキーマ作成

- [ ] **Step 1: lib/config.php を作成**

```php
<?php
// 駐車券記録アプリ 設定
// 上書き方法（優先順）: 環境変数 PARK_DB_PATH / テストでの DB_PATH define / 本番の既定値

if (!defined('DB_PATH'))   { define('DB_PATH', getenv('PARK_DB_PATH') ?: __DIR__ . '/../data/parking.db'); }
if (!defined('ADMIN_PW'))  { define('ADMIN_PW', '1234'); }
if (!defined('APP_TZ'))    { define('APP_TZ', 'Asia/Tokyo'); }
if (!defined('MAX_COUNT')) { define('MAX_COUNT', 999); }

date_default_timezone_set(APP_TZ);
```

> 注意: `DB_PATH` を最初に定義する（テスト・スモークテストで上書きするため）。`PARK_DB_PATH` 環境変数はHTTPスモークテストが一時DBで実行するために使用する。

- [ ] **Step 2: lib/db.php を作成**

```php
<?php
require_once __DIR__ . '/config.php';

/** SQLite に接続し、スキーマを初期化して PDO を返す。 */
function db_open(?string $path = null): PDO {
    $path = $path ?? DB_PATH;
    $dir = dirname($path);
    if (!is_dir($dir)) { mkdir($dir, 0775, true); }
    $pdo = new PDO('sqlite:' . $path);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->exec('PRAGMA journal_mode = WAL');
    $pdo->exec('CREATE TABLE IF NOT EXISTS records (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        count      INTEGER NOT NULL CHECK (count BETWEEN 1 AND ' . MAX_COUNT . '),
        created_at TEXT    NOT NULL
    )');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_records_created_at ON records (created_at)');
    return $pdo;
}
```

- [ ] **Step 3: data/.htaccess を作成（DBファイルへの直接アクセス拒否）**

```apache
<IfModule mod_authz_core.c>
    Require all denied
</IfModule>
<IfModule !mod_authz_core.c>
    Order allow,deny
    Deny from all
</IfModule>
```

- [ ] **Step 4: .gitignore を作成**

```gitignore
data/*.db
data/*.db-wal
data/*.db-shm
```

- [ ] **Step 5: 構文チェックとスキーマ生成の動作確認**

Run: `php -l lib/config.php && php -l lib/db.php && php -r "require 'lib/db.php'; \$db = db_open(sys_get_temp_dir() . '/park_probe.db'); echo 'schema ok', PHP_EOL;"`
Expected: `No syntax errors detected`（×2）と `schema ok`

---

### Task 2: コアロジック lib/store.php（TDD・T1〜T12）

**Covers:** S3, S5, S7, S8

**Files:**
- Create: `tests/run_tests.php`
- Create: `lib/store.php`

**Interfaces:**
- Consumes: `db_open()`（Task 1）、定数 `APP_TZ` / `MAX_COUNT` / `DB_PATH`
- Produces（後続タスクが使用する正確なシグネチャ）:
  - `now_jst(): DateTimeImmutable`
  - `add_record(PDO $db, mixed $count, ?DateTimeImmutable $now = null): ?array` — 不正値は null。成功時 `['id'=>int, 'count'=>int, 'created_at'=>'Y-m-d H:i:s']`
  - `get_today(PDO $db, ?DateTimeImmutable $now = null): array` — `['date'=>'Y-m-d', 'total'=>int, 'records'=>[['id','count','created_at'],...]]`（created_at 降順・id 降順）
  - `get_monthly_totals(PDO $db, mixed $year, mixed $month): ?array` — パラメータ不正は null。成功時 `['year'=>int, 'month'=>int, 'days'=>[['date'=>'Y-m-d','total'=>int],...]]`（月の全日、昇順）
  - `delete_record(PDO $db, mixed $id): bool` — 削除できたら true

- [ ] **Step 1: 失敗するテスト tests/run_tests.php を作成**

```php
<?php
// 駐車券記録アプリ 単体テスト（PHP CLI）
// 実行: php tests/run_tests.php
// DB_PATH を一時ファイルに差し替えて store.php のロジックを検証する。

$tmpDb = sys_get_temp_dir() . '/park_test_' . getmypid() . '_' . bin2hex(random_bytes(4)) . '.db';
define('DB_PATH', $tmpDb);
require_once __DIR__ . '/../lib/store.php';

$results = [];
function check(string $name, bool $cond, string $detail = ''): void {
    global $results;
    $results[] = ['name' => $name, 'pass' => $cond];
    printf("%s %s%s\n", $cond ? 'PASS' : 'FAIL', $name, $detail !== '' ? " — $detail" : '');
}

$db = db_open();
$tz = new DateTimeZone(APP_TZ);
// T1/T2 は 08-06 の時刻を使い、T3 以降の「今日(08-07)」の合計に混入させない
$base = new DateTimeImmutable('2026-08-06 09:00:00', $tz);

// T11: TZ設定
check('T11 timezone is Asia/Tokyo', date_default_timezone_get() === 'Asia/Tokyo');

// T1: 記録追加（正常）
$rec = add_record($db, 3, $base);
check('T1 add_record(3)', is_array($rec) && $rec['count'] === 3 && isset($rec['id'], $rec['created_at']));

// T12: タイムスタンプ形式
check('T12 created_at format', isset($rec['created_at']) && preg_match('/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/', $rec['created_at']) === 1);

// T2: 記録追加（異常系）
$bad = [0, -1, 1000, 1.5, 'abc', '', null];
$t2ok = true;
foreach ($bad as $v) {
    if (add_record($db, $v, $base) !== null) { $t2ok = false; }
}
check('T2 invalid counts rejected', $t2ok);

// T3: 今日の合計
add_record($db, 3, new DateTimeImmutable('2026-08-07 09:00:00', $tz));
add_record($db, 2, new DateTimeImmutable('2026-08-07 09:01:00', $tz));
add_record($db, 1, new DateTimeImmutable('2026-08-07 09:02:00', $tz));
check('T3 today total', get_today($db, new DateTimeImmutable('2026-08-07 10:00:00', $tz))['total'] === 6);

// T4: 一覧の順序（新しい順・同刻は id 降順）
$r1 = add_record($db, 1, new DateTimeImmutable('2026-08-07 10:00:00', $tz));
$r2 = add_record($db, 2, new DateTimeImmutable('2026-08-07 10:00:00', $tz));
$r3 = add_record($db, 3, new DateTimeImmutable('2026-08-07 11:00:00', $tz));
$ids = array_column(get_today($db, new DateTimeImmutable('2026-08-07 12:00:00', $tz))['records'], 'id');
check('T4 today order desc', $ids === [$r3['id'], $r2['id'], $r1['id']], 'ids=' . json_encode($ids));

// T8: 日付境界（23:59:59 は昨日扱い、00:00:00 は今日扱い）
add_record($db, 5, new DateTimeImmutable('2026-08-07 23:59:59', $tz));
$nextMorning = get_today($db, new DateTimeImmutable('2026-08-08 00:00:00', $tz));
$prevNight = get_today($db, new DateTimeImmutable('2026-08-07 23:59:59', $tz));
check('T8 date boundary', $nextMorning['date'] === '2026-08-08' && $nextMorning['total'] === 0 && $prevNight['total'] > 0);

// T5: 月別集計（指定月の全日 + 記録日の合計 + 記録なしの日は0）
add_record($db, 3, new DateTimeImmutable('2026-08-03 12:00:00', $tz));
add_record($db, 2, new DateTimeImmutable('2026-08-03 13:00:00', $tz));
$aug = get_monthly_totals($db, 2026, 8);
$t5ok = is_array($aug)
    && count($aug['days']) === 31
    && $aug['days'][0]['date'] === '2026-08-01' && $aug['days'][0]['total'] === 0
    && $aug['days'][2]['date'] === '2026-08-03' && $aug['days'][2]['total'] === 5;
check('T5 monthly totals', $t5ok);

// T6: 月別集計（別月は含まれない）
add_record($db, 7, new DateTimeImmutable('2026-07-31 23:00:00', $tz));
add_record($db, 8, new DateTimeImmutable('2026-09-01 00:00:00', $tz));
$jul = get_monthly_totals($db, 2026, 7);
$sep = get_monthly_totals($db, 2026, 9);
check('T6 other months excluded', is_array($aug) && $aug['days'][2]['total'] === 5
    && $jul['days'][30]['total'] === 7 && $sep['days'][0]['total'] === 8);

// T7: 月別集計（パラメータ検証）
$t7ok = get_monthly_totals($db, 1999, 8) === null
    && get_monthly_totals($db, 2101, 1) === null
    && get_monthly_totals($db, 2026, 0) === null
    && get_monthly_totals($db, 2026, 13) === null
    && get_monthly_totals($db, 2026, '8') === null
    && is_array(get_monthly_totals($db, 2026, 8));
check('T7 monthly param validation', $t7ok);

// T9: 削除（正常）
$before = get_today($db, new DateTimeImmutable('2026-08-07 12:00:00', $tz))['total'];
$deleted = delete_record($db, $r1['id']);
$after = get_today($db, new DateTimeImmutable('2026-08-07 12:00:00', $tz))['total'];
check('T9 delete record', $deleted === true && $after === $before - 1);

// T10: 削除（存在しないID）
check('T10 delete nonexistent', delete_record($db, 999999) === false && delete_record($db, 'abc') === false);

$passCount = count(array_filter($results, fn($r) => $r['pass']));
echo "\n$passCount/" . count($results) . " passed\n";
exit($passCount === count($results) ? 0 : 1);
```

- [ ] **Step 2: テストを実行し RED を確認**

Run: `php tests/run_tests.php`
Expected: `PHP Fatal error:  Uncaught Error: Call to undefined function add_record()` — store.php が存在しないため失敗する

- [ ] **Step 3: 最小実装 lib/store.php を作成**

```php
<?php
require_once __DIR__ . '/db.php';

/** JST の現在時刻を返す。 */
function now_jst(): DateTimeImmutable {
    return new DateTimeImmutable('now', new DateTimeZone(APP_TZ));
}

function format_ts(DateTimeImmutable $t): string {
    return $t->format('Y-m-d H:i:s');
}

/** 記録を追加。count が 1〜MAX_COUNT の整数でなければ null。 */
function add_record(PDO $db, $count, ?DateTimeImmutable $now = null): ?array {
    if (!is_int($count) || $count < 1 || $count > MAX_COUNT) { return null; }
    $now = $now ?? now_jst();
    $createdAt = format_ts($now);
    $stmt = $db->prepare('INSERT INTO records (count, created_at) VALUES (?, ?)');
    $stmt->execute([$count, $createdAt]);
    return ['id' => (int)$db->lastInsertId(), 'count' => $count, 'created_at' => $createdAt];
}

/** 指定日（既定: 今日 JST）の記録一覧（新しい順・同刻は id 降順）と合計。 */
function get_today(PDO $db, ?DateTimeImmutable $now = null): array {
    $now = $now ?? now_jst();
    $date = $now->format('Y-m-d');
    $stmt = $db->prepare('SELECT id, count, created_at FROM records WHERE created_at LIKE ? ORDER BY created_at DESC, id DESC');
    $stmt->execute([$date . '%']);
    $records = array_map(
        fn($r) => ['id' => (int)$r['id'], 'count' => (int)$r['count'], 'created_at' => $r['created_at']],
        $stmt->fetchAll(PDO::FETCH_ASSOC)
    );
    return ['date' => $date, 'total' => array_sum(array_column($records, 'count')), 'records' => $records];
}

/** 指定年月の日別合計（全日・昇順）。year 2000-2100 / month 1-12 以外は null。 */
function get_monthly_totals(PDO $db, $year, $month): ?array {
    if (!is_int($year) || !is_int($month) || $year < 2000 || $year > 2100 || $month < 1 || $month > 12) {
        return null;
    }
    $daysInMonth = (int)(new DateTimeImmutable(sprintf('%04d-%02d-01', $year, $month), new DateTimeZone(APP_TZ)))->format('t');
    $stmt = $db->prepare('SELECT substr(created_at, 1, 10) AS d, SUM(count) AS total FROM records WHERE created_at LIKE ? GROUP BY d ORDER BY d');
    $stmt->execute([sprintf('%04d-%02d-', $year, $month) . '%']);
    $byDay = [];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) { $byDay[$row['d']] = (int)$row['total']; }
    $days = [];
    for ($d = 1; $d <= $daysInMonth; $d++) {
        $date = sprintf('%04d-%02d-%02d', $year, $month, $d);
        $days[] = ['date' => $date, 'total' => $byDay[$date] ?? 0];
    }
    return ['year' => $year, 'month' => $month, 'days' => $days];
}

/** 記録を削除。存在すれば true、なければ false。 */
function delete_record(PDO $db, $id): bool {
    if (!is_int($id) || $id < 1) { return false; }
    $stmt = $db->prepare('DELETE FROM records WHERE id = ?');
    $stmt->execute([$id]);
    return $stmt->rowCount() > 0;
}
```

- [ ] **Step 4: テストを実行し GREEN を確認**

Run: `php tests/run_tests.php`
Expected: T1〜T12 すべて PASS、`12/12 passed`、exit code 0

- [ ] **Step 5: 結果を reports/ に記録**

Run: `php tests/run_tests.php | tee reports/2026-08-07-unit-test-results.txt`
Expected: 結果がファイルに保存される

---

### Task 3: HTTP API層 api.php

**Covers:** S5, S7

**Files:**
- Create: `api.php`

**Interfaces:**
- Consumes: `db_open()`（Task 1）、`add_record` / `get_today` / `get_monthly_totals` / `delete_record`（Task 2）、定数 `ADMIN_PW` / `MAX_COUNT`
- Produces: 下記エンドポイント（JSON）。HTTPスモークテスト（Task 5）が検証する

| エンドポイント | 認証 | 成功 | 失敗 |
|---|---|---|---|
| `POST ?action=add` `{"count":N}` | 不要 | 201 `{id,count,created_at}` | 400 |
| `GET ?action=today` | 不要 | 200 `{date,total,records}` | — |
| `GET ?action=monthly&year=&month=` | 要 | 200 `{year,month,days}` | 401 / 400 |
| `DELETE ?action=delete&id=` | 要 | 204 | 401 / 404 |
| `POST ?action=login` `{"pw":N}` | — | 200 `{ok:true}` | 401 |
| `POST ?action=logout` | — | 200 `{ok:true}` | — |

- [ ] **Step 1: api.php を作成**

```php
<?php
require_once __DIR__ . '/lib/store.php';

session_name('park_app');
session_set_cookie_params(['httponly' => true, 'samesite' => 'Lax', 'secure' => false]);
session_start();

header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');

function respond(int $status, $data = null): void {
    http_response_code($status);
    if ($data !== null) { echo json_encode($data, JSON_UNESCAPED_UNICODE); }
    exit;
}

function read_json_body(): array {
    $raw = file_get_contents('php://input');
    $decoded = json_decode($raw === false ? '' : $raw, true);
    return is_array($decoded) ? $decoded : [];
}

function require_auth(): void {
    if (empty($_SESSION['auth'])) { respond(401, ['error' => 'unauthorized']); }
}

$db = db_open();
$action = $_GET['action'] ?? '';

switch ($action) {
    case 'add': {
        $count = read_json_body()['count'] ?? null;
        if (!is_int($count) || $count < 1 || $count > MAX_COUNT) {
            respond(400, ['error' => 'count must be an integer between 1 and ' . MAX_COUNT]);
        }
        $rec = add_record($db, $count);
        if ($rec === null) { respond(400, ['error' => 'count must be an integer between 1 and ' . MAX_COUNT]); }
        respond(201, $rec);
        break;
    }
    case 'today': {
        respond(200, get_today($db));
        break;
    }
    case 'monthly': {
        require_auth();
        $year = $_GET['year'] ?? null;
        $month = $_GET['month'] ?? null;
        $year = is_string($year) && ctype_digit($year) ? (int)$year : null;
        $month = is_string($month) && ctype_digit($month) ? (int)$month : null;
        $result = get_monthly_totals($db, $year, $month);
        if ($result === null) { respond(400, ['error' => 'year (2000-2100) and month (1-12) are required']); }
        respond(200, $result);
        break;
    }
    case 'delete': {
        require_auth();
        $id = $_GET['id'] ?? null;
        $id = is_string($id) && ctype_digit($id) ? (int)$id : null;
        if ($id === null || !delete_record($db, $id)) { respond(404, ['error' => 'not found']); }
        respond(204);
        break;
    }
    case 'login': {
        $pw = read_json_body()['pw'] ?? null;
        if (!is_string($pw) || !hash_equals(ADMIN_PW, $pw)) { respond(401, ['error' => 'unauthorized']); }
        session_regenerate_id(true);
        $_SESSION['auth'] = true;
        respond(200, ['ok' => true]);
        break;
    }
    case 'logout': {
        $_SESSION = [];
        session_destroy();
        respond(200, ['ok' => true]);
        break;
    }
    default:
        respond(404, ['error' => 'unknown action']);
}
```

- [ ] **Step 2: 構文チェック**

Run: `php -l api.php`
Expected: `No syntax errors detected in api.php`

---

### Task 4: UI index.php（モバイルファースト・単一ページ）

> **2026-08-07 更新（要件ロック後）**: ユーザー指示「cssフレームワークはbootstrapを使用して（cdn板）」により、本タスクは **Bootstrap 5.3.3（CDN版・jsDelivr）** を使用したUIに変更された。以下のコードは旧版（標準CSS）。実装済み `index.php` を参照のこと。変更点: CDN の `<link>`/`<script>` 追加、`data-bs-theme="auto"`（ライト/ダーク自動）、PWダイアログを Bootstrap モーダル化（`show` クラス）、コンポーネントは card/form-control/btn/nav-pills/table を使用。要素ID（today-total / count / add-btn / pw-dialog 等）とAPI連携ロジックは不変。ローカル配置案（assets/）は破棄。

**Covers:** S6, S7

**Files:**
- Create: `index.php`

**Interfaces:**
- Consumes: `api.php` の全エンドポイント（Task 3）、定数 `APP_TZ`（ヘッダ出力のため）
- Produces: スマホブラウザ向け単一ページUI（HTML+CSS+JS 内包）

- [ ] **Step 1: index.php を作成（HTML/CSS/JS の完全実装）**

```php
<?php
// 駐車券記録アプリ — 単一ページUI（モバイルファースト）
require_once __DIR__ . '/lib/config.php';
?><!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#2563eb">
<title>駐車券 記録</title>
<style>
:root{
  --bg:#f5f6f8; --card:#ffffff; --text:#1c1f23; --muted:#6b7280;
  --accent:#2563eb; --accent-text:#ffffff; --danger:#dc2626; --border:#e5e7eb;
}
@media (prefers-color-scheme: dark){
  :root{ --bg:#111417; --card:#1b1f24; --text:#e5e7eb; --muted:#9ca3af;
         --accent:#3b82f6; --accent-text:#ffffff; --danger:#ef4444; --border:#2a2f36; }
}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--text);font-family:system-ui,-apple-system,"Hiragino Sans","Noto Sans JP",sans-serif;line-height:1.5;padding:16px;padding-bottom:60px}
h1{font-size:1.15rem;display:flex;justify-content:space-between;align-items:baseline}
#today-date{font-size:.85rem;color:var(--muted);font-weight:400}
.today-total{background:var(--card);border:1px solid var(--border);border-radius:16px;padding:20px;margin-top:14px;text-align:center}
.today-total .label{color:var(--muted);font-size:.9rem}
.today-total .num{font-size:3.2rem;font-weight:700;line-height:1.1}
.today-total .unit{font-size:1rem;color:var(--muted)}
.form{background:var(--card);border:1px solid var(--border);border-radius:16px;padding:16px;margin-top:14px;display:flex;gap:10px;align-items:stretch}
.form input{flex:1;font-size:1.5rem;text-align:center;border:1px solid var(--border);border-radius:12px;padding:10px;background:var(--bg);color:var(--text);min-width:0}
.form button{font-size:1.15rem;font-weight:600;color:var(--accent-text);background:var(--accent);border:none;border-radius:12px;padding:0 22px;touch-action:manipulation}
.card{background:var(--card);border:1px solid var(--border);border-radius:16px;margin-top:14px;padding:16px}
.card h2{font-size:1rem;margin-bottom:10px}
.tabs{display:flex;gap:8px;margin-top:14px}
.tabs button{flex:1;padding:10px;font-size:.95rem;border:1px solid var(--border);border-radius:12px;background:var(--card);color:var(--text);touch-action:manipulation}
.tabs button.active{background:var(--accent);color:var(--accent-text);border-color:var(--accent)}
.record-row{display:flex;justify-content:space-between;align-items:center;padding:10px 0;border-bottom:1px solid var(--border)}
.record-row:last-child{border-bottom:none}
.record-row .time{color:var(--muted);font-size:.85rem}
.record-row .cnt{font-weight:600}
.del{color:var(--danger);border:1px solid var(--danger);background:transparent;border-radius:10px;padding:6px 12px;font-size:.9rem;touch-action:manipulation}
.empty{color:var(--muted);text-align:center;padding:14px 0}
.month-picker{display:flex;gap:8px;align-items:center;margin-bottom:12px}
.month-picker select{flex:1;padding:10px;border:1px solid var(--border);border-radius:12px;background:var(--card);color:var(--text);font-size:1rem}
.month-picker button{padding:10px 16px;border:none;border-radius:12px;background:var(--accent);color:var(--accent-text);font-size:1rem;font-weight:600;touch-action:manipulation}
table{width:100%;border-collapse:collapse}
th,td{padding:8px 6px;text-align:right;border-bottom:1px solid var(--border)}
th:first-child,td:first-child{text-align:left}
th{color:var(--muted);font-weight:400;font-size:.85rem}
.dialog{display:none;position:fixed;inset:0;background:rgba(0,0,0,.5);align-items:center;justify-content:center;padding:24px;z-index:10}
.dialog.open{display:flex}
.dialog-box{background:var(--card);border-radius:16px;padding:20px;width:100%;max-width:320px}
.dialog-box h3{font-size:1rem;margin-bottom:12px}
.dialog-box input{width:100%;font-size:1.4rem;text-align:center;padding:10px;border:1px solid var(--border);border-radius:12px;background:var(--bg);color:var(--text);margin-bottom:12px}
.dialog-actions{display:flex;gap:8px}
.dialog-actions button{flex:1;padding:10px;border-radius:12px;font-size:1rem;border:1px solid var(--border);background:var(--card);color:var(--text);touch-action:manipulation}
.dialog-actions button.primary{background:var(--accent);color:var(--accent-text);border-color:var(--accent)}
.err{color:var(--danger);font-size:.85rem;min-height:1.2em}
#toast{position:fixed;left:50%;bottom:24px;transform:translateX(-50%);background:var(--text);color:var(--bg);padding:10px 18px;border-radius:999px;font-size:.9rem;opacity:0;transition:opacity .25s;pointer-events:none;z-index:20}
#toast.show{opacity:1}
</style>
</head>
<body>
<header>
  <h1>駐車券 記録<span id="today-date"></span></h1>
</header>

<section class="today-total">
  <div class="label">今日の合計</div>
  <div><span class="num" id="today-total">0</span><span class="unit"> 枚</span></div>
</section>

<section class="form">
  <input type="number" id="count" value="1" min="1" max="999" inputmode="numeric" aria-label="枚数">
  <button id="add-btn">記録する</button>
</section>

<div class="tabs">
  <button id="tab-today" class="active">今日の記録</button>
  <button id="tab-month">日別集計</button>
</div>

<section class="card" id="panel-today">
  <h2>今日の記録</h2>
  <div id="today-list"></div>
</section>

<section class="card" id="panel-month" hidden>
  <h2>日別集計</h2>
  <div class="month-picker">
    <select id="year"></select>
    <select id="month"></select>
    <button id="month-btn">表示</button>
  </div>
  <div class="err" id="month-err"></div>
  <table id="month-table" hidden><thead><tr><th>日付</th><th>枚数</th></tr></thead><tbody></tbody></table>
</section>

<div class="dialog" id="pw-dialog">
  <div class="dialog-box">
    <h3>パスワード</h3>
    <input type="password" id="pw" inputmode="numeric" autocomplete="off" placeholder="4桁の数字">
    <div class="err" id="pw-err"></div>
    <div class="dialog-actions">
      <button id="pw-cancel">キャンセル</button>
      <button class="primary" id="pw-ok">確定</button>
    </div>
  </div>
</div>

<div id="toast"></div>

<script>
'use strict';
const $ = id => document.getElementById(id);

function toast(msg) {
  const t = $('toast');
  t.textContent = msg;
  t.classList.add('show');
  setTimeout(() => t.classList.remove('show'), 1800);
}

async function api(method, action, body) {
  const opts = { method, headers: {} };
  if (body !== undefined) {
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(body);
  }
  const res = await fetch('api.php?action=' + action, opts);
  let data = null;
  try { data = await res.json(); } catch (e) { /* 204等 */ }
  return { status: res.status, data };
}

let authed = false;
let pendingAuthAction = null;

function showPwDialog(afterAuth) {
  pendingAuthAction = afterAuth;
  $('pw').value = '';
  $('pw-err').textContent = '';
  $('pw-dialog').classList.add('open');
  $('pw').focus();
}

async function submitPw() {
  const { status } = await api('POST', 'login', { pw: $('pw').value });
  if (status === 200) {
    authed = true;
    $('pw-dialog').classList.remove('open');
    const action = pendingAuthAction;
    pendingAuthAction = null;
    if (action) await action();
  } else {
    $('pw-err').textContent = 'パスワードが違います';
  }
}

$('pw-ok').addEventListener('click', submitPw);
$('pw-cancel').addEventListener('click', () => {
  $('pw-dialog').classList.remove('open');
  pendingAuthAction = null;
});
$('pw').addEventListener('keydown', e => { if (e.key === 'Enter') submitPw(); });

function rowNode(r) {
  const row = document.createElement('div');
  row.className = 'record-row';
  const time = document.createElement('span');
  time.className = 'time';
  time.textContent = r.created_at.slice(11, 16);
  const mid = document.createElement('span');
  mid.className = 'cnt';
  mid.textContent = r.count + ' 枚';
  const del = document.createElement('button');
  del.className = 'del';
  del.textContent = '削除';
  del.addEventListener('click', () => {
    const doDelete = async () => {
      const { status } = await api('DELETE', 'delete&id=' + r.id);
      if (status === 204) { toast('削除しました'); await loadToday(); }
      else if (status === 401) { showPwDialog(doDelete); }
      else if (status === 404) { toast('既に削除済みです'); await loadToday(); }
    };
    doDelete();
  });
  row.append(time, mid, del);
  return row;
}

async function loadToday() {
  const { status, data } = await api('GET', 'today');
  if (status !== 200) { return; }
  $('today-total').textContent = String(data.total);
  const list = $('today-list');
  list.textContent = '';
  if (data.records.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent = 'まだ記録がありません';
    list.append(empty);
    return;
  }
  data.records.forEach(r => list.append(rowNode(r)));
}

$('add-btn').addEventListener('click', async () => {
  const v = parseInt($('count').value, 10);
  if (!Number.isInteger(v) || v < 1 || v > 999) { toast('枚数は1〜999で入力してください'); return; }
  const { status } = await api('POST', 'add', { count: v });
  if (status === 201) { $('count').value = '1'; toast('記録しました'); await loadToday(); }
  else if (status === 400) { toast('枚数は1〜999で入力してください'); }
  else { toast('エラーが発生しました'); }
});

// 日別集計
const now = new Date();
for (let y = now.getFullYear(); y >= now.getFullYear() - 10; y--) {
  const opt = document.createElement('option');
  opt.value = y; opt.textContent = y + '年';
  if (y === now.getFullYear()) opt.selected = true;
  $('year').append(opt);
}
for (let m = 1; m <= 12; m++) {
  const opt = document.createElement('option');
  opt.value = m; opt.textContent = m + '月';
  if (m === now.getMonth() + 1) opt.selected = true;
  $('month').append(opt);
}

async function loadMonthly() {
  const { status, data } = await api('GET', 'monthly&year=' + $('year').value + '&month=' + $('month').value);
  if (status === 401) { showPwDialog(loadMonthly); return; }
  if (status === 400) { $('month-err').textContent = '指定が不正です'; return; }
  $('month-err').textContent = '';
  const tbody = $('month-table').querySelector('tbody');
  tbody.textContent = '';
  let grand = 0;
  for (const d of data.days) {
    grand += d.total;
    const tr = document.createElement('tr');
    const tdDate = document.createElement('td');
    tdDate.textContent = d.date.slice(5);
    const tdTotal = document.createElement('td');
    tdTotal.textContent = d.total;
    tr.append(tdDate, tdTotal);
    tbody.append(tr);
  }
  const tr = document.createElement('tr');
  const tdDate = document.createElement('td');
  tdDate.textContent = '合計';
  const tdTotal = document.createElement('td');
  tdTotal.textContent = grand;
  tdTotal.style.fontWeight = '700';
  tr.append(tdDate, tdTotal);
  tbody.append(tr);
  $('month-table').hidden = false;
}

$('month-btn').addEventListener('click', loadMonthly);
$('tab-today').addEventListener('click', () => {
  $('tab-today').classList.add('active');
  $('tab-month').classList.remove('active');
  $('panel-today').hidden = false;
  $('panel-month').hidden = true;
});
$('tab-month').addEventListener('click', () => {
  $('tab-month').classList.add('active');
  $('tab-today').classList.remove('active');
  $('panel-today').hidden = true;
  $('panel-month').hidden = false;
});

$('today-date').textContent = new Date().toLocaleDateString('ja-JP', { year: 'numeric', month: 'long', day: 'numeric', weekday: 'short' });
loadToday();
</script>
</body>
</html>
```

- [ ] **Step 2: 構文チェック**

Run: `php -l index.php`
Expected: `No syntax errors detected in index.php`

---

### Task 5: HTTPスモークテスト（php -S + curl）とレポート

**Covers:** S8, S11

**Files:**
- Create: `tests/smoke_test.sh`
- Create: `reports/`（結果の記録先。既存）

**Interfaces:**
- Consumes: ポート4500で稼働する `php -S`、`api.php` 全エンドポイント、`index.php`
- Produces: `reports/2026-08-07-smoke-test-results.txt`

- [ ] **Step 1: tests/smoke_test.sh を作成**

```bash
#!/usr/bin/env bash
# 駐車券記録アプリ HTTPスモークテスト（php -S + curl）
# 実データを汚さないよう、一時DB(PARK_DB_PATH)で実行する。
set -u
PORT=4500
BASE="http://127.0.0.1:${PORT}"
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DB=/tmp/park_smoke.db
JAR=/tmp/park_cookies.txt
JAR2=/tmp/park_cookies2.txt
rm -f "$TMP_DB" "$TMP_DB-wal" "$TMP_DB-shm" "$JAR" "$JAR2"

PASS=0; FAIL=0
ok() { echo "PASS $1"; PASS=$((PASS+1)); }
ng() { echo "FAIL $1 — $2"; FAIL=$((FAIL+1)); }

PARK_DB_PATH="$TMP_DB" php -S 127.0.0.1:${PORT} -t "$APP_DIR" >/tmp/park_smoke_server.log 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null' EXIT
sleep 1

YEAR=$(date +%Y)
MONTH=$(date +%-m)

# 1. index.php が 200 で「駐車券」「記録する」を含む
code=$(curl -s -o /tmp/park_idx.html -w '%{http_code}' "$BASE/index.php")
if [ "$code" = "200" ] && grep -q '駐車券' /tmp/park_idx.html && grep -q '記録する' /tmp/park_idx.html; then
  ok "1 index.php 200 + UI要素"
else
  ng "1 index.php" "code=$code"
fi

# 2. add(count=2) → 201（id を取得）
resp=$(curl -s -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"count":2}' "$BASE/api.php?action=add")
code=${resp##*$'\n'}; body=${resp%$'\n'*}
id=$(printf '%s' "$body" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
if [ "$code" = "201" ] && [ -n "$id" ]; then ok "2 add(count=2) 201 id=$id"; else ng "2 add" "code=$code body=$body"; fi

# 3. today の total に反映（一時DBなので2）
today=$(curl -s "$BASE/api.php?action=today")
total=$(printf '%s' "$today" | sed -n 's/.*"total":\([0-9]*\).*/\1/p')
if [ "$total" = "2" ]; then ok "3 today total=2"; else ng "3 today total" "total=$total body=$today"; fi

# 4. add(count=0) → 400
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"count":0}' "$BASE/api.php?action=add")
if [ "$code" = "400" ]; then ok "4 add(count=0) 400"; else ng "4 add invalid" "code=$code"; fi

# 5. monthly 未認証 → 401
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" "$BASE/api.php?action=monthly&year=$YEAR&month=$MONTH")
if [ "$code" = "401" ]; then ok "5 monthly no-auth 401"; else ng "5 monthly no-auth" "code=$code"; fi

# 6. login 誤PW → 401
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"pw":"9999"}' -c "$JAR" "$BASE/api.php?action=login")
if [ "$code" = "401" ]; then ok "6 login wrong pw 401"; else ng "6 login wrong pw" "code=$code"; fi

# 7. login 正PW(1234) → 200
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"pw":"1234"}' -c "$JAR" "$BASE/api.php?action=login")
if [ "$code" = "200" ]; then ok "7 login correct pw 200"; else ng "7 login correct pw" "code=$code"; fi

# 8. monthly 認証済み → 200 + 本日の日付を含む
resp=$(curl -s -b "$JAR" "$BASE/api.php?action=monthly&year=$YEAR&month=$MONTH")
today_ymd=$(date +%F)
if printf '%s' "$resp" | grep -q "$today_ymd"; then ok "8 monthly authed 200 + today included"; else ng "8 monthly authed" "resp=$resp"; fi

# 9. delete 未認証（別クッキー）→ 401
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR2" -X DELETE "$BASE/api.php?action=delete&id=$id")
if [ "$code" = "401" ]; then ok "9 delete no-auth 401"; else ng "9 delete no-auth" "code=$code"; fi

# 10. delete 認証済み → 204
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -X DELETE "$BASE/api.php?action=delete&id=$id")
if [ "$code" = "204" ]; then ok "10 delete authed 204"; else ng "10 delete authed" "code=$code"; fi

# 11. 再削除 → 404
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -X DELETE "$BASE/api.php?action=delete&id=$id")
if [ "$code" = "404" ]; then ok "11 delete again 404"; else ng "11 delete again" "code=$code"; fi

# 12. today 削除後 → total 0
today=$(curl -s "$BASE/api.php?action=today")
total=$(printf '%s' "$today" | sed -n 's/.*"total":\([0-9]*\).*/\1/p')
if [ "$total" = "0" ]; then ok "12 today total=0 after delete"; else ng "12 today after delete" "total=$total"; fi

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
```

- [ ] **Step 2: 実行権限付与と実行**

Run: `chmod +x tests/smoke_test.sh && tests/smoke_test.sh`
Expected: 1〜12 すべて PASS、`RESULT: 12 passed, 0 failed`、exit 0

- [ ] **Step 3: 結果を reports/ に記録**

Run: `tests/smoke_test.sh | tee reports/2026-08-07-smoke-test-results.txt`
Expected: 結果がファイルに保存される

- [ ] **Step 4: ブラウザでのUI実動作確認（可能なら）**

Run: サーバーを起動したまま `php -S 0.0.0.0:4500 -t .` とし、curl で `index.php` の取得と API 連携が上記で確認済みであることをレポートに追記する（ヘッドレス環境のため、ブラウザ実操作はスモークテストで代替し、その旨を記録する）。

**実績（逸脱・追記）:** ヘッドレス環境でもブラウザ実操作が可能だったため、計画外の **`tests/e2e_ui.mjs`（依存ゼロUI E2E: ヘッドレスchrome + 生CDP + Node組み込みWebSocket）** を追加し、E1〜E8（17チェック）を実ブラウザで実行した。結果は `reports/2026-08-07-e2e-ui-results.txt` に **17/17 PASS** で記録済み。実行手順と根因調査の教訓は下記。

**E2E 実行手順（安定パターン、実証済み）:**
1. `pkill -x chrome`（プロセス名完全一致。ラッパーPID kill では実体 chrome が 9222 と認証済みセッションを保持して残り、実行間コンタミの原因になる）
2. `PARK_DB_PATH=/tmp/park_e2e.db php -S 127.0.0.1:4500 -t . &` → `curl` で 200 確認
3. `google-chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --remote-debugging-port=9222 --user-data-dir=/tmp/park_chrome_e2e about:blank &` → sleep 4
4. `node tests/e2e_ui.mjs > reports/2026-08-07-e2e-ui-results.txt 2>&1`（出力は必ずファイルリダイレクト）
5. `pkill -x chrome` + PID指定 kill で php -S を停止

**E2E 開発中の根因（記録）:**
- **E7 削除ボタン:** Bootstrap 書き換え時に rowNode の削除ボタンから `del` クラスが脱落し、E2E セレクタ `#today-list .del` が 0 件になった（DIAG で HTML 実証）。`del.className = 'del btn btn-sm btn-outline-danger'` に修正。
- **実行間コンタミ:** `google-chrome` はラッパーで、`kill $PID` は実体（プロセス名 'chrome'）を殺さない。実体が 9222 と前回の認証済みセッション（cookie）を保持 → 次回実行が古いブラウザを操作し、E4 で monthly が 200 を返して PW ダイアログが開かない。対策: 実行前後に `pkill -x chrome` + E2E 接続後に `Network.enable` + `Network.clearBrowserCookies`。
- **E6 ダイアログ閉鎖:** Bootstrap Modal の `hide()` は show 遷移（約500ms）完了まで guard（`_isTransitioning`）で早期 return する。E2E が 1 秒未満で E5→E6 を実行したため hide() が無視された（実ユーザーは PW 入力に秒単位かかるためアプリ側は正常）。対策: E4 後に 800ms 待機 + E6 は「テーブル描画を先に待つ」順序に変更。

---

### Task 6: 最終確認（compose:verify 相当）

**Covers:** S11

- [ ] **Step 1: 全テスト再実行**

Run: `php tests/run_tests.php`・`tests/smoke_test.sh`・`tests/e2e_ui.mjs`（E2E は上記の安定パターンで実行）
Expected: 単体 12/12・スモーク 12/12・E2E 17/17 すべてPASS

- [ ] **Step 2: デリバラブル一覧を確認**

- `index.php` / `api.php` / `lib/{config,db,store}.php` / `data/.htaccess` / `tests/{run_tests.php,smoke_test.sh,e2e_ui.mjs,docker_check.sh}` / `Dockerfile` / `docker-compose.yml` / `entrypoint.sh` / `docs/compose/specs/*` / `reports/*.txt`
- ポート4500で起動できること（`php -S 0.0.0.0:4500 -t .`）

### Task 7: Dockerデプロイ（要件ロック後の追加タスク・Q13〜Q15 / S12）

**Covers:** S12（このマシンでの運用）

- [ ] **Step 1: デプロイ一式の作成**

- `Dockerfile`: `php:8.3-apache` ベース。pdo_sqlite/sqlite3 はベースイメージに同梱済み（`php -m` で確認済み）— `docker-php-ext-install` は不要（ビルド失敗の実績あり: libsqlite3-dev が無いと configure が落ちる）。
- `docker-compose.yml`: ポート `4500:80`・`./data:/var/www/html/data`・`restart: unless-stopped`。
- `entrypoint.sh`: 起動時に data/ を www-data へ chown + .htaccess を保証して `apache2-foreground`。

- [ ] **Step 2: デプロイ検証（tests/docker_check.sh）**

Expected: 12ケース全PASS — コンテナ running / restart=unless-stopped / index.php 200 + Bootstrap CDN / today 初期0 / add 201 / total=2（DB書込）/ `/data/parking.db`・`.htaccess` 403（php -S の穴の解消）/ restart 後も total=2（永続化）/ login→delete→total=0（復元）
Run: `bash tests/docker_check.sh > reports/2026-08-07-docker-verification.txt`
