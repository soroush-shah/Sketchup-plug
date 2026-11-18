<?php
declare(strict_types=1);

namespace App\Core;

/**
 * Authentication (session for the web app, Bearer API token for the SketchUp plugin,
 * share-link tokens for guests) and authorization helpers.
 */
final class Auth
{
    public const ROLE_RANK = ['viewer' => 1, 'commenter' => 2, 'editor' => 3];

    private static ?array $user = null;
    private static bool $resolved = false;
    private static bool $viaToken = false;
    /** Test hook: when set, sessions are not used. */
    public static ?array $fakeSession = null;

    public static function reset(): void
    {
        self::$user = null;
        self::$resolved = false;
        self::$viaToken = false;
    }

    public static function startSession(): void
    {
        if (self::$fakeSession !== null || session_status() === PHP_SESSION_ACTIVE) return;
        $secure = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
            || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https');
        session_name('SKPSID');
        session_set_cookie_params(['lifetime' => 60 * 60 * 24 * 30, 'path' => App::basePath() ?: '/',
            'httponly' => true, 'samesite' => 'Lax', 'secure' => $secure]);
        ini_set('session.gc_maxlifetime', (string)(60 * 60 * 24 * 30));
        session_start();
    }

    public static function &session(): array
    {
        if (self::$fakeSession !== null) return self::$fakeSession;
        self::startSession();
        return $_SESSION;
    }

