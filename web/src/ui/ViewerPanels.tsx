import { useState } from 'preact/hooks';
import { del, fmtBytes, fmtDate, patch, post, type Annotation, type ModelDetail, type User, type Version } from '../lib/api';
import { toast } from '../lib/store';
import type { Manifest, RenderMode, SceneDef } from '../viewer/Viewer';
import { measureText } from '../viewer/Tools';
import type { LengthUnit } from '../viewer/units';
import * as THREE from 'three';
import { approvalPill } from './common';
import { Icon } from './icons';
import type { ViewerCtx } from './ModelPage';

export type PanelName = 'comments' | 'tags' | 'views' | 'settings' | 'info' | 'bom';

interface Props {
  name: PanelName; onClose: () => void; c: ViewerCtx; detail: ModelDetail; version: Version | null; manifest: Manifest | null;
  annotations: Annotation[]; selected: number | null; setSelected: (id: number | null) => void; canComment: boolean; canEdit: boolean;
  user: User | null; unit: LengthUnit;
  onFly: (a: Annotation) => void; onUpdate: (a: Annotation, ch: Partial<Annotation>) => void; onDelete: (a: Annotation) => void;
  onReply: (parent: Annotation, body: string) => void; onSaveView: (name: string) => void; onRestoreView: (vs: any) => void;
  onScene: (s: SceneDef) => void; onVersion: (id: number) => void; onCompare: (v: Version) => void; onReload: () => void;
  onDownload: (k: 'skp' | 'full') => void; rerender: () => void;
}

const TITLES: Record<PanelName, string> = { comments: 'Comments & notes', tags: 'Tags', views: 'Views & scenes', settings: 'Display', info: 'Model info', bom: 'Components' };

export function SidePanel(p: Props) {
  return (
    <aside class="side">
      <div class="side-head"><h2>{TITLES[p.name]}</h2><button class="btn ghost sm" onClick={p.onClose} aria-label="Close"><Icon name="close" /></button></div>
      <div class="side-body">
        {p.name === 'comments' && <Comments {...p} />}
        {p.name === 'tags' && <Tags {...p} />}
        {p.name === 'views' && <Views {...p} />}
        {p.name === 'settings' && <Settings {...p} />}
        {p.name === 'info' && <Info {...p} />}
        {p.name === 'bom' && <Bom {...p} />}
      </div>
    </aside>
  );
}

const canModify = (p: Props, a: Annotation) => a.id < 0 || p.canEdit || (p.user && a.user_id === p.user.id);

