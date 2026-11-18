<?php
declare(strict_types=1);
/**
 * Dependency-free API test suite (SQLite).  Run:  php server/tests/run.php
 */
require __DIR__ . '/../src/bootstrap.php';

use App\Core\{App, Auth, Db, Request, Response};

$tmp = sys_get_temp_dir() . '/skpshare-test-' . bin2hex(random_bytes(4));
mkdir($tmp . '/storage', 0777, true);
App::boot(['db' => ['driver' => 'sqlite', 'path' => "$tmp/db.sqlite"], 'secret' => 'test-secret',
    'storage_path' => "$tmp/storage", 'chunk_size' => 1024, 'max_file_size' => 10 << 20, 'debug' => true]);
Db::migrate(__DIR__ . '/../migrations/schema.sql');
Response::$capture = true;
$router = skpshare_router();

$sessions = [];
$fails = 0;
$passes = 0;

/** Perform a request as a named client (each with its own cookie session). */
function call(string $who, string $method, string $path, mixed $body = null, array $headers = [], array $query = []): array
{
    global $router, $sessions;
    $sessions[$who] ??= [];
    Auth::$fakeSession = $sessions[$who];
    Auth::reset();
    if (isset($sessions[$who]['csrf'])) $headers['x-csrf-token'] ??= $sessions[$who]['csrf'];
    $raw = is_string($body) ? $body : ($body === null ? '' : json_encode($body));
    $req = new Request($method, $path, $query, array_change_key_case($headers), $raw);
    Response::$captured = [];
    skpshare_handle($router, $req);
    $c = Response::$captured;
    $c['json'] = isset($c['body']) ? json_decode($c['body'], true) : null;
    $sessions[$who] = Auth::$fakeSession;
    Auth::$fakeSession = null;
    return $c;
}

function check(string $name, bool $ok, mixed $info = null): void
{
    global $fails, $passes;
    if ($ok) { $passes++; echo "  ✔ $name\n"; }
    else { $fails++; echo "  ✘ $name\n"; if ($info !== null) echo '      ' . json_encode($info) . "\n"; }
}

// ---------------------------------------------------------------- setup
Db::insert('users', ['email' => 'admin@test.io', 'name' => 'Admin', 'password_hash' => password_hash('adminpass', PASSWORD_DEFAULT),
    'role' => 'admin', 'active' => 1, 'created_at' => Db::now()]);

echo "Auth\n";
$r = call('admin', 'POST', '/api/auth/login', ['email' => 'admin@test.io', 'password' => 'wrong']);
check('wrong password rejected', $r['status'] === 401);
$r = call('admin', 'POST', '/api/auth/login', ['email' => 'ADMIN@test.io', 'password' => 'adminpass']);
check('login ok', $r['status'] === 200 && $r['json']['user']['role'] === 'admin', $r);
$r = call('admin', 'GET', '/api/me');
check('me returns user', $r['json']['user']['email'] === 'admin@test.io');
$r = call('admin', 'POST', '/api/projects', ['name' => 'X'], ['x-csrf-token' => 'bad']);
check('csrf enforced', $r['status'] === 419);
$r = call('anon', 'GET', '/api/projects');
check('anonymous blocked', $r['status'] === 401);

echo "Admin & permissions\n";
$r = call('admin', 'POST', '/api/admin/users', ['email' => 'ed@test.io', 'name' => 'Editor', 'role' => 'editor', 'password' => 'editorpass']);
$editorId = $r['json']['id'];
check('create editor', $r['status'] === 200);
$r = call('admin', 'POST', '/api/admin/users', ['email' => 'cl@test.io', 'name' => 'Client', 'role' => 'viewer']);
$clientId = $r['json']['id'];
$clientPass = $r['json']['password'];
check('create viewer with generated password', strlen($clientPass) >= 8);
$r = call('admin', 'POST', '/api/admin/users', ['email' => 'cl@test.io', 'name' => 'Dup']);
check('duplicate email rejected', $r['status'] === 409);
call('editor', 'POST', '/api/auth/login', ['email' => 'ed@test.io', 'password' => 'editorpass']);
call('client', 'POST', '/api/auth/login', ['email' => 'cl@test.io', 'password' => $clientPass]);
$r = call('editor', 'GET', '/api/admin/users');
check('non-admin blocked from admin api', $r['status'] === 403);

