<?php
// Run from server/:  php -S 127.0.0.1:8089 -t public dev-router.php
// Router for PHP's built-in server (development only): emulates public/.htaccess.
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$file = __DIR__ . '/public' . $path;
if ($path !== '/' && is_file($file) && !str_ends_with($file, '.php')) return false;
if ($path === '/install.php') { require __DIR__ . '/public/install.php'; return true; }
$_SERVER['SCRIPT_NAME'] = '/index.php';
require __DIR__ . '/public/index.php';