function Comments(p: Props) {
  const [filter, setFilter] = useState<'open' | 'all' | 'other'>('open');
  const [reply, setReply] = useState<Record<number, string>>({});
  const top = p.annotations.filter((a) => (a.type === 'comment' || a.type === 'markup' || a.type === 'note') && !a.parent_id);
  const list = filter === 'other' ? p.annotations.filter((a) => ['measure', 'line', 'highlight'].includes(a.type))
    : top.filter((a) => filter === 'all' || a.status === 'open');
  const replies = (id: number) => p.annotations.filter((a) => a.parent_id === id);

  return (
    <>
      <div class="seg" style="margin-bottom:10px">
        <button class={filter === 'open' ? 'on' : ''} onClick={() => setFilter('open')}>Open</button>
        <button class={filter === 'all' ? 'on' : ''} onClick={() => setFilter('all')}>All</button>
        <button class={filter === 'other' ? 'on' : ''} onClick={() => setFilter('other')}>Measurements</button>
      </div>
      <label class="check small"><input type="checkbox" checked={p.c.tools.visible} onChange={(e) => { p.c.tools.setVisible(e.currentTarget.checked); p.rerender(); }} />Show annotations in 3D</label>
      {!list.length && <p class="muted small">{filter === 'other' ? 'No measurements, lines or highlights yet.' : 'No comments. Use the comment pin or markup tool to start a discussion.'}</p>}
      {list.map((a) => (
        <div class={'list-item' + (p.selected === a.id ? ' sel' : '')} key={a.id} onClick={() => p.onFly(a)}>
          <div class="row small" style="gap:6px">
            <b>{a.author_name}</b><span class="muted">{fmtDate(a.created_at)}</span><span class="grow" />
            {a.type === 'comment' && (a.status === 'resolved' ? <span class="pill ok">resolved</span> : <span class="pill bad">open</span>)}
            {a.type !== 'comment' && <span class="pill">{a.type === 'measure' ? a.data?.kind : a.type}</span>}
          </div>
          {a.type === 'measure' && <div style="font-weight:700;margin-top:4px">{measureText(a.data.kind, a.data.points.map((x: number[]) => new THREE.Vector3().fromArray(x)), p.unit)}</div>}
          {a.type === 'markup' && a.data?.image && <img src={a.data.image} style="width:100%;border-radius:8px;margin-top:6px" alt="Markup" />}
          {a.body && <div style="white-space:pre-wrap;margin-top:4px">{a.body}</div>}
          <div class="row" style="margin-top:6px" onClick={(e) => e.stopPropagation()}>
            {(a.type === 'comment' || a.type === 'markup') && p.canComment && (
              <button class="btn sm" onClick={() => p.onUpdate(a, { status: a.status === 'open' ? 'resolved' : 'open' })}>{a.status === 'open' ? <><Icon name="check" size={14} />Resolve</> : 'Reopen'}</button>
            )}
            {a.type === 'markup' && <a class="btn sm" href={a.data.image} download="markup.jpg"><Icon name="download" size={14} /></a>}
            {canModify(p, a) && <button class="btn sm danger" onClick={() => confirm('Delete?') && p.onDelete(a)}><Icon name="trash" size={14} /></button>}
          </div>
          {replies(a.id).map((r) => (
            <div class="thread small" key={r.id}><b>{r.author_name}</b> <span class="muted">{fmtDate(r.created_at)}</span><div style="white-space:pre-wrap">{r.body}</div></div>
          ))}
          {p.canComment && a.type !== 'measure' && (
            <form class="row" style="margin-top:6px" onClick={(e) => e.stopPropagation()} onSubmit={(e) => {
              e.preventDefault();
              const t = (reply[a.id] || '').trim();
              if (t) { p.onReply(a, t); setReply({ ...reply, [a.id]: '' }); }
            }}>
              <input class="input grow" style="min-height:34px;padding:4px 8px" placeholder="Reply…" value={reply[a.id] || ''} onInput={(e) => setReply({ ...reply, [a.id]: e.currentTarget.value })} />
            </form>
          )}
        </div>
      ))}
    </>
  );
}

function Tags(p: Props) {
  const v = p.c.viewer;
  const tags = v.listTags();
  const colors = Object.fromEntries((p.manifest?.tags ?? []).map((t) => [t.name, t.color]));
  if (!tags.length) return <p class="muted small">This model has no tag information (publish with the SkpShare plugin to get tags).</p>;
  const setAll = (on: boolean) => { tags.forEach((t) => v.tagState.set(t, on)); v.applyTags(); p.rerender(); };
  return (
    <>
      <div class="row" style="margin-bottom:8px"><button class="btn sm" onClick={() => setAll(true)}>Show all</button><button class="btn sm" onClick={() => setAll(false)}>Hide all</button></div>
      {tags.map((t) => {
        const on = v.tagState.get(t) !== false;
        return (
          <label class="check" key={t} style="padding:6px 4px;border-bottom:1px solid var(--line)">
            <input type="checkbox" checked={on} onChange={(e) => { v.setTagVisible(t, e.currentTarget.checked); p.rerender(); }} />
            <span style={{ width: 12, height: 12, borderRadius: 3, background: colors[t] ?? '#cbd5e1', display: 'inline-block' }} />
            <span class="grow">{t}</span>
            <button class="btn ghost sm" title="Show only this tag" onClick={(e) => { e.preventDefault(); tags.forEach((x) => v.tagState.set(x, x === t)); v.applyTags(); p.rerender(); }}>solo</button>
          </label>
        );
      })}
    </>
  );
}