echo "Projects / models\n";
$r = call('editor', 'POST', '/api/projects', ['name' => 'Villa']);
$projectId = $r['json']['id'];
check('editor creates project', $r['status'] === 200);
$r = call('client', 'POST', '/api/projects', ['name' => 'Nope']);
check('viewer cannot create project', $r['status'] === 403);
$r = call('editor', 'POST', '/api/models', ['project_id' => $projectId, 'name' => 'Ground floor']);
$modelId = $r['json']['id'];
check('editor creates model', $r['status'] === 200);
$r = call('client', 'GET', "/api/models/$modelId");
check('client has no access yet', $r['status'] === 403);
$r = call('admin', 'POST', '/api/admin/permissions', ['user_id' => $clientId, 'project_id' => $projectId, 'role' => 'commenter']);
check('grant commenter on project', $r['status'] === 200);
$r = call('client', 'GET', '/api/projects');
check('client sees project', count($r['json']['projects']) === 1 && count($r['json']['projects'][0]['models']) === 1, $r['json']);

echo "Plugin token + chunked upload\n";
$r = call('editor', 'POST', '/api/me/tokens', ['name' => 'Laptop']);
$token = $r['json']['token'];
check('token created', str_starts_with($token, 'skp_'));
$bearer = ['authorization' => "Bearer $token"];
$r = call('plugin', 'GET', '/api/projects', null, $bearer);
check("bearer auth works", $r["status"] === 200 && count($r["json"]["projects"]) === 1, $r);
$r = call('plugin', 'GET', '/api/projects', null, ['authorization' => 'Bearer skp_nope']);
check('bad bearer rejected', $r['status'] === 401);

$r = call('plugin', 'POST', "/api/models/$modelId/versions", ['note' => 'first', 'stats' => ['faces' => 10]], $bearer);
$versionId = $r['json']['id'];
check('version created', $r['json']['version_no'] === 1);

$upload = function (string $kind, string $data, bool $gz = false, ?int $orig = null) use ($bearer, $versionId) {
    $r = call('plugin', 'POST', '/api/uploads', ['version_id' => $versionId, 'kind' => $kind, 'filename' => "f.$kind",
        'size' => strlen($data), 'sha256' => hash('sha256', $data), 'gzipped' => $gz, 'original_size' => $orig], $bearer);
    $id = $r['json']['id'];
    $chunks = str_split($data, $r['json']['chunk_size']);
    foreach (array_reverse(array_keys($chunks)) as $i) { // out of order on purpose
        $c = call('plugin', 'PUT', "/api/uploads/$id/chunks/$i", $chunks[$i], $bearer + ['x-chunk-sha256' => hash('sha256', $chunks[$i])]);
        if ($c['status'] !== 200) return $c;
    }
    return call('plugin', 'POST', "/api/uploads/$id/complete", null, $bearer);
};

