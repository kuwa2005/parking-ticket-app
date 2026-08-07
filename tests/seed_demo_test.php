<?php
// デモデータ投入の検証テスト（DEMO 化仕様 §3 B1〜B8）
// 実行: php tests/seed_demo_test.php
// 一時 DB に seed_demo.php を実行し、統計（401件/68日/count=1/日5〜10件・中央値5/
// 時刻09:00〜17:05・分重複なし/範囲内差し替え/冪等/範囲外温存）を検証する。

$tmpDb = sys_get_temp_dir() . '/park_seed_' . getmypid() . '_' . bin2hex(random_bytes(4)) . '.db';
putenv('PARK_DB_PATH=' . $tmpDb);
$seedScript = __DIR__ . '/../scripts/seed_demo.php';

$results = [];
function check(string $name, bool $cond, string $detail = ''): void {
    global $results;
    $results[] = ['name' => $name, 'pass' => $cond];
    printf("%s %s%s\n", $cond ? 'PASS' : 'FAIL', $name, $detail !== '' ? " — $detail" : '');
}

function run_seed(string $script): void {
    $out = shell_exec('php ' . escapeshellarg($script) . ' 2>&1');
    if ($out === null || strpos($out, '投入完了') === false) {
        fwrite(STDERR, "seed 実行失敗: $out\n");
        exit(2);
    }
}

function db(): PDO {
    return new PDO('sqlite:' . getenv('PARK_DB_PATH'));
}

// B6: 範囲内の既存データ（今日 2026-08-07 のレコード）を事前投入 → 差し替え検証用
$pdo = db();
$pdo->exec('CREATE TABLE records (id INTEGER PRIMARY KEY AUTOINCREMENT, count INTEGER NOT NULL, created_at TEXT NOT NULL)');
$pdo->exec("INSERT INTO records (count, created_at) VALUES (5, '2026-08-07 08:00:00')");
// B8: 範囲外（2026-09-01）のレコードも事前投入 → 温存検証用
$pdo->exec("INSERT INTO records (count, created_at) VALUES (9, '2026-09-01 10:00:00')");

// シード実行（1回目）
run_seed($seedScript);
$pdo = db();

// B1: 合計 401 件（+ 範囲外の温存レコード 1 件 = 402）
$total = (int)$pdo->query('SELECT COUNT(*) FROM records')->fetchColumn();
check('B1 total 401', $total === 402, "total=$total (401 demo + 1 kept out-of-range)");

// B2: 期間 2026-06-01〜2026-08-07（68日）のみ（範囲外レコードを除く）
$r = $pdo->query("SELECT MIN(substr(created_at,1,10)) mn, MAX(substr(created_at,1,10)) mx, COUNT(DISTINCT substr(created_at,1,10)) d FROM records WHERE substr(created_at,1,10) BETWEEN '2026-06-01' AND '2026-08-07'")->fetch(PDO::FETCH_ASSOC);
check('B2 range 06-01..08-07 68days', $r['mn'] === '2026-06-01' && $r['mx'] === '2026-08-07' && (int)$r['d'] === 68, json_encode($r));

// B3: 全レコード count=1（範囲内）
$c = $pdo->query("SELECT MIN(count) mn, MAX(count) mx FROM records WHERE substr(created_at,1,10) BETWEEN '2026-06-01' AND '2026-08-07'")->fetch(PDO::FETCH_ASSOC);
check('B3 all count=1', (int)$c['mn'] === 1 && (int)$c['mx'] === 1);

// B4: 日ごと 5〜10件・中央値 5（範囲内）
$per = array_map('intval', array_column($pdo->query("SELECT COUNT(*) c FROM records WHERE substr(created_at,1,10) BETWEEN '2026-06-01' AND '2026-08-07' GROUP BY substr(created_at,1,10)")->fetchAll(PDO::FETCH_ASSOC), 'c'));
sort($per);
$median = $per[intdiv(count($per), 2)];
check('B4 per-day 5..10 median5', count($per) === 68 && min($per) >= 5 && max($per) <= 10 && $median === 5, 'min=' . min($per) . ' max=' . max($per) . " median=$median");

// B5: 時刻 09:00:00〜17:05:59・同一日・同一分の重複なし（範囲内）
$t = $pdo->query("SELECT MIN(substr(created_at,12)) mn, MAX(substr(created_at,12)) mx FROM records WHERE substr(created_at,1,10) BETWEEN '2026-06-01' AND '2026-08-07'")->fetch(PDO::FETCH_ASSOC);
$dup = (int)$pdo->query("SELECT COUNT(*) FROM (SELECT substr(created_at,1,16) k FROM records WHERE substr(created_at,1,10) BETWEEN '2026-06-01' AND '2026-08-07' GROUP BY k HAVING COUNT(*) > 1)")->fetchColumn();
check('B5 time range + unique minutes', $t['mn'] >= '09:00:00' && $t['mx'] <= '17:05:59' && $dup === 0, json_encode($t) . " dup=$dup");

// B6: 範囲内の既存データは差し替え（事前投入の 2026-08-07 08:00 レコードは消え、今日はデモデータ 5〜10件のみ）
$old = (int)$pdo->query("SELECT COUNT(*) FROM records WHERE created_at = '2026-08-07 08:00:00'")->fetchColumn();
$today = (int)$pdo->query("SELECT COUNT(*) FROM records WHERE created_at LIKE '2026-08-07%'")->fetchColumn();
check('B6 same-range replaced', $old === 0 && $today >= 5 && $today <= 10, "old_record=$old today_count=$today");

// B8: 範囲外（2026-09-01）は温存
$keep = (int)$pdo->query("SELECT COUNT(*) FROM records WHERE created_at LIKE '2026-09-01%'")->fetchColumn();
check('B8 out-of-range kept', $keep === 1, "kept=$keep");

// B7: 冪等（2回目実行でも 401+1 件のまま・重複なし）
run_seed($seedScript);
$pdo = db();
$total2 = (int)$pdo->query('SELECT COUNT(*) FROM records')->fetchColumn();
$keep2 = (int)$pdo->query("SELECT COUNT(*) FROM records WHERE created_at LIKE '2026-09-01%'")->fetchColumn();
check('B7 idempotent', $total2 === 402 && $keep2 === 1, "total2=$total2 kept2=$keep2");

unlink($tmpDb);
@unlink($tmpDb . '-wal');
@unlink($tmpDb . '-shm');

$passCount = count(array_filter($results, fn($r) => $r['pass']));
echo "\n$passCount/" . count($results) . " passed\n";
exit($passCount === count($results) ? 0 : 1);
