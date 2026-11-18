<?php
declare(strict_types=1);

namespace App\Api;

use App\Core\{App, Auth, Db, HttpError, Request, Router};

/** File downloads + share links. */
final class ShareApi
{
    public static function publicLink(array $l): array
    {
        return ['token' => $l['token'], 'label' => $l['label'], 'allow_download' => (bool)$l['allow_download'],
            'allow_comments' => (bool)$l['allow_comments'], 'watermark' => $l['watermark'],
            'view_state' => $l['view_state_json'] ? json_decode($l['view_state_json'], true) : null,
            'expires_at' => $l['expires_at'], 'version_id' => $l['version_id'] ? (int)$l['version_id'] : null];
    }

    public static function adminLink(array $l): array
    {
        return self::publicLink($l) + ['id' => (int)$l['id'], 'model_id' => (int)$l['model_id'],
            'has_password' => (bool)$l['password_hash'], 'views' => (int)$l['views'], 'revoked' => (bool)$l['revoked'],
            'created_at' => $l['created_at'],
            'model_name' => Db::val('SELECT name FROM models WHERE id = ?', [$l['model_id']]),
            'expired' => $l['expires_at'] && $l['expires_at'] < Db::now()];
    }

    private static function linkFields(Request $req): array
    {
        $row = [];
        $j = $req->json();
        if (array_key_exists('label', $j)) $row['label'] = $req->str('label', 190);
        if (array_key_exists('allow_download', $j)) $row['allow_download'] = $req->bool('allow_download') ? 1 : 0;
        if (array_key_exists('allow_comments', $j)) $row['allow_comments'] = $req->bool('allow_comments') ? 1 : 0;
        if (array_key_exists('watermark', $j)) $row['watermark'] = $req->str('watermark', 190);
        if (array_key_exists('view_state', $j)) $row['view_state_json'] = $j['view_state'] ? json_encode($j['view_state']) : null;
        if (array_key_exists('expires_at', $j)) {
            $e = $req->str('expires_at', 40);
            $row['expires_at'] = $e ? gmdate('Y-m-d H:i:s', strtotime($e) ?: throw new HttpError(422, 'Bad expiry date')) : null;
        }
        if (array_key_exists('password', $j)) {
            $p = (string)($j['password'] ?? '');
            $row['password_hash'] = $p === '' ? null : password_hash($p, PASSWORD_DEFAULT);
        }
        if (array_key_exists('version_id', $j)) $row['version_id'] = $req->int('version_id');
        return $row;
    }

