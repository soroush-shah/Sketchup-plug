<?php
declare(strict_types=1);

namespace App\Api;

use App\Core\{App, Auth, Db, HttpError, Request, Router};

final class AdminApi
{
    private const ROLES = ['admin', 'editor', 'viewer'];

    public static function register(Router $r): void
    {
        $r->get('/api/admin/users', function (Request $req) {
            Auth::requireAdmin($req);
            $users = array_map(function ($u) {
                $p = Auth::publicUser($u);
                $p['permissions'] = (int)Db::val('SELECT COUNT(*) FROM permissions WHERE user_id = ?', [$u['id']]);
                return $p;
            }, Db::all('SELECT * FROM users ORDER BY name'));
            return ['users' => $users];
        });

        $r->post('/api/admin/users', function (Request $req) {
            $admin = Auth::requireAdmin($req);
            $email = strtolower((string)$req->str('email', 190, true));
            if (!filter_var($email, FILTER_VALIDATE_EMAIL)) throw new HttpError(422, 'Invalid email');
            if (Db::val('SELECT id FROM users WHERE email = ?', [$email])) throw new HttpError(409, 'Email already exists');
            $role = $req->str('role', 20) ?? 'viewer';
            if (!in_array($role, self::ROLES, true)) throw new HttpError(422, 'Invalid role');
            $password = (string)($req->input('password') ?: App::randomToken(9));
            if (strlen($password) < 8) throw new HttpError(422, 'Password must be at least 8 characters');
            $id = Db::insert('users', ['email' => $email, 'name' => $req->str('name', 190) ?? $email,
                'password_hash' => password_hash($password, PASSWORD_DEFAULT), 'role' => $role, 'active' => 1, 'created_at' => Db::now()]);
            App::audit($admin, 'user_created', "user:$id", ['email' => $email, 'role' => $role]);
            return ['id' => $id, 'password' => $password];
        });

        $r->patch('/api/admin/users/{id}', function (Request $req) {
            $admin = Auth::requireAdmin($req);
            $id = (int)$req->params['id'];
            $u = Db::one('SELECT * FROM users WHERE id = ?', [$id]) ?? throw new HttpError(404, 'User not found');
            $row = [];
            $j = $req->json();
            if (isset($j['name'])) $row['name'] = $req->str('name', 190);
            if (isset($j['email'])) {
                $e = strtolower((string)$req->str('email', 190));
                if (!filter_var($e, FILTER_VALIDATE_EMAIL)) throw new HttpError(422, 'Invalid email');
                if (Db::val('SELECT id FROM users WHERE email = ? AND id <> ?', [$e, $id])) throw new HttpError(409, 'Email already exists');
                $row['email'] = $e;
            }
            if (isset($j['role'])) {
                if (!in_array($j['role'], self::ROLES, true)) throw new HttpError(422, 'Invalid role');
                $row['role'] = $j['role'];
            }
            if (isset($j['active'])) $row['active'] = $req->bool('active') ? 1 : 0;
            if ($id === $admin['id'] && ((isset($row['role']) && $row['role'] !== 'admin') || (isset($row['active']) && !$row['active']))) {
                throw new HttpError(422, 'You cannot demote or deactivate yourself');
            }
            $newPass = null;
            if (!empty($j['reset_password'])) {
                $newPass = !empty($j['password']) ? (string)$j['password'] : App::randomToken(9);
                if (strlen($newPass) < 8) throw new HttpError(422, 'Password must be at least 8 characters');
                $row['password_hash'] = password_hash($newPass, PASSWORD_DEFAULT);
            }
            if ($row) Db::update('users', $row, 'id = ?', [$id]);
            if (isset($row['active']) && !$row['active']) Db::exec('UPDATE api_tokens SET revoked = 1 WHERE user_id = ?', [$id]);
            App::audit($admin, 'user_updated', "user:$id", array_diff_key($row, ['password_hash' => 1]) + ($newPass ? ['password_reset' => true] : []));
            return ['ok' => true, 'password' => $newPass];
        });

        $r->delete('/api/admin/users/{id}', function (Request $req) {
            $admin = Auth::requireAdmin($req);
            $id = (int)$req->params['id'];
            if ($id === $admin['id']) throw new HttpError(422, 'You cannot delete yourself');
            Db::exec('DELETE FROM users WHERE id = ?', [$id]);
            App::audit($admin, 'user_deleted', "user:$id");
            return ['ok' => true];
        });

        // ---- permissions
        $r->get('/api/admin/permissions', function (Request $req) {
            Auth::requireAdmin($req);
            $where = isset($req->query['user_id']) ? 'WHERE p.user_id = ' . (int)$req->query['user_id'] : '';
            return ['permissions' => Db::all("SELECT p.id, p.user_id, p.project_id, p.model_id, p.role, p.created_at,
                u.name user_name, u.email user_email, pr.name project_name, m.name model_name
                FROM permissions p JOIN users u ON u.id = p.user_id
                LEFT JOIN projects pr ON pr.id = p.project_id LEFT JOIN models m ON m.id = p.model_id $where ORDER BY p.id DESC")];
        });

        $r->post('/api/admin/permissions', function (Request $req) {
            $admin = Auth::requireAdmin($req);
            $uid = (int)$req->input('user_id');
            Db::val('SELECT id FROM users WHERE id = ?', [$uid]) ?? throw new HttpError(404, 'User not found');
            $pid = $req->int('project_id');
            $mid = $req->int('model_id');
            if (!$pid === !$mid) throw new HttpError(422, 'Give either project_id or model_id');
            if ($pid) Common::project($pid);
            if ($mid) Common::model($mid);
            $role = $req->str('role', 20) ?? 'viewer';
            if (!isset(Auth::ROLE_RANK[$role])) throw new HttpError(422, 'Invalid role');
            Db::exec('DELETE FROM permissions WHERE user_id = ? AND ' . ($pid ? 'project_id = ?' : 'model_id = ?'), [$uid, $pid ?: $mid]);
            $id = Db::insert('permissions', ['user_id' => $uid, 'project_id' => $pid, 'model_id' => $mid, 'role' => $role, 'created_at' => Db::now()]);
            App::audit($admin, 'permission_granted', "user:$uid", ['project' => $pid, 'model' => $mid, 'role' => $role]);
            return ['id' => $id];
        });

        $r->delete('/api/admin/permissions/{id}', function (Request $req) {
            $admin = Auth::requireAdmin($req);
            Db::exec('DELETE FROM permissions WHERE id = ?', [(int)$req->params['id']]);
            App::audit($admin, 'permission_revoked', 'perm:' . $req->params['id']);
            return ['ok' => true];
        });

        // ---- stats / audit / tokens
        $r->get('/api/admin/stats', function (Request $req) {
            Auth::requireAdmin($req);
            $byKind = Db::all('SELECT kind, COUNT(*) n, COALESCE(SUM(size),0) size, COALESCE(SUM(original_size),0) original_size FROM files GROUP BY kind');
            $total = array_sum(array_map(fn($r) => (int)$r['size'], $byKind));
            $disk = @disk_free_space(App::storagePath());
            $quota = (int)(App::$config['storage_quota'] ?? 0);
            $tmp = 0;
            foreach (glob(App::storagePath('tmp/*.part')) ?: [] as $f) $tmp += filesize($f);
            $biggest = Db::all('SELECT m.id, m.name, COALESCE(SUM(f.size),0) size FROM models m
                JOIN model_versions v ON v.model_id = m.id JOIN files f ON f.version_id = v.id
                GROUP BY m.id, m.name ORDER BY size DESC LIMIT 10');
            return [
                'users' => (int)Db::val('SELECT COUNT(*) FROM users'),
                'projects' => (int)Db::val('SELECT COUNT(*) FROM projects'),
                'models' => (int)Db::val('SELECT COUNT(*) FROM models'),
                'versions' => (int)Db::val('SELECT COUNT(*) FROM model_versions'),
                'shares' => (int)Db::val('SELECT COUNT(*) FROM share_links WHERE revoked = 0'),
                'share_views' => (int)Db::val('SELECT COALESCE(SUM(views),0) FROM share_links'),
                'open_comments' => (int)Db::val("SELECT COUNT(*) FROM annotations WHERE type = 'comment' AND parent_id IS NULL AND status = 'open'"),
                'storage_used' => $total, 'storage_tmp' => $tmp, 'disk_free' => $disk === false ? null : (int)$disk,
                'storage_quota' => $quota ?: null, 'by_kind' => $byKind, 'biggest_models' => $biggest,
            ];
        });

        $r->get('/api/admin/audit', function (Request $req) {
            Auth::requireAdmin($req);
            $limit = min(500, max(1, (int)($req->query['limit'] ?? 200)));
            return ['entries' => Db::all("SELECT a.*, u.name user_name FROM audit_log a LEFT JOIN users u ON u.id = a.user_id
                ORDER BY a.id DESC LIMIT $limit")];
        });

        $r->get('/api/admin/tokens', function (Request $req) {
            Auth::requireAdmin($req);
            return ['tokens' => Db::all('SELECT t.id, t.name, t.prefix, t.revoked, t.last_used_at, t.created_at, u.name user_name
                FROM api_tokens t JOIN users u ON u.id = t.user_id ORDER BY t.id DESC')];
        });

        // Remove stale, never-completed uploads (older than 2 days) to recover disk space.
        $r->post('/api/admin/cleanup', function (Request $req) {
            $admin = Auth::requireAdmin($req);
            $cut = gmdate('Y-m-d H:i:s', time() - 2 * 86400);
            $n = 0;
            foreach (Db::all("SELECT id FROM upload_sessions WHERE status = 'open' AND created_at < ?", [$cut]) as $s) {
                @unlink(App::storagePath("tmp/{$s['id']}.part"));
                Db::exec('DELETE FROM upload_sessions WHERE id = ?', [$s['id']]);
                $n++;
            }
            $stale = Db::all("SELECT id FROM model_versions WHERE status = 'uploading' AND created_at < ?", [$cut]);
            foreach ($stale as $v) {
                Common::deleteVersionFiles((int)$v['id']);
                Db::exec('DELETE FROM model_versions WHERE id = ?', [$v['id']]);
            }
            App::audit($admin, 'cleanup', null, ['uploads' => $n, 'versions' => count($stale)]);
            return ['removed_uploads' => $n, 'removed_versions' => count($stale)];
        });
    }
}
