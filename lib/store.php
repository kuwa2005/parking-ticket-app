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

/** 指定日（今日 JST 等）の記録一覧（時間昇順・同刻は id 昇順）と合計。 */
function get_today(PDO $db, ?DateTimeImmutable $now = null): array {
    $now = $now ?? now_jst();
    return get_day($db, $now->format('Y-m-d'));
}

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

/** 指定年月の日別合計（全日・昇順）。year 2000-2100 / month 1-12 以外は null。 */
function get_monthly_totals(PDO $db, $year, $month): ?array {
    if (!is_int($year) || !is_int($month) || $year < 2000 || $year > 2100 || $month < 1 || $month > 12) {
        return null;
    }
    $daysInMonth = (int)(new DateTimeImmutable(sprintf('%04d-%02d-01', $year, $month), new DateTimeZone(APP_TZ)))->format('t');
    $stmt = $db->prepare('SELECT substr(created_at, 1, 10) AS d, SUM(count) AS total, COUNT(*) AS c FROM records WHERE created_at LIKE ? GROUP BY d ORDER BY d');
    $stmt->execute([sprintf('%04d-%02d-', $year, $month) . '%']);
    $byDay = [];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $byDay[$row['d']] = ['total' => (int)$row['total'], 'count' => (int)$row['c']];
    }
    $days = [];
    for ($d = 1; $d <= $daysInMonth; $d++) {
        $date = sprintf('%04d-%02d-%02d', $year, $month, $d);
        $days[] = [
            'date' => $date,
            'total' => $byDay[$date]['total'] ?? 0,
            'count' => $byDay[$date]['count'] ?? 0,
        ];
    }
    return ['year' => $year, 'month' => $month, 'days' => $days];
}

/** 指定年の月別合計（全12ヶ月・昇順）。year 2000-2100 以外は null。 */
function get_yearly_totals(PDO $db, $year): ?array {
    if (!is_int($year) || $year < 2000 || $year > 2100) { return null; }
    $stmt = $db->prepare('SELECT substr(created_at, 1, 7) AS ym, SUM(count) AS total, COUNT(*) AS c FROM records WHERE created_at LIKE ? GROUP BY ym ORDER BY ym');
    $stmt->execute([$year . '%']);
    $byMonth = [];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $byMonth[(int)substr($row['ym'], 5, 2)] = ['total' => (int)$row['total'], 'count' => (int)$row['c']];
    }
    $months = [];
    for ($m = 1; $m <= 12; $m++) {
        $months[] = ['month' => $m, 'total' => $byMonth[$m]['total'] ?? 0, 'count' => $byMonth[$m]['count'] ?? 0];
    }
    return ['year' => $year, 'months' => $months];
}

/** 分析: 指定期間（年 or 年+月）の曜日別・時間帯別・期間サマリ。 */
function get_stats(PDO $db, string $year, ?string $month = null): array {
    $like = $month !== null ? $year . '-' . $month . '%' : $year . '%';
    $stmt = $db->prepare('SELECT count, created_at FROM records WHERE created_at LIKE ?');
    $stmt->execute([$like]);
    $dow = array_fill(0, 7, ['count' => 0, 'sum' => 0]);
    $hour = array_fill(0, 24, ['count' => 0, 'sum' => 0]);
    $perDay = [];
    $records = 0;
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $r) {
        $c = (int)$r['count'];
        $d = (int)date('w', strtotime(substr($r['created_at'], 0, 10)));
        $h = (int)substr($r['created_at'], 11, 2);
        $dow[$d]['count']++;
        $dow[$d]['sum'] += $c;
        $hour[$h]['count']++;
        $hour[$h]['sum'] += $c;
        $day = substr($r['created_at'], 0, 10);
        $perDay[$day] = ($perDay[$day] ?? 0) + $c;
        $records++;
    }
    $days = count($perDay);
    $total = array_sum($perDay);
    $maxDay = null;
    $maxVal = -1;
    foreach ($perDay as $day => $sum) {
        if ($sum > $maxVal) { $maxVal = $sum; $maxDay = $day; }
    }
    $dowOut = [];
    foreach ($dow as $i => $v) { $dowOut[] = ['dow' => $i, 'count' => $v['count'], 'sum' => $v['sum']]; }
    $hourOut = [];
    foreach ($hour as $i => $v) { $hourOut[] = ['hour' => $i, 'count' => $v['count'], 'sum' => $v['sum']]; }
    return [
        'dow' => $dowOut,
        'hour' => $hourOut,
        'summary' => [
            'days' => $days,
            'total' => $total,
            'records' => $records,
            'max_day' => $maxDay !== null ? ['date' => $maxDay, 'total' => $maxVal] : null,
            'avg_per_day' => $days > 0 ? round($total / $days, 1) : 0.0,
        ],
    ];
}

/** レコードを訂正（枚数・日時）。戻り値: ['ok'=>true,'record'=>...] または ['ok'=>false,'error'=>'not_found'|'invalid_count'|'invalid_datetime']。 */
function update_record(PDO $db, $id, $count, $createdAt): array {
    if (!is_int($id) || $id < 1) { return ['ok' => false, 'error' => 'not_found']; }
    $stmt = $db->prepare('SELECT count, created_at FROM records WHERE id = ?');
    $stmt->execute([$id]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($row === false) { return ['ok' => false, 'error' => 'not_found']; }
    if ($count !== null && (!is_int($count) || $count < 1 || $count > MAX_COUNT)) {
        return ['ok' => false, 'error' => 'invalid_count'];
    }
    if ($createdAt !== null && (!is_string($createdAt) || !preg_match('/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/', $createdAt))) {
        return ['ok' => false, 'error' => 'invalid_datetime'];
    }
    $newCount = $count ?? (int)$row['count'];
    $newCreated = $createdAt ?? $row['created_at'];
    $stmt = $db->prepare('UPDATE records SET count = ?, created_at = ? WHERE id = ?');
    $stmt->execute([$newCount, $newCreated, $id]);
    return ['ok' => true, 'record' => ['id' => (int)$id, 'count' => $newCount, 'created_at' => $newCreated]];
}

/** 記録を削除。存在すれば true、なければ false。 */
function delete_record(PDO $db, $id): bool {
    if (!is_int($id) || $id < 1) { return false; }
    $stmt = $db->prepare('DELETE FROM records WHERE id = ?');
    $stmt->execute([$id]);
    return $stmt->rowCount() > 0;
}
