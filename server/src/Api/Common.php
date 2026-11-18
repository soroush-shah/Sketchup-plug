<?php
declare(strict_types=1);

namespace App\Api;

use App\Core\{Db, HttpError};

final class Common
{
    public const FILE_KINDS = [
        'skp' => ['ext' => 'skp', 'mime' => 'application/vnd.sketchup.skp'],
        'full' => ['ext' => 'glb', 'mime' => 'model/gltf-binary'],
        'preview' => ['ext' => 'glb', 'mime' => 'model/gltf-binary'],
        'manifest' => ['ext' => 'json', 'mime' => 'application/json'],
        'thumb' => ['ext' => 'jpg', 'mime' => 'image/jpeg'],
        'scenethumbs' => ['ext' => 'zip', 'mime' => 'application/zip'],
        'attachment' => ['ext' => 'bin', 'mime' => 'application/octet-stream'],
    ];

    public static function model(int $id): array
    {
        return Db::one('SELECT * FROM models WHERE id = ?', [$id]) ?? throw new HttpError(404, 'Model not found');
    }

    public static function project(int $id): array
    {
        return Db::one('SELECT * FROM projects WHERE id = ?', [$id]) ?? throw new HttpError(404, 'Project not found');
    }

    public static function version(int $id): array
    {
        return Db::one('SELECT * FROM model_versions WHERE id = ?', [$id]) ?? throw new HttpError(404, 'Version not found');
    }

    public static function files(int $versionId, bool $includeSkp = true): array
    {
        $rows = Db::all('SELECT id, kind, filename, size, original_size, sha256, mime, gzipped, created_at
                         FROM files WHERE version_id = ? ORDER BY id', [$versionId]);
        $out = [];
        foreach ($rows as $r) {
            if (!$includeSkp && in_array($r['kind'], ['skp', 'attachment'], true)) continue;
            $r['id'] = (int)$r['id'];
            $r['size'] = (int)$r['size'];
            $r['original_size'] = (int)$r['original_size'];
            $r['gzipped'] = (bool)$r['gzipped'];
            $out[] = $r;
        }
        return $out;
    }

    public static function versionPayload(array $v, bool $includeSkp = true): array
    {
        return [
            'id' => (int)$v['id'], 'model_id' => (int)$v['model_id'], 'version_no' => (int)$v['version_no'],
            'note' => $v['note'], 'status' => $v['status'], 'has_3d' => (bool)$v['has_3d'], 'source' => $v['source'],
            'approval_status' => $v['approval_status'], 'approval_note' => $v['approval_note'],
            'approved_at' => $v['approved_at'],
            'approved_by_name' => $v['approved_by'] ? Db::val('SELECT name FROM users WHERE id = ?', [$v['approved_by']]) : null,
            'stats' => $v['stats_json'] ? json_decode($v['stats_json'], true) : null,
            'created_at' => $v['created_at'],
            'created_by_name' => $v['created_by'] ? Db::val('SELECT name FROM users WHERE id = ?', [$v['created_by']]) : null,
            'files' => self::files((int)$v['id'], $includeSkp),
        ];
    }

    public static function modelSummary(array $m): array
    {
        $cur = $m['current_version_id'] ? Db::one('SELECT * FROM model_versions WHERE id = ?', [$m['current_version_id']]) : null;
        $thumb = $cur ? Db::val("SELECT id FROM files WHERE version_id = ? AND kind = 'thumb'", [$cur['id']]) : null;
        $size = $cur ? (int)Db::val('SELECT COALESCE(SUM(size),0) FROM files WHERE version_id = ?', [$cur['id']]) : 0;
        $origSize = $cur ? (int)Db::val("SELECT COALESCE(SUM(original_size),0) FROM files WHERE version_id = ? AND kind = 'skp'", [$cur['id']]) : 0;
        $viewSize = $cur ? (int)Db::val("SELECT COALESCE(SUM(size),0) FROM files WHERE version_id = ? AND kind = 'full'", [$cur['id']]) : 0;
        return [
            'id' => (int)$m['id'], 'project_id' => (int)$m['project_id'], 'name' => $m['name'],
            'description' => $m['description'], 'created_at' => $m['created_at'], 'updated_at' => $m['updated_at'],
            'current_version_id' => $m['current_version_id'] ? (int)$m['current_version_id'] : null,
            'version_no' => $cur ? (int)$cur['version_no'] : null,
            'has_3d' => $cur ? (bool)$cur['has_3d'] : false,
            'approval_status' => $cur['approval_status'] ?? null,
            'thumb_file_id' => $thumb ? (int)$thumb : null,
            'stored_size' => $size, 'skp_size' => $origSize, 'view_size' => $viewSize,
            'open_comments' => (int)Db::val("SELECT COUNT(*) FROM annotations WHERE model_id = ? AND type = 'comment' AND parent_id IS NULL AND status = 'open'", [$m['id']]),
        ];
    }

    public static function deleteVersionFiles(int $versionId): void
    {
        foreach (Db::all('SELECT path FROM files WHERE version_id = ?', [$versionId]) as $f) {
            @unlink(\App\Core\App::storagePath($f['path']));
        }
        foreach (Db::all("SELECT id FROM upload_sessions WHERE version_id = ?", [$versionId]) as $s) {
            @unlink(\App\Core\App::storagePath('tmp/' . $s['id'] . '.part'));
        }
        @rmdir(\App\Core\App::storagePath('models/v' . $versionId));
    }

    public static function safeName(string $name, string $fallback = 'file'): string
    {
        $name = preg_replace('/[^\w.\- ()]+/u', '_', basename($name));
        return trim($name) === '' ? $fallback : mb_substr($name, 0, 200);
    }
}
