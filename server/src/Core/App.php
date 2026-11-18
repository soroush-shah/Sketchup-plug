<?php
declare(strict_types=1);

namespace App\Core;

final class App
{
    public static array $config = [];

    public static function boot(array $config): void
    {
        self::$config = $config;
        Db::connect($config['db']);
        foreach (['models', 'tmp'] as $d) {
            $p = self::storagePath($d);
            if (!is_dir($p)) @mkdir($p, 0775, true);
        }
    }

    public static function basePath(): string { return rtrim(self::$config['base_path'] ?? '', '/'); }
    public static function secret(): string { return self::$config['secret']; }

    public static function storagePath(string $rel = ''): string
    {
        return rtrim(self::$config['storage_path'], '/') . ($rel !== '' ? '/' . ltrim($rel, '/') : '');
    }

    public static function chunkSize(): int { return (int)(self::$config['chunk_size'] ?? 4 * 1024 * 1024); }
    public static function maxFileSize(): int { return (int)(self::$config['max_file_size'] ?? 3 * 1024 ** 3); }

    public static function audit(?array $user, string $action, ?string $target = null, mixed $details = null): void
    {
        Db::insert('audit_log', [
            'user_id' => $user['id'] ?? null, 'action' => $action, 'target' => $target,
            'details' => $details === null ? null : (is_string($details) ? $details : json_encode($details)),
            'ip' => $_SERVER['REMOTE_ADDR'] ?? null, 'created_at' => Db::now(),
        ]);
    }

    public static function randomToken(int $bytes = 18): string
    {
        return rtrim(strtr(base64_encode(random_bytes($bytes)), '+/', '-_'), '=');
    }

    /**
     * Stream a stored file with HTTP Range / ETag support.
     * Gzipped originals (.skp) are inflated on the fly so the user receives a plain .skp.
     */
    public static function sendFile(array $file, bool $download): void
    {
        $path = self::storagePath($file['path']);
        if (!is_file($path)) throw new HttpError(404, 'File missing on disk');
        $name = $file['filename'];
        $etag = '"' . ($file['sha256'] ? substr($file['sha256'], 0, 32) : md5($path . filemtime($path))) . '"';
        if (Response::$capture) {
            Response::$captured = ['status' => 200, 'file' => $path, 'gzipped' => (bool)$file['gzipped']];
            return;
        }
        while (ob_get_level()) ob_end_clean();
        @set_time_limit(0);
        header('ETag: ' . $etag);
        header('Cache-Control: private, max-age=31536000, immutable');
        header('X-Content-Type-Options: nosniff');
        $disp = $download ? 'attachment' : 'inline';
        header("Content-Disposition: $disp; filename=\"" . addcslashes($name, '"\\') . "\"; filename*=UTF-8''" . rawurlencode($name));
        if (($_SERVER['HTTP_IF_NONE_MATCH'] ?? '') === $etag) {
            http_response_code(304);
            return;
        }
        header('Content-Type: ' . $file['mime']);

        if ($file['gzipped']) {
            // Inflate on the fly. Original size is known, so the browser shows real progress.
            header('Content-Length: ' . $file['original_size']);
            $gz = gzopen($path, 'rb');
            while (!gzeof($gz)) {
                echo gzread($gz, 1 << 20);
                flush();
                if (connection_aborted()) break;
            }
            gzclose($gz);
            return;
        }

        $size = filesize($path);
        $start = 0;
        $end = $size - 1;
        header('Accept-Ranges: bytes');
        if (isset($_SERVER['HTTP_RANGE']) && preg_match('/bytes=(\d*)-(\d*)/', $_SERVER['HTTP_RANGE'], $m)) {
            if ($m[1] === '' && $m[2] !== '') {
                $start = max(0, $size - (int)$m[2]);
            } else {
                $start = (int)$m[1];
                if ($m[2] !== '') $end = min($end, (int)$m[2]);
            }
            if ($start > $end || $start >= $size) {
                http_response_code(416);
                header("Content-Range: bytes */$size");
                return;
            }
            http_response_code(206);
            header("Content-Range: bytes $start-$end/$size");
        }
        header('Content-Length: ' . ($end - $start + 1));
        if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'HEAD') return;
        $fp = fopen($path, 'rb');
        fseek($fp, $start);
        $left = $end - $start + 1;
        while ($left > 0 && !feof($fp)) {
            $buf = fread($fp, (int)min(1 << 20, $left));
            $left -= strlen($buf);
            echo $buf;
            flush();
            if (connection_aborted()) break;
        }
        fclose($fp);
    }
}