function Views(p: Props) {
  const views = p.annotations.filter((a) => a.type === 'view');
  const scenes = p.manifest?.scenes ?? [];
  const v = p.c.viewer;
  const copyLink = (a: Annotation) => {
    const u = new URL(location.href);
    u.searchParams.set('view', String(a.id));
    navigator.clipboard?.writeText(u.toString());
    toast('Link to this view copied');
  };
  return (
    <>
      <h3>Camera</h3>
      <div class="row" style="margin-bottom:12px">
        {(['iso', 'top', 'front', 'back', 'left', 'right'] as const).map((k) => <button class="btn sm" onClick={() => v.standardView(k)}>{k}</button>)}
        <button class="btn sm" onClick={() => v.fit(undefined, true)}>Fit</button>
      </div>
      {scenes.length > 0 && <>
        <h3>SketchUp scenes</h3>
        {scenes.map((s) => <div class="list-item" onClick={() => p.onScene(s)}><b>{s.name}</b>{s.description && <div class="small muted">{s.description}</div>}</div>)}
      </>}
      <h3 style="margin-top:12px">Saved views</h3>
      {p.canComment && (
        <form class="row" style="margin-bottom:8px" onSubmit={(e) => {
          e.preventDefault();
          const input = (e.currentTarget as HTMLFormElement).elements.namedItem('vn') as HTMLInputElement;
          p.onSaveView(input.value || `View ${views.length + 1}`);
          input.value = '';
        }}>
          <input name="vn" class="input grow" placeholder="Name this view (camera, section, tags)" />
          <button class="btn primary sm">Save</button>
        </form>
      )}
      {!views.length && <p class="muted small">No saved views yet.</p>}
      {views.map((a) => (
        <div class="list-item" key={a.id} onClick={() => p.onRestoreView(a.data)}>
          <div class="row"><b class="grow">{a.title || 'View'}</b>
            <button class="btn sm ghost" onClick={(e) => { e.stopPropagation(); copyLink(a); }} title="Copy link"><Icon name="share" size={14} /></button>
            {canModify(p, a) && <button class="btn sm ghost danger" onClick={(e) => { e.stopPropagation(); p.onDelete(a); }}><Icon name="trash" size={14} /></button>}
          </div>
          <div class="small muted">{a.author_name} · {a.data?.section?.mode !== 'off' ? 'with section' : 'no section'}</div>
        </div>
      ))}
    </>
  );
}

function Settings(p: Props) {
  const v = p.c.viewer;
  const [bg, setBg] = useState('#eef1f5');
  const mode = (m: RenderMode) => { v.setRenderMode(m); p.rerender(); };
  return (
    <>
      <h3>Style</h3>
      <div class="seg" style="margin-bottom:10px">
        {(['shaded', 'monochrome', 'xray', 'wireframe'] as RenderMode[]).map((m) => <button class={v.renderMode === m ? 'on' : ''} onClick={() => mode(m)}>{m === 'xray' ? 'X-ray' : m}</button>)}
      </div>
      <label class="check"><input type="checkbox" checked={v.edgesVisible} onChange={(e) => { v.setEdges(e.currentTarget.checked); p.rerender(); }} />Edges</label>
      <label class="check"><input type="checkbox" checked={v.camera === v.ortho} onChange={(e) => { v.setProjection(!e.currentTarget.checked); p.rerender(); }} />Parallel projection (orthographic)</label>
      <h3 style="margin-top:14px">Sun &amp; shadows</h3>
      <label class="check"><input type="checkbox" checked={v.shadows} onChange={(e) => { v.setShadows(e.currentTarget.checked); p.rerender(); }} />Cast shadows {v.isMobile && <span class="small muted">(slower on phones)</span>}</label>
      <label class="small">Direction {v.sunAngles.azimuth}°</label>
      <input type="range" min={0} max={360} value={v.sunAngles.azimuth} style="width:100%" onInput={(e) => { v.setSun(+e.currentTarget.value, v.sunAngles.elevation); p.rerender(); }} />
      <label class="small">Height {v.sunAngles.elevation}°</label>
      <input type="range" min={2} max={90} value={v.sunAngles.elevation} style="width:100%" onInput={(e) => { v.setSun(v.sunAngles.azimuth, +e.currentTarget.value); p.rerender(); }} />
      <h3 style="margin-top:14px">Background</h3>
      <div class="row">
        {['#eef1f5', '#ffffff', '#1f2937', '#0b1220', '#dbeafe'].map((c) => <button class={'swatch' + (bg === c ? ' on' : '')} style={{ background: c }} onClick={() => { setBg(c); v.setBackground(c); }} aria-label={c} />)}
      </div>
      <h3 style="margin-top:14px">Section fill colour</h3>
      <div class="row">
        {['#d94b4b', '#334155', '#f59e0b', '#16a34a', '#9ca3af'].map((c) => <button class="swatch" style={{ background: c }} onClick={() => { p.c.section.capColor.set(c); p.c.section.setCaps(p.c.section.caps); }} aria-label={c} />)}
      </div>
    </>
  );
}

