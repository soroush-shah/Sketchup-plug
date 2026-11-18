<?php
declare(strict_types=1);

namespace App\Core;

final class HttpError extends \RuntimeException
{
    public function __construct(public int $status, string $message, public array $extra = [])
    {
        parent::__construct($message, $status);
    }
}

final class Request
{
    private ?array $jsonBody = null;

    public function __construct(
        public string $method,
        public string $path,
        public array $query,
        public array $headers,
        public ?string $rawBody = null,
        public array $params = [],
    ) {}

    public static function fromGlobals(string $basePath): self
    {
        $uri = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
        if ($basePath !== '' && str_starts_with($uri, $basePath)) $uri = substr($uri, strlen($basePath));
        $uri = '/' . ltrim($uri, '/');
        $headers = [];
        foreach ($_SERVER as $k => $v) {
            if (str_starts_with($k, 'HTTP_')) $headers[strtolower(str_replace('_', '-', substr($k, 5)))] = $v;
        }
        if (isset($_SERVER['CONTENT_TYPE'])) $headers['content-type'] = $_SERVER['CONTENT_TYPE'];
        // Some shared hosts (CGI/FastCGI) strip Authorization; .htaccess re-exposes it.
        if (!isset($headers['authorization']) && isset($_SERVER['REDIRECT_HTTP_AUTHORIZATION'])) {
            $headers['authorization'] = $_SERVER['REDIRECT_HTTP_AUTHORIZATION'];
        }
        $method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
        if ($method === 'POST' && isset($headers['x-http-method-override'])) {
            $method = strtoupper($headers['x-http-method-override']); // hosts that block PUT/DELETE
        }
        return new self($method, $uri, $_GET, $headers);
    }

    public function header(string $name): ?string { return $this->headers[strtolower($name)] ?? null; }

    public function body(): string
    {
        if ($this->rawBody === null) $this->rawBody = (string)file_get_contents('php://input');
        return $this->rawBody;
    }

    /** Stream of the raw request body (used for large chunk uploads without buffering twice). */
    public function bodyStream()
    {
        if ($this->rawBody !== null) {
            $s = fopen('php://memory', 'w+b');
            fwrite($s, $this->rawBody);
            rewind($s);
            return $s;
        }
        return fopen('php://input', 'rb');
    }

    public function json(): array
    {
        if ($this->jsonBody === null) {
            $b = $this->body();
            $this->jsonBody = $b === '' ? [] : (json_decode($b, true) ?? throw new HttpError(400, 'Invalid JSON body'));
        }
        return $this->jsonBody;
    }

    public function input(string $key, mixed $default = null): mixed { return $this->json()[$key] ?? $default; }

    public function str(string $key, int $max = 255, bool $required = false): ?string
    {
        $v = $this->input($key);
        if ($v === null || $v === '') {
            if ($required) throw new HttpError(422, "Field '$key' is required");
            return null;
        }
        $v = trim((string)$v);
        if (mb_strlen($v) > $max) throw new HttpError(422, "Field '$key' is too long");
        return $v;
    }

    public function int(string $key): ?int
    {
        $v = $this->input($key);
        return $v === null || $v === '' ? null : (int)$v;
    }

    public function bool(string $key, bool $default = false): bool
    {
        $v = $this->input($key);
        return $v === null ? $default : filter_var($v, FILTER_VALIDATE_BOOL);
    }

    public function ip(): string { return $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0'; }
}

final class Response
{
    /** In tests we capture instead of echoing. */
    public static bool $capture = false;
    public static array $captured = [];

    public static function json(mixed $data, int $status = 200): void
    {
        $body = json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        if (self::$capture) {
            self::$captured = ['status' => $status, 'body' => $body];
            return;
        }
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        header('Cache-Control: no-store');
        echo $body;
    }
}
