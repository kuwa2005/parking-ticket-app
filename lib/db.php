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
