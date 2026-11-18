<?php
declare(strict_types=1);

namespace App\Api;

use App\Core\{App, Auth, Db, HttpError, Request, Router};

/**
 * Resumable chunked uploads. Works around shared-hosting upload_max_filesize limits:
 *   POST /api/uploads                        -> {id, chunk_size, received:[...]}
 *   PUT  /api/uploads/{id}/chunks/{n}        raw bytes of chunk n (0-based)
 *   GET  /api/uploads/{id}                   -> status (for resume)
 *   POST /api/uploads/{id}/complete          -> verifies size + sha256, registers file
 */
final class UploadApi
{
    public static function register(Router $r): void
    {
        $r->post('/api/uploads', function (Request $req) {
            $u = Auth::require($req);
            $v = Common::version((int)$req->input('version_id'));
            Auth::modelAccess($req, Common::model((int)$v['model_id']), 'editor');
            if ($v['status'] !== 'uploading') throw new HttpError(409, 'Version is already published');
            $kind = (string)$req->str('kind', 20, true);
            if (!isset(Common::FILE_KINDS[$kind])) throw new HttpError(422, 'Unknown file kind');
            $size = (int)$req->input('size');
            if ($size <= 0 || $size > App::maxFileSize()) throw new HttpError(413, 'File size not allowed');
            $sha = $req->str('sha256', 64);
            if ($sha !== null && !preg_match('/^[a-f0-9]{64}$/', $sha)) throw new HttpError(422, 'Invalid sha256');

            // Resume an identical open session if the client restarts.
            $existing = $sha ? Db::one("SELECT * FROM upload_sessions WHERE version_id = ? AND kind = ? AND sha256 = ? AND status = 'open'",
                [$v['id'], $kind, $sha]) : null;
            if ($existing) return self::status($existing);

            $chunk = App::chunkSize();
            $id = bin2hex(random_bytes(16));
            Db::insert('upload_sessions', [
                'id' => $id, 'user_id' => $u['id'], 'version_id' => $v['id'], 'kind' => $kind,
                'filename' => Common::safeName((string)$req->str('filename', 255), $kind . '.' . Common::FILE_KINDS[$kind]['ext']),
                'total_size' => $size, 'original_size' => (int)($req->input('original_size') ?: $size),
                'chunk_size' => $chunk, 'total_chunks' => (int)ceil($size / $chunk), 'received_json' => '[]',
                'sha256' => $sha, 'gzipped' => $req->bool('gzipped') ? 1 : 0, 'created_at' => Db::now(),
            ]);
            $fp = fopen(App::storagePath("tmp/$id.part"), 'wb');
            fclose($fp);
            return self::status(self::session($id));
        });

        $r->get('/api/uploads/{id}', function (Request $req) {
            $u = Auth::require($req);
            return self::status(self::session($req->params['id'], $u));
        });

        $chunkHandler = function (Request $req) {
            $u = Auth::require($req);
            $s = self::session($req->params['id'], $u);
            if ($s['status'] !== 'open') throw new HttpError(409, 'Upload already completed');
            $n = (int)$req->params['n'];
            if ($n < 0 || $n >= $s['total_chunks']) throw new HttpError(422, 'Chunk index out of range');
            $expected = $n === $s['total_chunks'] - 1 ? $s['total_size'] - $n * $s['chunk_size'] : $s['chunk_size'];

            $in = $req->bodyStream();
            $data = stream_get_contents($in, $s['chunk_size'] + 1);
            fclose($in);
            if (strlen($data) !== (int)$expected) throw new HttpError(422, "Chunk $n has wrong size (" . strlen($data) . " != $expected)");
            $sum = $req->header('x-chunk-sha256');
            if ($sum && !hash_equals(strtolower($sum), hash('sha256', $data))) throw new HttpError(422, 'Chunk checksum mismatch');

            $fp = fopen(App::storagePath("tmp/{$s['id']}.part"), 'c+b');
            flock($fp, LOCK_EX);
            fseek($fp, $n * $s['chunk_size']);
            fwrite($fp, $data);
            fflush($fp);
            // Re-read the received list under lock so parallel chunks don't lose updates.
            $fresh = self::session($s['id']);
            $received = json_decode($fresh['received_json'], true);
            if (!in_array($n, $received, true)) $received[] = $n;
            sort($received);
            Db::update('upload_sessions', ['received_json' => json_encode($received)], 'id = ?', [$s['id']]);
            flock($fp, LOCK_UN);
            fclose($fp);
            return ['ok' => true, 'received' => count($received), 'total_chunks' => (int)$s['total_chunks']];
        };
        $r->put('/api/uploads/{id}/chunks/{n}', $chunkHandler);
        $r->post('/api/uploads/{id}/chunks/{n}', $chunkHandler); // for hosts that block PUT

        $r->post('/api/uploads/{id}/complete', function (Request $req) {
            $u = Auth::require($req);
            $s = self::session($req->params['id'], $u);
            if ($s['status'] !== 'open') throw new HttpError(409, 'Upload already completed');
            $received = json_decode($s['received_json'], true);
            $missing = array_values(array_diff(range(0, $s['total_chunks'] - 1), $received));
            if ($missing) throw new HttpError(409, 'Missing chunks', ['missing' => array_slice($missing, 0, 200)]);
            $tmp = App::storagePath("tmp/{$s['id']}.part");
            clearstatcache(true, $tmp);
            if (filesize($tmp) !== (int)$s['total_size']) throw new HttpError(409, 'Assembled size mismatch');
            $sha = hash_file('sha256', $tmp);
            if ($s['sha256'] && $sha !== $s['sha256']) {
                Db::update('upload_sessions', ['received_json' => '[]'], 'id = ?', [$s['id']]);
                throw new HttpError(422, 'Checksum mismatch, please re-upload');
            }
            $kind = $s['kind'];
            $meta = Common::FILE_KINDS[$kind];
            $dir = 'models/v' . $s['version_id'];
            if (!is_dir(App::storagePath($dir))) mkdir(App::storagePath($dir), 0775, true);
            $ext = $kind === 'attachment' ? (pathinfo($s['filename'], PATHINFO_EXTENSION) ?: 'bin') : $meta['ext'];
            $rel = "$dir/$kind-" . substr($sha, 0, 12) . ".$ext" . ($s['gzipped'] ? '.gz' : '');
            rename($tmp, App::storagePath($rel));

            // One file per kind per version (attachments excepted): replace older.
            if ($kind !== 'attachment') {
                foreach (Db::all('SELECT * FROM files WHERE version_id = ? AND kind = ?', [$s['version_id'], $kind]) as $old) {
                    if ($old['path'] !== $rel) @unlink(App::storagePath($old['path']));
                    Db::exec('DELETE FROM files WHERE id = ?', [$old['id']]);
                }
            }
            $mime = $meta['mime'];
            if ($kind === 'thumb' && str_ends_with(strtolower($s['filename']), '.png')) $mime = 'image/png';
            $filename = $s['filename'];
            if ($kind === 'skp' && !str_ends_with(strtolower($filename), '.skp')) $filename = preg_replace('/\.gz$/i', '', $filename);
            $fid = Db::insert('files', ['version_id' => $s['version_id'], 'kind' => $kind, 'filename' => $filename,
                'path' => $rel, 'size' => $s['total_size'], 'original_size' => $s['original_size'], 'sha256' => $sha,
                'mime' => $mime, 'gzipped' => $s['gzipped'], 'created_at' => Db::now()]);
            Db::update('upload_sessions', ['status' => 'done'], 'id = ?', [$s['id']]);
            return ['ok' => true, 'file_id' => $fid, 'sha256' => $sha];
        });
    }

    private static function session(string $id, ?array $u = null): array
    {
        $s = Db::one('SELECT * FROM upload_sessions WHERE id = ?', [$id]) ?? throw new HttpError(404, 'Upload not found');
        if ($u && (int)$s['user_id'] !== $u['id'] && $u['role'] !== 'admin') throw new HttpError(403, 'Not your upload');
        $s['total_chunks'] = (int)$s['total_chunks'];
        $s['chunk_size'] = (int)$s['chunk_size'];
        $s['total_size'] = (int)$s['total_size'];
        return $s;
    }

    private static function status(array $s): array
    {
        return ['id' => $s['id'], 'chunk_size' => (int)$s['chunk_size'], 'total_chunks' => (int)$s['total_chunks'],
            'received' => json_decode($s['received_json'], true), 'status' => $s['status']];
    }
}
