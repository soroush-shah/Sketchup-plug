import { useEffect, useMemo, useState } from 'preact/hooks';
import { del, fileUrl, fmtBytes, fmtDate, get, patch, post, uploadFile, type ModelSummary, type Project } from '../lib/api';
import { offline } from '../lib/offline';
import { toast, useStore } from '../lib/store';
import { approvalPill, Empty, Link, Modal, Progress, TopBar } from './common';
import { Icon } from './icons';

export function Library() {
  const s = useStore();
  const [projects, setProjects] = useState<Project[] | null>(null);
  const [q, setQ] = useState('');
  const [err, setErr] = useState('');
  const [upload, setUpload] = useState<{ projectId?: number; modelId?: number } | null>(null);
  const [savedIds, setSavedIds] = useState<Set<number>>(new Set());
  const canEdit = s.user?.role !== 'viewer';

  const load = () => get<{ projects: Project[] }>('api/projects').then((r) => setProjects(r.projects)).catch((e) => setErr(e.message));
  useEffect(() => { load(); offline.list().then((l) => setSavedIds(new Set(l.map((x) => x.model_id)))); }, []);

  const filtered = useMemo(() => {
    if (!projects) return [];
    const term = q.trim().toLowerCase();
    if (!term) return projects;
    return projects.map((p) => ({ ...p, models: p.name.toLowerCase().includes(term) ? p.models : p.models.filter((m) => m.name.toLowerCase().includes(term)) }))
      .filter((p) => p.models.length || p.name.toLowerCase().includes(term));
  }, [projects, q]);

  const newProject = async () => {
    const name = prompt('Project name');
    if (!name) return;
    await post('api/projects', { name });
    load();
  };

  return (
    <>
      <TopBar />
      <main class="page">
        <div class="toolbar-line">
          <input class="input grow" style="max-width:420px" placeholder="Search models and projects…" value={q} onInput={(e) => setQ(e.currentTarget.value)} />
          <span class="grow" />
          {canEdit && <button class="btn" onClick={newProject}><Icon name="plus" size={16} />Project</button>}
          {canEdit && <button class="btn primary" onClick={() => setUpload({})}><Icon name="upload" size={16} />Upload</button>}
        </div>
        {err && <div class="error">{err}</div>}
        {projects && !projects.length && (
          <Empty>
            <h2>No models yet</h2>
            {canEdit ? <>Install the SketchUp plugin from <Link to="/account">Account</Link> and press <b>Publish</b>, or upload a .skp / .glb here.</> : 'Nothing has been shared with you yet.'}
          </Empty>
        )}
        {filtered.map((p) => (
          <section class="project" key={p.id}>
            <div class="project-head">
              <h2 style="margin:0">{p.name}</h2>
              <span class="muted small">{p.models.length} model{p.models.length === 1 ? '' : 's'}</span>
              <span class="grow" />
              {p.role === 'editor' && (
                <>
                  <button class="btn sm ghost" onClick={() => setUpload({ projectId: p.id })}><Icon name="upload" size={16} />Add</button>
                  <button class="btn sm ghost" onClick={async () => { const n = prompt('Rename project', p.name); if (n) { await patch(`api/projects/${p.id}`, { name: n }); load(); } }}>Rename</button>
                  <button class="btn sm ghost danger" onClick={async () => {
                    if (prompt(`Delete project "${p.name}" and ALL its models and files? Type DELETE to confirm`) === 'DELETE') { await del(`api/projects/${p.id}`); load(); toast('Project deleted'); }
                  }}><Icon name="trash" size={16} /></button>
                </>
              )}
            </div>
            {p.description && <p class="muted">{p.description}</p>}
            <div class="grid">
              {p.models.map((m) => <ModelCard key={m.id} m={m} offline={savedIds.has(m.id)} />)}
              {!p.models.length && <div class="muted small">Empty project</div>}
            </div>
          </section>
        ))}
      </main>
      {upload && projects && <UploadDialog projects={projects.filter((p) => p.role === 'editor')} init={upload} onClose={() => setUpload(null)} onDone={() => { setUpload(null); load(); }} />}
    </>
  );
}

function ModelCard({ m, offline: saved }: { m: ModelSummary; offline: boolean }) {
  return (
    <Link to={`/m/${m.id}`} class="mcard">
      <div class="thumb">{m.thumb_file_id ? <img loading="lazy" src={fileUrl(m.thumb_file_id)} alt="" /> : <Icon name={m.has_3d ? 'views' : 'download'} size={36} />}</div>
      <div class="body">
        <div class="name" title={m.name}>{m.name}</div>
        <div class="row small muted" style="gap:6px">
          <span>v{m.version_no ?? 0}</span>·<span>{fmtDate(m.updated_at)}</span>
        </div>
        <div class="row small" style="gap:6px">
          {approvalPill(m.approval_status)}
          {!m.has_3d && <span class="pill">.skp only</span>}
          {m.open_comments > 0 && <span class="pill bad">{m.open_comments} open</span>}
          {saved && <span class="pill ok">offline</span>}
        </div>
        {m.has_3d && m.skp_size > 0 && <div class="small muted">View {fmtBytes(m.view_size)} · SKP {fmtBytes(m.skp_size)}</div>}
      </div>
    </Link>
  );
}