$glb = random_bytes(5000);
$r = call('plugin', 'POST', '/api/uploads', ['version_id' => $versionId, 'kind' => 'full', 'size' => strlen($glb), 'sha256' => hash('sha256', $glb)], $bearer);
$upId = $r['json']['id'];
call('plugin', 'PUT', "/api/uploads/$upId/chunks/0", substr($glb, 0, 1024), $bearer);
$r = call('plugin', 'POST', "/api/uploads/$upId/complete", null, $bearer);
check('incomplete upload refused with missing list', $r['status'] === 409 && $r['json']['missing'][0] === 1, $r['json']);
$r = call('plugin', 'POST', '/api/uploads', ['version_id' => $versionId, 'kind' => 'full', 'size' => strlen($glb), 'sha256' => hash('sha256', $glb)], $bearer);
check('resume returns same session with received chunks', $r['json']['id'] === $upId && $r['json']['received'] === [0], $r['json']);
$r = call('plugin', 'PUT', "/api/uploads/$upId/chunks/1", 'short', $bearer);
check('wrong chunk size rejected', $r['status'] === 422);
$r = call('plugin', 'PUT', "/api/uploads/$upId/chunks/1", substr($glb, 1024, 1024), $bearer + ['x-chunk-sha256' => str_repeat('0', 64)]);
check('chunk checksum enforced', $r['status'] === 422);
foreach (str_split($glb, 1024) as $i => $c) call('plugin', 'PUT', "/api/uploads/$upId/chunks/$i", $c, $bearer);
$r = call('plugin', 'POST', "/api/uploads/$upId/complete", null, $bearer);
check('resumed upload completes', $r['status'] === 200, $r['json']);

$r = $upload('manifest', json_encode(['scenes' => [['name' => 'Front']]]));
check('manifest uploaded', $r['status'] === 200);
$skp = str_repeat('SketchUp model data ', 2000);
$gz = gzencode($skp, 9);
$r = $upload('skp', $gz, true, strlen($skp));
check('gzipped skp uploaded', $r['status'] === 200, $r['json'] ?? $r);
$r = call('client', 'POST', "/api/models/$modelId/versions", []);
check('commenter cannot create versions', $r['status'] === 403);
$r = call('plugin', 'POST', "/api/versions/$versionId/finalize", null, $bearer);
check('version finalized', $r['status'] === 200);
$r = call('client', 'GET', "/api/models/$modelId");
$files = array_column($r['json']['versions'][0]['files'], null, 'kind');
check('model shows 3d + files', $r['json']['model']['has_3d'] === true && isset($files['full'], $files['skp'], $files['manifest']), $r['json']);
check('stats stored', $r['json']['versions'][0]['stats']['faces'] === 10);

echo "File download\n";
$r = call('client', 'GET', '/api/files/' . $files['full']['id']);
check('glb served intact', isset($r['file']) && file_get_contents($r['file']) === $glb);
$r = call('client', 'GET', '/api/files/' . $files['skp']['id'], null, [], ['download' => '1']);
check('skp is gzipped on disk and inflates to original', $r['gzipped'] === true && gzdecode(file_get_contents($r['file'])) === $skp);
$r = call('anon', 'GET', '/api/files/' . $files['full']['id']);
check('anonymous file access blocked', $r['status'] === 401);

