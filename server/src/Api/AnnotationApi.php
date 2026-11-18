<?php
declare(strict_types=1);

namespace App\Api;

use App\Core\{Auth, Db, HttpError, Request, Router};

/**
 * Measurements, 3D lines, highlights, notes, comments (threaded, open/resolved),
 * 2D markups and saved views. Geometry lives in data_json and is interpreted by the viewer.
 */
final class AnnotationApi
{
    public const TYPES = ['measure', 'line', 'highlight', 'note', 'comment', 'markup', 'view', 'section'];

    public static function payload(array $a): array
    {
        return ['id' => (int)$a['id'], 'model_id' => (int)$a['model_id'],
            'version_id' => $a['version_id'] ? (int)$a['version_id'] : null,
            'parent_id' => $a['parent_id'] ? (int)$a['parent_id'] : null,
            'user_id' => $a['user_id'] ? (int)$a['user_id'] : null, 'author_name' => $a['author_name'],
            'type' => $a['type'], 'title' => $a['title'], 'body' => $a['body'],
            'data' => $a['data_json'] ? json_decode($a['data_json'], true) : null, 'status' => $a['status'],
            'created_at' => $a['created_at'], 'updated_at' => $a['updated_at']];
    }

    public static function register(Router $r): void
    {
        $r->get('/api/models/{id}/annotations', function (Request $req) {
            $m = Common::model((int)$req->params['id']);
            Auth::modelAccess($req, $m);
            $rows = Db::all('SELECT * FROM annotations WHERE model_id = ? ORDER BY id', [$m['id']]);
            return ['annotations' => array_map([self::class, 'payload'], $rows)];
        });

        $r->post('/api/models/{id}/annotations', function (Request $req) {
            $m = Common::model((int)$req->params['id']);
            $acc = Auth::modelAccess($req, $m, 'commenter');
            $type = (string)$req->str('type', 20, true);
            if (!in_array($type, self::TYPES, true)) throw new HttpError(422, 'Unknown annotation type');
            $author = $acc['user']['name'] ?? ($req->str('author_name', 100) ?? 'Guest');
            if (!$acc['user']) $author .= ' (guest)';
            $parent = $req->int('parent_id');
            if ($parent && !Db::val('SELECT id FROM annotations WHERE id = ? AND model_id = ?', [$parent, $m['id']])) {
                throw new HttpError(422, 'Parent not found');
            }
            $data = $req->input('data');
            $json = $data === null ? null : json_encode($data);
            if ($json !== null && strlen($json) > 2_000_000) throw new HttpError(413, 'Annotation too large');
            $now = Db::now();
            $id = Db::insert('annotations', ['model_id' => $m['id'], 'version_id' => $req->int('version_id'),
                'parent_id' => $parent, 'user_id' => $acc['user']['id'] ?? null, 'author_name' => $author, 'type' => $type,
                'title' => $req->str('title', 255), 'body' => $req->str('body', 20000), 'data_json' => $json,
                'status' => 'open', 'created_at' => $now, 'updated_at' => $now]);
            return ['annotation' => self::payload(Db::one('SELECT * FROM annotations WHERE id = ?', [$id]))];
        });

        $r->patch('/api/annotations/{id}', function (Request $req) {
            $a = Db::one('SELECT * FROM annotations WHERE id = ?', [(int)$req->params['id']]) ?? throw new HttpError(404, 'Not found');
            $acc = Auth::modelAccess($req, Common::model((int)$a['model_id']), 'commenter');
            $own = $acc['user'] && (int)$a['user_id'] === $acc['user']['id'];
            $row = [];
            $j = $req->json();
            if (array_key_exists('status', $j)) {
                $st = $req->str('status', 20);
                if (!in_array($st, ['open', 'resolved'], true)) throw new HttpError(422, 'Invalid status');
                $row['status'] = $st; // anyone who can comment can resolve
            }
            if (array_intersect(array_keys($j), ['title', 'body', 'data'])) {
                if (!$own && $acc['role'] !== 'editor') throw new HttpError(403, 'Only the author can edit this');
                if (array_key_exists('title', $j)) $row['title'] = $req->str('title', 255);
                if (array_key_exists('body', $j)) $row['body'] = $req->str('body', 20000);
                if (array_key_exists('data', $j)) $row['data_json'] = json_encode($j['data']);
            }
            if ($row) {
                $row['updated_at'] = Db::now();
                Db::update('annotations', $row, 'id = ?', [$a['id']]);
            }
            return ['annotation' => self::payload(Db::one('SELECT * FROM annotations WHERE id = ?', [$a['id']]))];
        });

        $r->delete('/api/annotations/{id}', function (Request $req) {
            $a = Db::one('SELECT * FROM annotations WHERE id = ?', [(int)$req->params['id']]) ?? throw new HttpError(404, 'Not found');
            $acc = Auth::modelAccess($req, Common::model((int)$a['model_id']), 'commenter');
            $own = $acc['user'] && (int)$a['user_id'] === $acc['user']['id'];
            if (!$own && $acc['role'] !== 'editor') throw new HttpError(403, 'Only the author or an editor can delete this');
            Db::exec('DELETE FROM annotations WHERE id = ? OR parent_id = ?', [$a['id'], $a['id']]);
            return ['ok' => true];
        });
    }
}