/** Web upload: .skp (stored for download) and/or .glb (3D view). Uses the same resumable chunk API as the plugin. */
export function UploadDialog({ projects, init, onClose, onDone }: { projects: Project[]; init: { projectId?: number; modelId?: number }; onClose: () => void; onDone: (modelId: number) => void }) {
  const [projectId, setProjectId] = useState<number | 'new'>(init.projectId ?? projects[0]?.id ?? 'new');
  const [projectName, setProjectName] = useState('');
  const project = projects.find((p) => p.id === projectId);
  const [modelId, setModelId] = useState<number | 'new'>(init.modelId ?? 'new');
  const [modelName, setModelName] = useState('');
  const [note, setNote] = useState('');
  const [skp, setSkp] = useState<File | null>(null);
  const [glb, setGlb] = useState<File | null>(null);
  const [progress, setProgress] = useState<{ label: string; v: number } | null>(null);
  const [err, setErr] = useState('');

  const pick = (files: FileList | null) => {
    for (const f of Array.from(files ?? [])) {
      const n = f.name.toLowerCase();
      if (n.endsWith('.skp')) { setSkp(f); if (!modelName) setModelName(f.name.replace(/\.skp$/i, '')); }
      else if (n.endsWith('.glb')) { setGlb(f); if (!modelName) setModelName(f.name.replace(/\.glb$/i, '')); }
      else setErr(`Unsupported file: ${f.name} (use .skp or .glb)`);
    }
  };

  const run = async () => {
    setErr('');
    if (!skp && !glb) return setErr('Choose a .skp and/or .glb file');
    try {
      let pid = projectId;
      if (pid === 'new') pid = (await post<{ id: number }>('api/projects', { name: projectName || 'Uploads' })).id;
      let mid = modelId;
      if (mid === 'new') mid = (await post<{ id: number }>('api/models', { project_id: pid, name: modelName || 'Model' })).id;
      const v = await post<{ id: number }>(`api/models/${mid}/versions`, { note: note || null, source: 'web' });
      const total = (skp?.size ?? 0) + (glb?.size ?? 0);
      let base = 0;
      for (const [kind, f] of [['full', glb], ['skp', skp]] as const) {
        if (!f) continue;
        await uploadFile(v.id, kind, f, f.name, (sent) => setProgress({ label: `Uploading ${f.name}`, v: (base + sent) / total }));
        base += f.size;
      }
      await post(`api/versions/${v.id}/finalize`);
      toast('Upload complete');
      onDone(mid as number);
    } catch (e: any) {
      setErr(e.message);
      setProgress(null);
    }
  };

  return (
    <Modal title="Upload model" onClose={progress ? () => {} : onClose}>
      {err && <div class="error" style="margin-bottom:10px">{err}</div>}
      <p class="small muted" style="margin-top:0">For the fast compressed 3D viewer with scenes, tags and sections, publish from SketchUp with the plugin. Here you can upload a <b>.skp</b> (download/share only) and/or a <b>.glb</b> (viewable in 3D).</p>
      <label class="f">Project</label>
      <select class="input" value={String(projectId)} onChange={(e) => { const v = e.currentTarget.value; setProjectId(v === 'new' ? 'new' : +v); setModelId('new'); }}>
        {projects.map((p) => <option value={p.id}>{p.name}</option>)}
        <option value="new">+ New project…</option>
      </select>
      {projectId === 'new' && <input class="input" style="margin-top:6px" placeholder="Project name" value={projectName} onInput={(e) => setProjectName(e.currentTarget.value)} />}
      <label class="f">Model</label>
      <select class="input" value={String(modelId)} onChange={(e) => { const v = e.currentTarget.value; setModelId(v === 'new' ? 'new' : +v); }}>
        <option value="new">+ New model…</option>
        {project?.models.map((m) => <option value={m.id}>{m.name} (new version)</option>)}
      </select>
      {modelId === 'new' && <input class="input" style="margin-top:6px" placeholder="Model name" value={modelName} onInput={(e) => setModelName(e.currentTarget.value)} />}
      <label class="f">Files</label>
      <label class="card" style="display:block;text-align:center;border-style:dashed;cursor:pointer"
        onDragOver={(e) => e.preventDefault()} onDrop={(e) => { e.preventDefault(); pick(e.dataTransfer?.files ?? null); }}>
        <input type="file" accept=".skp,.glb" multiple class="hidden" onChange={(e) => pick(e.currentTarget.files)} />
        <Icon name="upload" size={28} /><br />Drop files or tap to choose
        <div class="small muted">{skp && `SKP: ${skp.name} (${fmtBytes(skp.size)})`}{skp && glb && ' · '}{glb && `GLB: ${glb.name} (${fmtBytes(glb.size)})`}</div>
      </label>
      <label class="f">Version note</label>
      <input class="input" value={note} onInput={(e) => setNote(e.currentTarget.value)} placeholder="Optional" />
      {progress && <div style="margin-top:14px"><div class="small">{progress.label} – {Math.round(progress.v * 100)}%</div><Progress value={progress.v} /></div>}
      <div class="row" style="margin-top:16px;justify-content:flex-end">
        <button class="btn" onClick={onClose} disabled={!!progress}>Cancel</button>
        <button class="btn primary" onClick={run} disabled={!!progress}>Upload</button>
      </div>
    </Modal>
  );
}
