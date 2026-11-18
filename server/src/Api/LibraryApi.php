<?php
declare(strict_types=1);

namespace App\Api;

use App\Core\{App, Auth, Db, HttpError, Request, Router};

/** Projects, models and versions. */
final class LibraryApi
{
    public static function visibleProjects(array $u): array
    {
        if ($u['role'] === 'admin') return Db::all('SELECT * FROM projects ORDER BY name');
        return Db::all('SELECT DISTINCT p.* FROM projects p
            LEFT JOIN permissions pp ON pp.project_id = p.id AND pp.user_id = ?
            LEFT JOIN models m ON m.project_id = p.id
            LEFT JOIN permissions mp ON mp.model_id = m.id AND mp.user_id = ?
            WHERE pp.id IS NOT NULL OR mp.id IS NOT NULL' . ($u['role'] === 'editor' ? ' OR p.created_by = ' . (int)$u['id'] : '') . '
            ORDER BY p.name', [$u['id'], $u['id']]);
    }

    public static function register(Router $r): void
    {
        $r->get('/api/projects', function (Request $req) {
            $u = Auth::require($req);
            $out = [];
            foreach (self::visibleProjects($u) as $p) {
                $models = [];
                foreach (Db::all('SELECT * FROM models WHERE project_id = ? ORDER BY updated_at DESC', [$p['id']]) as $m) {
                    if (Auth::modelRole($u, $m)) $models[] = Common::modelSummary($m);
                }
                $out[] = ['id' => (int)$p['id'], 'name' => $p['name'], 'description' => $p['description'],
                    'created_at' => $p['created_at'], 'role' => Auth::projectRole($u, $p), 'models' => $models];
            }
            return ['projects' => $out];
        });

        $r->post('/api/projects', function (Request $req) {
            $u = Auth::require($req);
            if ($u['role'] === 'viewer') throw new HttpError(403, 'Viewers cannot create projects');
            $id = Db::insert('projects', ['name' => $req->str('name', 190, true), 'description' => $req->str('description', 2000),
                'created_by' => $u['id'], 'created_at' => Db::now()]);
            App::audit($u, 'project_created', "project:$id");
            return ['id' => $id];
        });

        $r->patch('/api/projects/{id}', function (Request $req) {
            $u = Auth::require($req);
            $p = Common::project((int)$req->params['id']);
            if (!Auth::atLeast(Auth::projectRole($u, $p), 'editor')) throw new HttpError(403, 'Not allowed');
            $row = array_filter(['name' => $req->str('name', 190), 'description' => $req->str('description', 2000)], fn($v) => $v !== null);
            if ($row) Db::update('projects', $row, 'id = ?', [$p['id']]);
            return ['ok' => true];
        });

        $r->delete('/api/projects/{id}', function (Request $req) {
            $u = Auth::require($req);
            $p = Common::project((int)$req->params['id']);
            if (!Auth::atLeast(Auth::projectRole($u, $p), 'editor')) throw new HttpError(403, 'Not allowed');
            foreach (Db::all('SELECT v.id FROM model_versions v JOIN models m ON m.id = v.model_id WHERE m.project_id = ?', [$p['id']]) as $v) {
                Common::deleteVersionFiles((int)$v['id']);
            }
            Db::exec('DELETE FROM projects WHERE id = ?', [$p['id']]);
            App::audit($u, 'project_deleted', "project:{$p['id']}", $p['name']);
            return ['ok' => true];
        });

        // ---------------------------------------------------------------- models
        $r->get('/api/models', function (Request $req) {
            $u = Auth::require($req);
            $q = '%' . ($req->query['q'] ?? '') . '%';
            $rows = Db::all('SELECT * FROM models WHERE name LIKE ? ORDER BY updated_at DESC LIMIT 500', [$q]);
            if (isset($req->query['project_id'])) $rows = array_filter($rows, fn($m) => (int)$m['project_id'] === (int)$req->query['project_id']);
            $out = [];
            foreach ($rows as $m) if (Auth::modelRole($u, $m)) $out[] = Common::modelSummary($m);
            return ['models' => $out];
        });

        $r->post('/api/models', function (Request $req) {
            $u = Auth::require($req);
            $p = Common::project((int)$req->input('project_id'));
            if (!Auth::atLeast(Auth::projectRole($u, $p), 'editor')) throw new HttpError(403, 'You cannot add models to this project');
            $now = Db::now();
            $id = Db::insert('models', ['project_id' => $p['id'], 'name' => $req->str('name', 190, true),
                'description' => $req->str('description', 2000), 'created_by' => $u['id'], 'created_at' => $now, 'updated_at' => $now]);
            App::audit($u, 'model_created', "model:$id");
            return ['id' => $id];
        });

        $r->get('/api/models/{id}', function (Request $req) {
            $m = Common::model((int)$req->params['id']);
            $acc = Auth::modelAccess($req, $m);
            $includeSkp = !$acc['share'] || $acc['share']['allow_download'];
            $versions = [];
            $rows = $acc['share']
                ? Db::all('SELECT * FROM model_versions WHERE id = ?', [$acc['share']['version_id'] ?: $m['current_version_id']])
                :Db::all("SELECT * FROM model_versions WHERE model_id = ? AND status = 'ready' ORDER BY version_no DESC", [$m['id']]);
            foreach ($rows as $v) $versions[] = Common::versionPayload($v, $includeSkp);
            $project = Common::project((int)$m['project_id']);
            return ['model' => Common::modelSummary($m), 'project' => ['id' => (int)$project['id'], 'name' => $project['name']],
                'versions' => $versions, 'role' => $acc['role'], 'can_download' => $includeSkp,
                'share' => $acc['share'] ? ShareApi::publicLink($acc['share']) : null];
        });

        $r->patch('/api/models/{id}', function (Request $req) {
            $m = Common::model((int)$req->params['id']);
            $acc = Auth::modelAccess($req, $m, 'editor');
            $row = array_filter(['name' => $req->str('name', 190), 'description' => $req->str('description', 2000)], fn($v) => $v !== null);
            if ($pid = $req->int('project_id')) {
                $p = Common::project($pid);
                if (!Auth::atLeast(Auth::projectRole($acc['user'], $p), 'editor')) throw new HttpError(403, 'Cannot move to that project');
                $row['project_id'] = $pid;
            }
            if ($cv = $req->int('current_version_id')) {
                $v = Common::version($cv);
                if ((int)$v['model_id'] !== (int)$m['id'] || $v['status'] !== 'ready') throw new HttpError(422, 'Invalid version');
                $row['current_version_id'] = $cv;
            }
            if ($row) {
                $row['updated_at'] = Db::now();
                Db::update('models', $row, 'id = ?', [$m['id']]);
            }
            App::audit($acc['user'], 'model_updated', "model:{$m['id']}", $row);
            return ['ok' => true];
        });

        $r->delete('/api/models/{id}', function (Request $req) {
            $m = Common::model((int)$req->params['id']);
            $acc = Auth::modelAccess($req, $m, 'editor');
            foreach (Db::all('SELECT id FROM model_versions WHERE model_id = ?', [$m['id']]) as $v) Common::deleteVersionFiles((int)$v['id']);
            Db::exec('DELETE FROM models WHERE id = ?', [$m['id']]);
            App::audit($acc['user'], 'model_deleted', "model:{$m['id']}", $m['name']);
            return ['ok' => true];
        });

        // ---------------------------------------------------------------- versions
        $r->post('/api/models/{id}/versions', function (Request $req) {
            $m = Common::model((int)$req->params['id']);
            $acc = Auth::modelAccess($req, $m, 'editor');
            $no = (int)Db::val('SELECT COALESCE(MAX(version_no),0) FROM model_versions WHERE model_id = ?', [$m['id']]) + 1;
            $source = $req->str('source', 20) === 'web' ? 'web' : 'plugin';
            $stats = $req->input('stats');
            $id = Db::insert('model_versions', ['model_id' => $m['id'], 'version_no' => $no, 'note' => $req->str('note', 5000),
                'status' => 'uploading', 'source' => $source, 'stats_json' => $stats ? json_encode($stats) : null,
                'created_by' => $acc['user']['id'], 'created_at' => Db::now()]);
            return ['id' => $id, 'version_no' => $no, 'chunk_size' => App::chunkSize()];
        });

        $r->post('/api/versions/{id}/finalize', function (Request $req) {
            $v = Common::version((int)$req->params['id']);
            $m = Common::model((int)$v['model_id']);
            $acc = Auth::modelAccess($req, $m, 'editor');
            $kinds = array_column(Db::all('SELECT kind FROM files WHERE version_id = ?', [$v['id']]), 'kind');
            if (!$kinds) throw new HttpError(422, 'No files were uploaded for this version');
            $has3d = in_array('full', $kinds, true) || in_array('preview', $kinds, true);
            Db::update('model_versions', ['status' => 'ready', 'has_3d' => $has3d ? 1 : 0], 'id = ?', [$v['id']]);
            Db::update('models', ['current_version_id' => $v['id'], 'updated_at' => Db::now()], 'id = ?', [$m['id']]);
            Db::exec("DELETE FROM upload_sessions WHERE version_id = ?", [$v['id']]);
            App::audit($acc['user'], 'version_published', "model:{$m['id']}", ['version' => (int)$v['version_no']]);
            return ['ok' => true, 'model_id' => (int)$m['id'], 'version_id' => (int)$v['id'], 'url' => App::basePath() . '/m/' . $m['id']];
        });

        $r->patch('/api/versions/{id}', function (Request $req) {
            $v = Common::version((int)$req->params['id']);
            Auth::modelAccess($req, Common::model((int)$v['model_id']), 'editor');
            Db::update('model_versions', ['note' => $req->str('note', 5000)], 'id = ?', [$v['id']]);
            return ['ok' => true];
        });

        $r->delete('/api/versions/{id}', function (Request $req) {
            $v = Common::version((int)$req->params['id']);
            $m = Common::model((int)$v['model_id']);
            $acc = Auth::modelAccess($req, $m, 'editor');
            Common::deleteVersionFiles((int)$v['id']);
            Db::exec('DELETE FROM model_versions WHERE id = ?', [$v['id']]);
            if ((int)$m['current_version_id'] === (int)$v['id']) {
                $latest = Db::val("SELECT id FROM model_versions WHERE model_id = ? AND status = 'ready' ORDER BY version_no DESC LIMIT 1", [$m['id']]);
                Db::update('models', ['current_version_id' => $latest ?: null], 'id = ?', [$m['id']]);
            }
            App::audit($acc['user'], 'version_deleted', "model:{$m['id']}", ['version' => (int)$v['version_no']]);
            return ['ok' => true];
        });

        // Client approval workflow
        $r->post('/api/versions/{id}/approval', function (Request $req) {
            $v = Common::version((int)$req->params['id']);
            $m = Common::model((int)$v['model_id']);
            $acc = Auth::modelAccess($req, $m, 'commenter');
            if (!$acc['user']) throw new HttpError(401, 'Log in to approve versions');
            $status = $req->str('status', 30, true);
            if (!in_array($status, ['pending', 'approved', 'changes_requested'], true)) throw new HttpError(422, 'Invalid status');
            Db::update('model_versions', ['approval_status' => $status, 'approval_note' => $req->str('note', 5000),
                'approved_by' => $acc['user']['id'], 'approved_at' => Db::now()], 'id = ?', [$v['id']]);
            App::audit($acc['user'], 'version_' . $status, "model:{$m['id']}", ['version' => (int)$v['version_no']]);
            return ['ok' => true];
        });
    }
}