    public static function user(Request $req): ?array
    {
        if (self::$resolved) return self::$user;
        self::$resolved = true;
        $authz = $req->header('authorization') ?? '';
        if (preg_match('/^Bearer\s+(\S+)$/i', $authz, $m)) {
            $tok = Db::one('SELECT t.id tid, u.* FROM api_tokens t JOIN users u ON u.id = t.user_id
                            WHERE t.token_hash = ? AND t.revoked = 0 AND u.active = 1', [hash('sha256', $m[1])]);
            if (!$tok) throw new HttpError(401, 'Invalid API token');
            Db::exec('UPDATE api_tokens SET last_used_at = ? WHERE id = ?', [Db::now(), $tok['tid']]);
            unset($tok['tid']);
            self::$viaToken = true;
            return self::$user = self::publicUser($tok);
        }
        $sess = &self::session();
        if (!empty($sess['uid'])) {
            $u = Db::one('SELECT * FROM users WHERE id = ? AND active = 1', [$sess['uid']]);
            if ($u) return self::$user = self::publicUser($u);
        }
        return null;
    }

    public static function require(Request $req): array
    {
        $u = self::user($req) ?? throw new HttpError(401, 'Login required');
        if (!self::$viaToken && !in_array($req->method, ['GET', 'HEAD', 'OPTIONS'], true)) self::checkCsrf($req);
        return $u;
    }

    public static function requireAdmin(Request $req): array
    {
        $u = self::require($req);
        if ($u['role'] !== 'admin') throw new HttpError(403, 'Admin only');
        return $u;
    }

    public static function csrfToken(): string
    {
        $s = &self::session();
        if (empty($s['csrf'])) $s['csrf'] = bin2hex(random_bytes(16));
        return $s['csrf'];
    }

    public static function checkCsrf(Request $req): void
    {
        $s = &self::session();
        $sent = $req->header('x-csrf-token') ?? '';
        if (empty($s['csrf']) || !hash_equals($s['csrf'], $sent)) throw new HttpError(419, 'CSRF token mismatch');
    }

    public static function login(array $user): void
    {
        if (self::$fakeSession === null) {
            self::startSession();
            session_regenerate_id(true);
        }
        $s = &self::session();
        $s['uid'] = (int)$user['id'];
        self::reset();
    }

    public static function logout(): void
    {
        $s = &self::session();
        $s = [];
        if (self::$fakeSession === null && session_status() === PHP_SESSION_ACTIVE) session_destroy();
        self::reset();
    }

    public static function publicUser(array $u): array
    {
        return ['id' => (int)$u['id'], 'email' => $u['email'], 'name' => $u['name'], 'role' => $u['role'],
            'active' => (int)$u['active'], 'created_at' => $u['created_at'], 'last_login_at' => $u['last_login_at']];
    }

    // ---------------------------------------------------------------- authorization

    public static function isStaff(array $u): bool { return $u['role'] === 'admin'; }

    /** Effective role of a user on a model: null | viewer | commenter | editor. */
    public static function modelRole(array $u, array $model): ?string
    {
        if ($u['role'] === 'admin') return 'editor';
        $best = null;
        $proj = Db::one('SELECT created_by FROM projects WHERE id = ?', [$model['project_id']]);
        if ($u['role'] === 'editor' && $proj && (int)$proj['created_by'] === $u['id']) $best = 'editor';
        $rows = Db::all('SELECT role FROM permissions WHERE user_id = ? AND (project_id = ? OR model_id = ?)',
            [$u['id'], $model['project_id'], $model['id']]);
        foreach ($rows as $r) $best = self::maxRole($best, $r['role']);
        // A global "viewer" account can never write even if granted editor somewhere.
        if ($best === 'editor' && $u['role'] === 'viewer') $best = 'commenter';
        return $best;
    }

    public static function projectRole(array $u, array $project): ?string
    {
        if ($u['role'] === 'admin') return 'editor';
        $best = null;
        if ($u['role'] === 'editor' && (int)$project['created_by'] === $u['id']) $best = 'editor';
        $rows = Db::all('SELECT role FROM permissions WHERE user_id = ? AND project_id = ?', [$u['id'], $project['id']]);
        foreach ($rows as $r) $best = self::maxRole($best, $r['role']);
        if ($best === 'editor' && $u['role'] === 'viewer') $best = 'commenter';
        return $best;
    }

    public static function maxRole(?string $a, ?string $b): ?string
    {
        if ($a === null) return $b;
        if ($b === null) return $a;
        return self::ROLE_RANK[$a] >= self::ROLE_RANK[$b] ? $a : $b;
    }

    public static function atLeast(?string $role, string $needed): bool
    {
        return $role !== null && self::ROLE_RANK[$role] >= self::ROLE_RANK[$needed];
    }

    // ---------------------------------------------------------------- share links

    public static function shareKey(array $link): string
    {
        return hash_hmac('sha256', $link['token'] . '|' . ($link['password_hash'] ?? ''), App::secret());
    }

    /** Resolve an active share link from ?share=&k= (or headers). Throws on invalid / locked. */
    public static function shareFromRequest(Request $req, bool $requireUnlocked = true): ?array
    {
        $token = $req->query['share'] ?? $req->header('x-share-token');
        if (!$token) return null;
        $link = Db::one('SELECT * FROM share_links WHERE token = ?', [$token]);
        if (!$link || $link['revoked']) throw new HttpError(404, 'Share link not found');
        if ($link['expires_at'] && $link['expires_at'] < Db::now()) throw new HttpError(410, 'Share link expired');
        if ($requireUnlocked && $link['password_hash']) {
            $k = $req->query['k'] ?? $req->header('x-share-key') ?? '';
            if (!hash_equals(self::shareKey($link), (string)$k)) {
                throw new HttpError(401, 'Password required', ['password_required' => true]);
            }
        }
        return $link;
    }

    /**
     * Access context for a model: either a logged-in user with a role, or a share link.
     * Returns ['user'=>?, 'role'=>string, 'share'=>?array]
     */
    public static function modelAccess(Request $req, array $model, string $needed = 'viewer'): array
    {
        $share = self::shareFromRequest($req);
        if ($share) {
            if ((int)$share['model_id'] !== (int)$model['id']) throw new HttpError(403, 'Not allowed by this link');
            $role = $share['allow_comments'] ? 'commenter' : 'viewer';
            if (!self::atLeast($role, $needed)) throw new HttpError(403, 'Not allowed by this link');
            return ['user' => self::user($req), 'role' => $role, 'share' => $share];
        }
        $u = $needed === 'viewer' ? (self::user($req) ?? throw new HttpError(401, 'Login required')) : self::require($req);
        $role = self::modelRole($u, $model);
        if (!self::atLeast($role, $needed)) throw new HttpError(403, 'You do not have access to this model');
        return ['user' => $u, 'role' => $role, 'share' => null];
    }
}
