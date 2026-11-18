<?php
// Copy to config.php (the web installer does this for you).
return [
    'db' => [
        'driver' => 'mysql',          // 'mysql' on your host; 'sqlite' also works for small installs
        'host' => 'localhost',
        'port' => 3306,
        'name' => 'skpshare',
        'user' => 'skpshare',
        'pass' => 'change-me',
        // 'path' => __DIR__ . '/storage/skpshare.sqlite',   // when driver = sqlite
    ],
    'secret' => 'generate-a-long-random-string',
    'base_path' => '',                // e.g. '/viewer' if installed in a sub folder
    'storage_path' => __DIR__ . '/storage',
    'chunk_size' => 4 * 1024 * 1024,  // must be below your host's upload_max_filesize / post_max_size
    'max_file_size' => 3 * 1024 * 1024 * 1024,
    'storage_quota' => 0,             // bytes, optional, only for the admin dashboard gauge
    'debug' => false,
];
