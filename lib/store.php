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

/** 指定日（既定: 今日 JST）の記録一覧（時間昇順・同刻は id 昇順）と合計。 */
function get_today(PDO $db, ?DateTimeImmutable $now = null): array {
    $now = $now ?? now_jst();
    $date = $now->format('Y-m-d');
    $stmt = $db->prepare('SELECT id, count, created_at FROM records WHERE created_at LIKE ? ORDER BY created_at ASC, id ASC');
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
