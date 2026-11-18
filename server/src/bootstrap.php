<?php
declare(strict_types=1);

spl_autoload_register(function (string $class) {
    if (!str_starts_with($class, 'App\\')) return;
    $rel = str_replace('\\', '/', substr($class, 4));
    // Core/Http.php hosts several small classes (Request, Response, HttpError).
    foreach ([__DIR__ . "/$rel.php", __DIR__ . '/Core/Http.php'] as $f) {
        if (is_file($f)) { require_once $f; if (class_exists($class, false)) return; }
    }
});

function skpshare_router(): App\Core\Router
{
    $r = new App\Core\Router();
    App\Api\AuthApi::register($r);
    App\Api\LibraryApi::register($r);
    App\Api\UploadApi::register($r);
    App\Api\ShareApi::register($r);
    App\Api\AnnotationApi::register($r);
    App\Api\AdminApi::register($r);
    return $r;
}

/** Handle one API request, converting errors to JSON. */
function skpshare_handle(App\Core\Router $router, App\Core\Request $req): void
{
    try {
        $router->dispatch($req);
    } catch (App\Core\HttpError $e) {
        App\Core\Response::json(['error' => $e->getMessage()] + $e->extra, $e->status);
    } catch (Throwable $e) {
        error_log('[skpshare] ' . $e);
        $debug = !empty(App\Core\App::$config['debug']);
        App\Core\Response::json(['error' => $debug ? $e->getMessage() : 'Server error'], 500);
    }
}