echo "Share links\n";
$r = call('editor', 'POST', "/api/models/$modelId/shares", ['label' => 'Client', 'password' => 'secret12', 'allow_download' => false, 'watermark' => 'CONFIDENTIAL']);
$share = $r['json']['share'];
check('share created', $r['status'] === 200 && $share['has_password']);
$r = call('anon', 'GET', '/api/share/' . $share['token']);
check('password required', $r['status'] === 401 && $r['json']['password_required']);
$r = call('anon', 'POST', '/api/share/' . $share['token'] . '/unlock', ['password' => 'nope']);
check('wrong share password', $r['status'] === 401);
$r = call('anon', 'POST', '/api/share/' . $share['token'] . '/unlock', ['password' => 'secret12']);
$key = $r['json']['key'];
check('unlock returns key', strlen($key) === 64);
$q = ['share' => $share['token'], 'k' => $key];
$r = call('anon', 'GET', "/api/models/$modelId", null, [], $q);
check('guest sees model without skp', $r['status'] === 200 && !in_array('skp', array_column($r['json']['versions'][0]['files'], 'kind'), true), $r['json']);
$r = call('anon', 'GET', '/api/files/' . $files['full']['id'], null, [], $q);
check('guest can stream glb', isset($r['file']));
$r = call('anon', 'GET', '/api/files/' . $files['skp']['id'], null, [], $q);
check('guest cannot download skp when disabled', $r['status'] === 403);
$r = call('anon', 'POST', "/api/models/$modelId/annotations", ['type' => 'comment', 'body' => 'hi'], [], $q);
check('guest cannot comment when disabled', $r['status'] === 403);
call('editor', 'PATCH', '/api/shares/' . $share['id'], ['allow_comments' => true, 'allow_download' => true]);
$key = call('anon', 'POST', '/api/share/' . $share['token'] . '/unlock', ['password' => 'secret12'])['json']['key'];
$q = ['share' => $share['token'], 'k' => $key];
$r = call('anon', 'POST', "/api/models/$modelId/annotations", ['type' => 'comment', 'body' => 'Move the window', 'author_name' => 'Sara', 'data' => ['p' => [1, 2, 3]]], [], $q);
check('guest comments when allowed', $r['status'] === 200 && $r['json']['annotation']['author_name'] === 'Sara (guest)', $r['json']);
$r = call('anon', 'GET', '/api/files/' . $files['skp']['id'], null, [], $q);
check('guest downloads skp when allowed', isset($r['file']));
$r = call('anon', 'GET', "/api/models/$modelId", null, [], ['share' => $share['token'], 'k' => 'forged']);
check('forged key rejected', $r['status'] === 401);
call('editor', 'PATCH', '/api/shares/' . $share['id'], ['expires_at' => '2000-01-01']);
$r = call('anon', 'GET', '/api/share/' . $share['token']);
check('expired link refused', $r['status'] === 410);
call('editor', 'PATCH', '/api/shares/' . $share['id'], ['expires_at' => null, 'revoked' => true]);
$r = call('anon', 'GET', '/api/share/' . $share['token']);
check('revoked link refused', $r['status'] === 404);

echo "Annotations & approval\n";
$r = call('client', 'POST', "/api/models/$modelId/annotations", ['type' => 'measure', 'data' => ['a' => [0, 0, 0], 'b' => [1, 0, 0]]]);
$annId = $r['json']['annotation']['id'];
check('commenter adds measurement', $r['status'] === 200);
$r = call('client', 'POST', "/api/models/$modelId/annotations", ['type' => 'bogus']);
check('unknown type rejected', $r['status'] === 422);
$r = call('editor', 'PATCH', "/api/annotations/$annId", ['status' => 'resolved']);
check('resolve annotation', $r['json']['annotation']['status'] === 'resolved');
$r = call('client', 'GET', "/api/models/$modelId/annotations");
check('list annotations', count($r['json']['annotations']) === 2);
$r = call('client', 'POST', "/api/versions/$versionId/approval", ['status' => 'approved', 'note' => 'Looks good']);
check('client approves version', $r['status'] === 200);
$r = call('editor', 'GET', "/api/models/$modelId");
check('approval visible', $r['json']['versions'][0]['approval_status'] === 'approved' && $r['json']['versions'][0]['approved_by_name'] === 'Client');

echo "Stats, deletion\n";
$r = call('admin', 'GET', '/api/admin/stats');
check('stats', $r['json']['models'] === 1 && $r['json']['storage_used'] > 0, $r['json']);
$r = call('admin', 'GET', '/api/admin/audit');
check('audit log has entries', count($r['json']['entries']) > 5);
$path = Db::val('SELECT path FROM files WHERE id = ?', [$files['full']['id']]);
$r = call('editor', 'DELETE', "/api/models/$modelId");
check('model deleted', $r['status'] === 200 && !is_file(App::storagePath($path)));
$r = call('admin', 'DELETE', '/api/admin/users/1');
check('admin cannot delete self', $r['status'] === 422);

echo "\n$passes passed, $fails failed\n";
exec('rm -rf ' . escapeshellarg($tmp));
exit($fails ? 1 : 0);
