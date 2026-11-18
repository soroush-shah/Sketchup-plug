<?php
declare(strict_types=1);

namespace App\Core;

use PDO;

/** Thin PDO wrapper. Production uses MySQL; SQLite is supported for tests/dev. */
final class Db
{
    private static ?PDO $pdo = null;
    private static string $driver = 'mysql';

    public static function connect(array $cfg): PDO
    {
        if (self::$pdo) return self::$pdo;
        self::$driver = $cfg['driver'] ?? 'mysql';
        if (self::$driver === 'sqlite') {
            $pdo = new PDO('sqlite:' . $cfg['path']);
            $pdo->exec('PRAGMA foreign_keys = ON');
            $pdo->exec('PRAGMA journal_mode = WAL');
        } else {
            $dsn = sprintf('mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
                $cfg['host'] ?? 'localhost', (int)($cfg['port'] ?? 3306), $cfg['name']);
            $pdo = new PDO($dsn, $cfg['user'], $cfg['pass'], [PDO::MYSQL_ATTR_INIT_COMMAND => "SET time_zone = '+00:00'"]);
        }
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
        $pdo->setAttribute(PDO::ATTR_EMULATE_PREPARES, false);
        return self::$pdo = $pdo;
    }

    public static function reset(): void { self::$pdo = null; }
    public static function pdo(): PDO { return self::$pdo; }
    public static function driver(): string { return self::$driver; }

    public static function all(string $sql, array $p = []): array
    {
        $st = self::$pdo->prepare($sql);
        $st->execute($p);
        return $st->fetchAll();
    }

    public static function one(string $sql, array $p = []): ?array
    {
        $st = self::$pdo->prepare($sql);
        $st->execute($p);
        $r = $st->fetch();
        return $r === false ? null : $r;
    }

    public static function val(string $sql, array $p = []): mixed
    {
        $st = self::$pdo->prepare($sql);
        $st->execute($p);
        $r = $st->fetchColumn();
        return $r === false ? null : $r;
    }

    public static function exec(string $sql, array $p = []): int
    {
        $st = self::$pdo->prepare($sql);
        $st->execute($p);
        return $st->rowCount();
    }

    public static function insert(string $table, array $row): int
    {
        $cols = array_keys($row);
        $sql = sprintf('INSERT INTO %s (%s) VALUES (%s)', $table, implode(',', $cols),
            implode(',', array_fill(0, count($cols), '?')));
        self::exec($sql, array_values($row));
        return (int)self::$pdo->lastInsertId();
    }

    public static function update(string $table, array $row, string $where, array $p = []): int
    {
        $set = implode(',', array_map(fn($c) => "$c = ?", array_keys($row)));
        return self::exec("UPDATE $table SET $set WHERE $where", [...array_values($row), ...$p]);
    }

    /** Run schema.sql, translating the portable placeholders for the active driver. */
    public static function migrate(string $schemaFile): void
    {
        $sql = file_get_contents($schemaFile);
        $map = self::$driver === 'sqlite'
            ? ['{PK}' => 'INTEGER PRIMARY KEY AUTOINCREMENT', '{ENGINE}' => '', '{JSON}' => 'TEXT', '{BIG}' => 'INTEGER']
            : ['{PK}' => 'INT UNSIGNED AUTO_INCREMENT PRIMARY KEY', '{ENGINE}' => 'ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci', '{JSON}' => 'MEDIUMTEXT', '{BIG}' => 'BIGINT'];
        $sql = strtr($sql, $map);
        foreach (array_filter(array_map('trim', explode(';', $sql))) as $stmt) {
            if (str_starts_with($stmt, '--') && !str_contains($stmt, "\n")) continue;
            try {
                self::$pdo->exec($stmt);
            } catch (\PDOException $e) {
                // Re-running the installer: indexes already exist.
                if (!str_starts_with(strtoupper($stmt), 'CREATE INDEX')) throw $e;
            }
        }
    }

    public static function now(): string { return gmdate('Y-m-d H:i:s'); }
}
