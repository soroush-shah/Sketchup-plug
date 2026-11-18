<?php
declare(strict_types=1);

namespace App\Core;

final class Router
{
    private array $routes = [];

    public function add(string $method, string $pattern, callable $handler): void
    {
        $regex = '#^' . preg_replace('#\{(\w+)\}#', '(?P<$1>[^/]+)', $pattern) . '$#';
        $this->routes[] = [$method, $regex, $handler];
    }

    public function get(string $p, callable $h): void { $this->add('GET', $p, $h); }
    public function post(string $p, callable $h): void { $this->add('POST', $p, $h); }
    public function put(string $p, callable $h): void { $this->add('PUT', $p, $h); }
    public function patch(string $p, callable $h): void { $this->add('PATCH', $p, $h); }
    public function delete(string $p, callable $h): void { $this->add('DELETE', $p, $h); }

    public function dispatch(Request $req): void
    {
        $allowed = false;
        foreach ($this->routes as [$method, $regex, $handler]) {
            if (!preg_match($regex, $req->path, $m)) continue;
            $allowed = true;
            if ($method !== $req->method && !($method === 'GET' && $req->method === 'HEAD')) continue;
            $req->params = array_filter($m, 'is_string', ARRAY_FILTER_USE_KEY);
            $result = $handler($req);
            if ($result !== null) Response::json($result);
            return;
        }
        throw new HttpError($allowed ? 405 : 404, $allowed ? 'Method not allowed' : 'Not found');
    }
}