    public static function register(Router $r): void
    {
        $r->get('/api/files/{id}', function (Request $req) {
            $f = Db::one('SELECT f.*, v.model_id, v.status vstatus FROM files f JOIN model_versions v ON v.id = f.version_id WHERE f.id = ?',
                [(int)$req->params['id']]) ?? throw new HttpError(404, 'File not found');
            $m = Common::model((int)$f['model_id']);
            $acc = Auth::modelAccess($req, $m);
            if ($acc['share']) {
                $sv = $acc['share']['version_id'] ?: $m['current_version_id'];
                if ((int)$sv !== (int)$f['version_id']) throw new HttpError(403, 'This link does not include that version');
                if (in_array($f['kind'], ['skp', 'attachment'], true) && !$acc['share']['allow_download']) {
                    throw new HttpError(403, 'Downloads are disabled for this link');
                }
            }
            $download = !empty($req->query['download']);
            if ($download && $f['kind'] === 'skp') App::audit($acc['user'], 'skp_downloaded', "model:{$m['id']}", $acc['share'] ? 'share' : null);
            App::sendFile($f, $download);
            return null;
        });

        // ---- public share endpoints
        $r->get('/api/share/{token}', function (Request $req) {
            $req->query['share'] = $req->params['token'];
            try {
                $link = Auth::shareFromRequest($req);
            } catch (HttpError $e) {
                if ($e->status === 401) {
                    $l = Db::one('SELECT label FROM share_links WHERE token = ?', [$req->params['token']]);
                    throw new HttpError(401, 'Password required', ['password_required' => true, 'label' => $l['label'] ?? null]);
                }
                throw $e;
            }
            Db::exec('UPDATE share_links SET views = views + 1 WHERE id = ?', [$link['id']]);
            return ['link' => self::publicLink($link), 'model_id' => (int)$link['model_id']];
        });

        $r->post('/api/share/{token}/unlock', function (Request $req) {
            $req->query['share'] = $req->params['token'];
            $link = Auth::shareFromRequest($req, false);
            $fails = (int)Db::val("SELECT COUNT(*) FROM audit_log WHERE action = 'share_unlock_failed' AND ip = ? AND created_at > ?",
                [$req->ip(), gmdate('Y-m-d H:i:s', time() - 900)]);
            if ($fails >= 20) throw new HttpError(429, 'Too many attempts');
            if ($link['password_hash'] && !password_verify((string)$req->input('password', ''), $link['password_hash'])) {
                App::audit(null, 'share_unlock_failed', 'share:' . $link['id']);
                throw new HttpError(401, 'Wrong password', ['password_required' => true]);
            }
            return ['key' => Auth::shareKey($link)];
        });

        // ---- management
        $r->get('/api/shares', function (Request $req) {
            $u = Auth::require($req);
            $rows = $u['role'] === 'admin'
                ? Db::all('SELECT * FROM share_links ORDER BY id DESC')
                : Db::all('SELECT * FROM share_links WHERE created_by = ? ORDER BY id DESC', [$u['id']]);
            return ['shares' => array_map([self::class, 'adminLink'], $rows)];
        });

        $r->get('/api/models/{id}/shares', function (Request $req) {
            $m = Common::model((int)$req->params['id']);
            Auth::modelAccess($req, $m, 'editor');
            return ['shares' => array_map([self::class, 'adminLink'], Db::all('SELECT * FROM share_links WHERE model_id = ? ORDER BY id DESC', [$m['id']]))];
        });

        $r->post('/api/models/{id}/shares', function (Request $req) {
            $m = Common::model((int)$req->params['id']);
            $acc = Auth::modelAccess($req, $m, 'editor');
            $row = self::linkFields($req) + ['token' => App::randomToken(16), 'model_id' => $m['id'],
                'created_by' => $acc['user']['id'], 'created_at' => Db::now()];
            if (!empty($row['version_id']) && (int)Common::version((int)$row['version_id'])['model_id'] !== (int)$m['id']) {
                throw new HttpError(422, 'Version belongs to another model');
            }
            $id = Db::insert('share_links', $row);
            App::audit($acc['user'], 'share_created', "model:{$m['id']}", ['share' => $id]);
            return ['share' => self::adminLink(Db::one('SELECT * FROM share_links WHERE id = ?', [$id]))];
        });

        $r->patch('/api/shares/{id}', function (Request $req) {
            $l = Db::one('SELECT * FROM share_links WHERE id = ?', [(int)$req->params['id']]) ?? throw new HttpError(404, 'Not found');
            Auth::modelAccess($req, Common::model((int)$l['model_id']), 'editor');
            $row = self::linkFields($req);
            if ($req->input('revoked') !== null) $row['revoked'] = $req->bool('revoked') ? 1 : 0;
            if ($row) Db::update('share_links', $row, 'id = ?', [$l['id']]);
            return ['share' => self::adminLink(Db::one('SELECT * FROM share_links WHERE id = ?', [$l['id']]))];
        });

        $r->delete('/api/shares/{id}', function (Request $req) {
            $l = Db::one('SELECT * FROM share_links WHERE id = ?', [(int)$req->params['id']]) ?? throw new HttpError(404, 'Not found');
            $acc = Auth::modelAccess($req, Common::model((int)$l['model_id']), 'editor');
            Db::exec('DELETE FROM share_links WHERE id = ?', [$l['id']]);
            App::audit($acc['user'], 'share_deleted', "model:{$l['model_id']}");
            return ['ok' => true];
        });
    }
}
