<?php
declare(strict_types=1);

namespace App\Api;

use App\Core\{App, Auth, Db, HttpError, Request, Router};

final class AuthApi
{
    public static function register(Router $r): void
    {
        $r->get('/api/health', fn() => ['ok' => true, 'app' => 'SkpShare', 'version' => '1.0.0',
            'chunk_size' => App::chunkSize(), 'max_file_size' => App::maxFileSize()]);

        $r->post('/api/auth/login', function (Request $req) {
            $email = strtolower((string)$req->str('email', 190, true));
            $fails = (int)Db::val("SELECT COUNT(*) FROM audit_log WHERE action = 'login_failed' AND ip = ? AND created_at > ?",
                [$req->ip(), gmdate('Y-m-d H:i:s', time() - 900)]);
            if ($fails >= 10) throw new HttpError(429, 'Too many failed attempts. Try again in 15 minutes.');
            $u = Db::one('SELECT * FROM users WHERE email = ?', [$email]);
            if (!$u || !$u['active'] || !password_verify((string)$req->input('password', ''), $u['password_hash'])) {
                App::audit(null, 'login_failed', $email);
                throw new HttpError(401, 'Wrong email or password');
            }
            if (password_needs_rehash($u['password_hash'], PASSWORD_DEFAULT)) {
                Db::update('users', ['password_hash' => password_hash((string)$req->input('password'), PASSWORD_DEFAULT)], 'id = ?', [$u['id']]);
            }
            Db::update('users', ['last_login_at' => Db::now()], 'id = ?', [$u['id']]);
            Auth::login($u);
            App::audit($u, 'login');
            return ['user' => Auth::publicUser($u), 'csrf' => Auth::csrfToken()];
        });

        $r->post('/api/auth/logout', function () {
            Auth::logout();
            return ['ok' => true];
        });

        $r->get('/api/me', function (Request $req) {
            $u = Auth::user($req);
            return ['user' => $u, 'csrf' => $u ? Auth::csrfToken() : null];
        });

        $r->post('/api/me/password', function (Request $req) {
            $u = Auth::require($req);
            $row = Db::one('SELECT password_hash FROM users WHERE id = ?', [$u['id']]);
            if (!password_verify((string)$req->input('current', ''), $row['password_hash'])) throw new HttpError(422, 'Current password is wrong');
            $new = (string)$req->input('password', '');
            if (strlen($new) < 8) throw new HttpError(422, 'Password must be at least 8 characters');
            Db::update('users', ['password_hash' => password_hash($new, PASSWORD_DEFAULT)], 'id = ?', [$u['id']]);
            App::audit($u, 'password_changed');
            return ['ok' => true];
        });

        // ---- personal API tokens (used by the SketchUp plugin)
        $r->get('/api/me/tokens', function (Request $req) {
            $u = Auth::require($req);
            return ['tokens' => Db::all('SELECT id, name, prefix, revoked, last_used_at, created_at FROM api_tokens WHERE user_id = ? ORDER BY id DESC', [$u['id']])];
        });

        $r->post('/api/me/tokens', function (Request $req) {
            $u = Auth::require($req);
            if ($u['role'] === 'viewer') throw new HttpError(403, 'Viewers cannot upload, so they do not need plugin tokens');
            $plain = 'skp_' . App::randomToken(24);
            $id = Db::insert('api_tokens', ['user_id' => $u['id'], 'name' => $req->str('name', 190) ?? 'SketchUp plugin',
                'token_hash' => hash('sha256', $plain), 'prefix' => substr($plain, 0, 10), 'created_at' => Db::now()]);
            App::audit($u, 'token_created', "token:$id");
            return ['id' => $id, 'token' => $plain];
        });

        $r->delete('/api/me/tokens/{id}', function (Request $req) {
            $u = Auth::require($req);
            $n = $u['role'] === 'admin'
                ? Db::exec('UPDATE api_tokens SET revoked = 1 WHERE id = ?', [(int)$req->params['id']])
                : Db::exec('UPDATE api_tokens SET revoked = 1 WHERE id = ? AND user_id = ?', [(int)$req->params['id'], $u['id']]);
            if (!$n) throw new HttpError(404, 'Token not found');
            App::audit($u, 'token_revoked', 'token:' . $req->params['id']);
            return ['ok' => true];
        });
    }
}
