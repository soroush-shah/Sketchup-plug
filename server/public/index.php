<?php
declare(strict_types=1);

// Locate the application folder. Supported layouts:
//   1) public_html/ = this folder, app one level up (../src)       — most secure
//   2) everything inside public_html, app in ./_app (protected by .htaccess)
$root = is_file(__DIR__ . '/../src/bootstrap.php') ? dirname(__DIR__) : __DIR__ . '/_app';
require $root . '/src/bootstrap.php';

if (!is_file($root . '/config.php')) {
    header('Location: install.php');
    exit;
}
App\Core\App::boot(require $root . '/config.php');

$base = App\Core\App::basePath();
$req = App\Core\Request::fromGlobals($base);

if (str_starts_with($req->path, '/api/')) {
    skpshare_handle(skpshare_router(), $req);
    exit;
}

// Everything else is the single-page app.
$html = @file_get_contents(__DIR__ . '/index.html');
if ($html === false) {
    http_response_code(500);
    echo 'Web app not built: run "npm run build" in web/ and upload server/public.';
    exit;
}
$html = str_replace('<head>', '<head><base href="' . htmlspecialchars($base . '/') . '">', $html);
header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-cache');
header('X-Frame-Options: SAMEORIGIN');
header('Referrer-Policy: same-origin');
echo $html;