function Info(p: Props) {
  const { detail, version } = p;
  const [note, setNote] = useState('');
  const st = version?.stats ?? {};
  const files = version?.files ?? [];
  const sum = (k: string) => files.filter((f) => f.kind === k).reduce((s, f) => s + f.size, 0);
  const approve = async (status: string) => {
    if (!version) return;
    await post(`api/versions/${version.id}/approval`, { status, note: note || null });
    toast(status === 'approved' ? 'Version approved' : status === 'changes_requested' ? 'Changes requested' : 'Reset to pending');
    p.onReload();
  };
  return (
    <>
      <h3>{detail.model.name}</h3>
      {detail.model.description && <p class="muted">{detail.model.description}</p>}
      {version && (
        <div class="card" style="background:var(--panel-2);margin-bottom:12px">
          <div class="row"><b>Version {version.version_no}</b>{approvalPill(version.approval_status)}</div>
          <div class="small muted">{fmtDate(version.created_at)} by {version.created_by_name ?? 'unknown'} · via {version.source}</div>
          {version.note && <p style="white-space:pre-wrap;margin:6px 0">{version.note}</p>}
          {version.approved_by_name && <div class="small muted">Review: {version.approved_by_name}, {fmtDate(version.approved_at)}{version.approval_note ? ` – “${version.approval_note}”` : ''}</div>}
          {p.user && p.canComment && (
            <div style="margin-top:8px">
              <input class="input" placeholder="Review note (optional)" value={note} onInput={(e) => setNote(e.currentTarget.value)} />
              <div class="row" style="margin-top:6px">
                <button class="btn sm primary" onClick={() => approve('approved')}><Icon name="check" size={14} />Approve</button>
                <button class="btn sm" onClick={() => approve('changes_requested')}>Request changes</button>
              </div>
            </div>
          )}
        </div>
      )}
      <h3>Files</h3>
      <table class="t small">
        <tbody>
          {sum('full') > 0 && <tr><td>3D view (compressed)</td><td>{fmtBytes(sum('full'))}</td><td>{detail.can_download && <button class="btn sm" onClick={() => p.onDownload('full')}>.glb</button>}</td></tr>}
          {sum('preview') > 0 && <tr><td>Quick preview</td><td>{fmtBytes(sum('preview'))}</td><td /></tr>}
          {files.filter((f) => f.kind === 'skp').map((f) => (
            <tr><td>Original SketchUp file</td><td>{fmtBytes(f.original_size)}{f.gzipped && <div class="muted">stored {fmtBytes(f.size)}</div>}</td><td>{detail.can_download && <button class="btn sm primary" onClick={() => p.onDownload('skp')}>.skp</button>}</td></tr>
          ))}
        </tbody>
      </table>
      {Object.keys(st).length > 0 && (
        <>
          <h3 style="margin-top:12px">Statistics</h3>
          <div class="small muted">
            {st.faces != null && <div>{Number(st.faces).toLocaleString()} faces · {Number(st.edges ?? 0).toLocaleString()} edges</div>}
            {st.instances != null && <div>{Number(st.instances).toLocaleString()} groups / components · {st.textures ?? 0} textures</div>}
            {st.skp != null && st.full != null && <div>Original {fmtBytes(st.skp)} → viewer {fmtBytes(st.full)} ({Math.max(1, Math.round(st.skp / Math.max(1, st.full)))}× smaller)</div>}
          </div>
        </>
      )}
      {detail.versions.length > 1 && (
        <>
          <h3 style="margin-top:14px">Versions</h3>
          {detail.versions.map((v) => (
            <div class={'list-item' + (v.id === version?.id ? ' sel' : '')} key={v.id} onClick={() => p.onVersion(v.id)}>
              <div class="row"><b>v{v.version_no}</b>{v.id === detail.model.current_version_id && <span class="pill">current</span>}{approvalPill(v.approval_status)}<span class="grow" /><span class="small muted">{fmtDate(v.created_at)}</span></div>
              {v.note && <div class="small">{v.note}</div>}
              <div class="row" style="margin-top:6px" onClick={(e) => e.stopPropagation()}>
                {v.id !== version?.id && v.has_3d && version?.has_3d && <button class="btn sm" onClick={() => p.onCompare(v)}><Icon name="compare" size={14} />Compare</button>}
                {p.canEdit && v.id !== detail.model.current_version_id && <button class="btn sm" onClick={async () => { await patch(`api/models/${detail.model.id}`, { current_version_id: v.id }); p.onReload(); }}>Make current</button>}
                {p.canEdit && <button class="btn sm danger" onClick={async () => { if (confirm(`Delete version ${v.version_no} and its files?`)) { await del(`api/versions/${v.id}`); p.onReload(); } }}><Icon name="trash" size={14} /></button>}
              </div>
            </div>
          ))}
        </>
      )}
      {p.canEdit && (
        <div class="row" style="margin-top:14px">
          <button class="btn sm" onClick={async () => { const n = prompt('Model name', detail.model.name); if (n) { await patch(`api/models/${detail.model.id}`, { name: n }); p.onReload(); } }}>Rename</button>
          <button class="btn sm" onClick={async () => { const d = prompt('Description', detail.model.description ?? ''); if (d !== null) { await patch(`api/models/${detail.model.id}`, { description: d }); p.onReload(); } }}>Edit description</button>
        </div>
      )}
    </>
  );
}

function Bom(p: Props) {
  const rows = p.manifest?.bom ?? [];
  const [q, setQ] = useState('');
  const shown = rows.filter((r) => r.name.toLowerCase().includes(q.toLowerCase()));
  const csv = () => {
    const esc = (s: unknown) => `"${String(s).replace(/"/g, '""')}"`;
    const lines = [['Component', 'Description', 'Count', 'Width (mm)', 'Depth (mm)', 'Height (mm)'].map(esc).join(','),
      ...rows.map((r) => [r.name, r.description, r.count, ...r.size_mm].map(esc).join(','))];
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob(['﻿' + lines.join('\n')], { type: 'text/csv' }));
    a.download = `${p.detail.model.name}-components.csv`;
    a.click();
  };
  return (
    <>
      <div class="row" style="margin-bottom:8px"><input class="input grow" placeholder="Filter…" value={q} onInput={(e) => setQ(e.currentTarget.value)} /><button class="btn sm" onClick={csv}><Icon name="download" size={14} />CSV</button></div>
      <table class="t small">
        <thead><tr><th>Component</th><th>Qty</th><th>Size (mm)</th></tr></thead>
        <tbody>{shown.map((r) => <tr><td>{r.name}{r.description && <div class="muted">{r.description}</div>}</td><td><b>{r.count}</b></td><td class="muted">{r.size_mm.map((x) => Math.round(x)).join(' × ')}</td></tr>)}</tbody>
      </table>
    </>
  );
}
