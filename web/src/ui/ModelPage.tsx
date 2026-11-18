import { useCallback, useEffect, useMemo, useRef, useState } from 'preact/hooks';
import * as THREE from 'three';
import {
  ApiError, del, fetchFile, fileUrl, fmtBytes, loadAnnotations, loadModel, patch, post, shareCtx,
  type Annotation, type ModelDetail, type Version,
} from '../lib/api';
import { offline } from '../lib/offline';
import { navigate, toast, useStore } from '../lib/store';
import { Viewer, type Manifest, type RenderMode, type SceneDef } from '../viewer/Viewer';
import { SectionTool } from '../viewer/Section';
import { WalkControls } from '../viewer/Walk';
import { Annotator, type DraftResult, type MeasureKind, type ToolName } from '../viewer/Tools';
import { arSupport, isIOS, openQuickLook, startWebXR } from '../viewer/AR';
import type { LengthUnit } from '../viewer/units';
import { Modal, Progress } from './common';
import { Icon } from './icons';
import { Joystick } from './Joystick';
import { MarkupEditor } from './MarkupEditor';
import { ShareDialog } from './ShareDialog';
import { SidePanel, type PanelName } from './ViewerPanels';

type Mode = 'orbit' | 'walk' | 'section' | 'measure' | 'line' | 'highlight' | 'comment';
const COLORS = ['#ef4444', '#f59e0b', '#facc15', '#22c55e', '#2563eb', '#a855f7'];

export interface ViewerCtx {
  viewer: Viewer; section: SectionTool; tools: Annotator; walk: WalkControls;
}

export function ModelPage({ id, shareToken }: { id: number; shareToken?: string }) {
  const s = useStore();
  const [detail, setDetail] = useState<(ModelDetail & { offline?: boolean }) | null>(null);
  const [err, setErr] = useState<{ status: number; message: string } | null>(null);
  const [versionId, setVersionId] = useState<number | null>(null);
  const [annotations, setAnnotations] = useState<Annotation[]>([]);
  const [manifest, setManifest] = useState<Manifest | null>(null);
  const [loading, setLoading] = useState<{ label: string; v: number } | null>(null);
  const [mode, setModeState] = useState<Mode>('orbit');
  const [panel, setPanel] = useState<PanelName | null>(null);
  const [showScenes, setShowScenes] = useState(true);
  const [activeScene, setActiveScene] = useState<string | null>(null);
  const [shareOpen, setShareOpen] = useState(false);
  const [markup, setMarkup] = useState<string | null>(null);
  const [composer, setComposer] = useState<{ data: any } | null>(null);
  const [selected, setSelected] = useState<number | null>(null);
  const [compare, setCompare] = useState<Version | null>(null);
  const [presenting, setPresenting] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [saved, setSaved] = useState<{ version_id: number } | null>(null);
  const [saving, setSaving] = useState<number | null>(null);
  const [ar, setAr] = useState<'quicklook' | 'webxr' | null>(null);
  const [, bump] = useState(0);
  const rerender = () => bump((x) => x + 1);
  const canvasRef = useRef<HTMLDivElement>(null);
  const arOverlay = useRef<HTMLDivElement>(null);
  const ctx = useRef<ViewerCtx | null>(null);
  const loadToken = useRef(0);

  const role = detail?.role ?? 'viewer';
  const canComment = role === 'commenter' || role === 'editor';
  const canEdit = role === 'editor' && !shareToken;
  const version = detail?.versions.find((v) => v.id === versionId) ?? null;
  const unit = (manifest?.units?.length as LengthUnit) || 'mm';

  // ---------------------------------------------------------------- data
  const reload = useCallback(async () => {
    try {
      const d = await loadModel(id);
      setAnnotations(await loadAnnotations(id).catch(() => []));
      setDetail(d);
      const q = new URLSearchParams(location.search).get('v');
      setVersionId((cur) => cur && d.versions.some((v) => v.id === cur) ? cur
        : (q && d.versions.some((v) => v.id === +q) ? +q : d.share?.version_id ?? d.model.current_version_id ?? d.versions[0]?.id ?? null));
      const e = await offline.entry(id);
      setSaved(e ? { version_id: e.version_id } : null);
    } catch (e) {
      const ae = e as ApiError;
      setErr({ status: ae.status, message: ae.message });
    }
  }, [id]);
  useEffect(() => { reload(); }, [reload]);
  useEffect(() => { arSupport().then(setAr); }, []);

  // ---------------------------------------------------------------- viewer lifecycle
  useEffect(() => {
    const el = canvasRef.current;
    if (!el) return;
    const viewer = new Viewer(el);
    const section = new SectionTool(viewer);
    const tools = new Annotator(viewer);
    const walk = new WalkControls(viewer);
    ctx.current = { viewer, section, tools, walk };
    (window as any).__skp = ctx.current; // handy for debugging & automated tests
    const offs = [
      viewer.on('section', rerender), viewer.on('tags', rerender), viewer.on('draft', rerender),
      viewer.on('notice', (m: string) => toast(m)), viewer.on('section-pick', (on: boolean) => setNotice(on ? 'Tap a surface to cut there' : null)),
    ];
    return () => { offs.forEach((o) => o()); walk.disable(); section.dispose(); tools.dispose(); viewer.dispose(); ctx.current = null; };
  }, [!!detail]);

  // Load the 3D files of the selected version: manifest → preview (fast) → full.
  useEffect(() => {
    const c = ctx.current;
    if (!c || !version) return;
    const token = ++loadToken.current;
    const files = Object.fromEntries(version.files.map((f) => [f.kind, f]));
    (async () => {
      try {
        let man: Manifest | null = null;
        if (files.manifest) man = JSON.parse(new TextDecoder().decode(await fetchFile(files.manifest.id)));
        if (token !== loadToken.current) return;
        setManifest(man);
        if (man?.units?.length) c.tools.unit = man.units.length as LengthUnit;
        c.tools.precision = man?.units?.precision ?? 0;
        if (!version.has_3d) { setLoading(null); return; }
        const first = files.preview ?? files.full;
        const progress = (label: string) => (l: number, t: number) => token === loadToken.current && setLoading({ label, v: t ? l / t : 0 });
        setLoading({ label: 'Loading model…', v: 0 });
        const buf = await fetchFile(first.id, progress(files.preview ? 'Loading quick preview' : `Loading model (${fmtBytes(first.size)})`));
        if (token !== loadToken.current) return;
        setLoading({ label: 'Preparing…', v: 1 });
        const root = await c.viewer.parse(buf);
        if (token !== loadToken.current) return;
        c.viewer.setModel(root);
        c.viewer.initTagState(man);
        applyInitialView(c, man);
        rerender();
        if (files.preview && files.full) {
          setLoading({ label: `Loading full detail (${fmtBytes(files.full.size)})`, v: 0 });
          const fb = await fetchFile(files.full.id, progress(`Loading full detail (${fmtBytes(files.full.size)})`));
          if (token !== loadToken.current) return;
          const tags = new Map(c.viewer.tagState);
          const full = await c.viewer.parse(fb);
          if (token !== loadToken.current) return;
          c.viewer.setModel(full, { keepCamera: true });
          c.viewer.tagState = tags;
          c.viewer.applyTags();
          if (c.section.mode !== 'off') c.section.setState(c.section.getState());
          rerender();
        }
        setLoading(null);
      } catch (e: any) {
        if (token === loadToken.current) { setLoading(null); toast('Could not load model: ' + e.message, 6000); }
      }
    })();
  }, [version?.id, !!ctx.current]);

  const applyInitialView = (c: ViewerCtx, man: Manifest | null) => {
    const q = new URLSearchParams(location.search);
    const viewId = q.get('view');
    const fromAnn = viewId ? annotations.find((a) => a.id === +viewId && a.type === 'view') : null;
    const vs = fromAnn?.data ?? detail?.share?.view_state;
    if (vs) { restoreView(vs, false); return; }
    const first = man?.scenes?.find((x) => x.camera);
    if (first) { c.viewer.goToScene(first, false); setActiveScene(first.name); }
  };

  useEffect(() => {
    const c = ctx.current;
    if (!c) return;
    c.tools.setAnnotations(annotations, selected);
    c.tools.onSelect = (aid) => { setSelected(aid as number); setPanel('comments'); };
    c.tools.onCreate = onDraft;
  }, [annotations, selected, ctx.current, canComment]);

  // ---------------------------------------------------------------- annotations
  const saveAnnotation = async (type: Annotation['type'], data: any, body?: string | null, title?: string | null, parent_id?: number | null) => {
    if (!canComment) {
      const local: Annotation = { id: -Date.now(), model_id: id, version_id: versionId, parent_id: parent_id ?? null, user_id: null, author_name: 'You (not saved)',
        type, title: title ?? null, body: body ?? null, data, status: 'open', created_at: '', updated_at: '' };
      setAnnotations((a) => [...a, local]);
      toast('Shown only to you – you do not have permission to save annotations');
      return local;
    }
    let author_name: string | undefined;
    if (!s.user) {
      try { author_name = localStorage.getItem('guest-name') || undefined; } catch { /* ignore */ }
      if (!author_name) {
        author_name = prompt('Your name (shown next to your comments)') || 'Guest';
        try { localStorage.setItem('guest-name', author_name); } catch { /* ignore */ }
      }
    }
    try {
      const r = await post<{ annotation: Annotation }>(`api/models/${id}/annotations`, { type, data, body, title, parent_id, version_id: versionId, author_name });
      setAnnotations((a) => { const n = [...a, r.annotation]; offline.updateAnnotations(id, n); return n; });
      return r.annotation;
    } catch (e: any) { toast(e.message); return null; }
  };

  const updateAnnotation = async (a: Annotation, changes: Partial<Annotation>) => {
    if (a.id < 0) { setAnnotations((l) => l.map((x) => (x.id === a.id ? { ...x, ...changes } : x))); return; }
    const r = await patch<{ annotation: Annotation }>(`api/annotations/${a.id}`, changes);
    setAnnotations((l) => l.map((x) => (x.id === a.id ? r.annotation : x)));
  };

  const deleteAnnotation = async (a: Annotation) => {
    if (a.id > 0) await del(`api/annotations/${a.id}`);
    setAnnotations((l) => l.filter((x) => x.id !== a.id && x.parent_id !== a.id));
  };

  const onDraft = (r: DraftResult) => {
    if (r.type === 'comment') { setComposer({ data: { ...r.data, section: ctx.current?.section.getState() } }); return; }
    saveAnnotation(r.type, r.data);
  };

  // ---------------------------------------------------------------- views
  const getViewState = () => {
    const c = ctx.current!;
    return { camera: c.viewer.getCameraState(), section: c.section.getState(), tags: Object.fromEntries(c.viewer.tagState), renderMode: c.viewer.renderMode };
  };
  const restoreView = (vs: any, animate = true) => {
    const c = ctx.current;
    if (!c || !vs) return;
    if (vs.tags) { for (const [k, on] of Object.entries(vs.tags)) c.viewer.tagState.set(k, on as boolean); c.viewer.applyTags(); }
    if (vs.renderMode) c.viewer.setRenderMode(vs.renderMode);
    if (vs.section) { c.section.setState(vs.section); if (vs.section.mode !== 'off') setMode('section'); }
    if (vs.camera) animate ? c.viewer.animateTo(vs.camera) : c.viewer.setCameraState(vs.camera);
    rerender();
  };
  const flyTo = (a: Annotation) => {
    const d = a.data;
    if (d?.camera) ctx.current?.viewer.animateTo(d.camera);
    if (d?.section) ctx.current?.section.setState(d.section);
    if (a.type === 'view') restoreView(d);
    setSelected(a.id);
  };

  // ---------------------------------------------------------------- modes
  const setMode = (m: Mode) => {
    const c = ctx.current;
    if (!c) return;
    if (m !== 'walk') c.walk.disable();
    const toolFor: Record<Mode, ToolName> = { orbit: 'none', walk: 'none', section: 'none', measure: 'measure', line: 'line', highlight: 'highlight', comment: 'comment' };
    c.tools.setTool(toolFor[m]);
    if (m === 'walk') { c.walk.enable(); if (c.section.mode === 'off') setShowScenes(false); }
    if (m === 'section' && c.section.mode === 'off') c.section.setAxis('y');
    setModeState(m);
  };

  useEffect(() => {
    const k = (e: KeyboardEvent) => {
      if ((e.target as HTMLElement)?.closest?.('input,textarea,select')) return;
      const c = ctx.current;
      if (!c) return;
      if (e.key === 'Escape') { c.tools.cancelDraft(); if (mode !== 'section') setMode('orbit'); setPresenting(false); }
      if (e.key === 'Enter') c.tools.finishDraft();
      if (e.key === 'f' && mode !== 'walk') c.viewer.fit(undefined, true);
    };
    window.addEventListener('keydown', k);
    return () => window.removeEventListener('keydown', k);
  }, [mode]);

  // Presentation: play the SketchUp scenes like a slideshow.
  useEffect(() => {
    if (!presenting || !manifest?.scenes?.length) return;
    const scenes = manifest.scenes.filter((x) => x.camera);
    let i = Math.max(0, scenes.findIndex((x) => x.name === activeScene));
    const go = () => { const sc = scenes[i % scenes.length]; ctx.current?.viewer.goToScene(sc); setActiveScene(sc.name); i++; };
    go();
    const t = setInterval(go, 4500);
    document.documentElement.requestFullscreen?.().catch(() => {});
    return () => { clearInterval(t); if (document.fullscreenElement) document.exitFullscreen().catch(() => {}); };
  }, [presenting]);

  // Version compare (swipe)
  useEffect(() => {
    const c = ctx.current;
    if (!c) return;
    if (!compare) { c.viewer.setCompareModel(null); return; }
    const f = compare.files.find((x) => x.kind === 'full') ?? compare.files.find((x) => x.kind === 'preview');
    if (!f) { toast('That version has no 3D view'); setCompare(null); return; }
    setLoading({ label: `Loading v${compare.version_no} for comparison`, v: 0 });
    fetchFile(f.id, (l, t) => setLoading({ label: `Loading v${compare.version_no}`, v: t ? l / t : 0 }))
      .then((b) => c.viewer.parse(b)).then((root) => { c.viewer.setCompareModel(root); c.viewer.splitX = 0.5; setLoading(null); rerender(); })
      .catch((e) => { setLoading(null); toast(e.message); setCompare(null); });
  }, [compare?.id]);

  // ---------------------------------------------------------------- actions
  const saveOffline = async () => {
    if (!detail || !versionId) return;
    if (saved) {
      if (confirm('Remove this model from the offline library on this device?')) { await offline.remove(id); setSaved(null); toast('Removed from device'); }
      return;
    }
    const skp = version?.files.find((f) => f.kind === 'skp');
    const includeSkp = !!skp && detail.can_download && confirm(`Also keep the original .skp (${fmtBytes(skp.original_size)}) on this device?\nOK = include, Cancel = 3D view only`);
    setSaving(0);
    try {
      const e = await offline.save(detail, versionId, annotations, (fid) => fileUrl(fid), { includeSkp, share: shareToken ? { token: shareToken, key: shareCtx.key } : null }, (d, t) => setSaving(t ? d / t : 0));
      setSaved({ version_id: e.version_id });
      toast(`Saved for offline use (${fmtBytes(e.bytes)})`);
    } catch (e: any) { toast(e.message, 6000); }
    setSaving(null);
  };

  const download = async (kind: 'skp' | 'full') => {
    const f = version?.files.find((x) => x.kind === kind);
    if (!f) return;
    const cached = detail?.offline ? await offline.fileUrl(f.id) : null;
    const a = document.createElement('a');
    a.href = cached ?? fileUrl(f.id, true);
    a.download = f.filename.replace(/\.gz$/, '');
    document.body.appendChild(a); a.click(); a.remove();
  };

  const startAR = async () => {
    const c = ctx.current;
    if (!c || !ar) return;
    const real = confirm('Place the model at real-world scale?\nOK = real scale (walk inside)\nCancel = tabletop size');
    try {
      if (ar === 'quicklook' || isIOS()) { toast('Preparing AR…'); await openQuickLook(c.viewer, detail!.model.name, real ? 'real' : 'table'); }
      else await startWebXR(c.viewer, real ? 'real' : 'table', arOverlay.current!, () => toast('AR closed'));
    } catch (e: any) { toast('AR failed: ' + e.message, 6000); }
  };

  // ---------------------------------------------------------------- render
  if (err) {
    return (
      <div style="min-height:100vh;display:grid;place-items:center;padding:16px">
        <div class="card" style="text-align:center;max-width:420px">
          <h2>{err.status === 401 ? 'Please log in' : err.status === 403 ? 'No access' : 'Cannot open model'}</h2>
          <p class="muted">{err.message}</p>
          {err.status === 401 ? <button class="btn primary" onClick={() => navigate(`/login?next=${encodeURIComponent(location.pathname.replace(/^.*?\/m\//, '/m/'))}`)}>Log in</button>
            : <button class="btn" onClick={() => navigate('/')}>Back</button>}
        </div>
      </div>
    );
  }
  if (!detail) return <div style="min-height:100vh;display:grid;place-items:center" class="muted">Loading…</div>;

  const c = ctx.current;
  const scenes = (manifest?.scenes ?? []).filter((x) => x.camera || x.hidden_tags);
  const tb = (m: Mode, icon: string, tip: string) => (
    <button class={'tbtn' + (mode === m ? ' on' : '')} onClick={() => setMode(mode === m && m !== 'orbit' ? 'orbit' : m)} aria-label={tip} title={tip}><Icon name={icon} size={22} /><span class="tip">{tip}</span></button>
  );
  const pb = (p: PanelName, icon: string, tip: string, badge?: number) => (
    <button class={'tbtn' + (panel === p ? ' on' : '')} onClick={() => setPanel(panel === p ? null : p)} aria-label={tip} title={tip}>
      <Icon name={icon} size={22} /><span class="tip">{tip}</span>
      {!!badge && <span style="position:absolute;top:2px;right:2px;background:#ef4444;color:#fff;border-radius:99px;font-size:10px;padding:0 5px;font-weight:700">{badge}</span>}
    </button>
  );
  const openComments = annotations.filter((a) => a.type === 'comment' && !a.parent_id && a.status === 'open').length;
  const skpFile = version?.files.find((f) => f.kind === 'skp');

  return (
    <div class="vpage" ref={arOverlay}>
      <div class="vtop">
        <button class="btn ghost sm" onClick={() => (shareToken ? null : navigate('/'))} aria-label="Back" disabled={!!shareToken}><Icon name={shareToken ? 'views' : 'back'} /></button>
        <div class="col grow" style="gap:0;min-width:0">
          <div class="title">{detail.model.name}</div>
          <div class="small muted" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{detail.project.name} · v{version?.version_no}{detail.offline ? ' · offline copy' : ''}</div>
        </div>
        {detail.versions.length > 1 && !shareToken && (
          <select class="input hide-sm" style="width:auto;min-height:34px;padding:4px 8px" value={versionId ?? ''} onChange={(e) => { setCompare(null); setVersionId(+e.currentTarget.value); }}>
            {detail.versions.map((v) => <option value={v.id}>v{v.version_no}{v.id === detail.model.current_version_id ? ' (current)' : ''}</option>)}
          </select>
        )}
        {saving !== null ? <span class="small" style="min-width:90px"><Progress value={saving} />Saving {Math.round(saving * 100)}%</span>
          : <button class={'btn sm' + (saved ? ' primary' : '')} onClick={saveOffline} title={saved ? 'Saved on this device – tap to remove' : 'Save for offline use'}><Icon name="offline" size={18} /><span class="hide-sm">{saved ? (saved.version_id === versionId ? 'Offline ✓' : 'Update offline') : 'Save offline'}</span></button>}
        {detail.can_download && skpFile && <button class="btn sm" onClick={() => download('skp')} title={`Download .skp (${fmtBytes(skpFile.original_size)}) – opens in SketchUp Pro`}><Icon name="download" size={18} /><span class="hide-sm">.skp</span></button>}
        {canEdit && <button class="btn sm primary" onClick={() => setShareOpen(true)}><Icon name="share" size={18} /><span class="hide-sm">Share</span></button>}
      </div>

      <div class="vmain">
        <div class="vcanvas" ref={canvasRef}>
          {!version?.has_3d && !loading && (
            <div class="loading"><div class="box" style="text-align:center">
              <h3>No 3D preview for this version</h3>
              <p class="muted small">It was uploaded as a .skp file only. Publish it from SketchUp with the SkpShare plugin to view it here.</p>
              {detail.can_download && skpFile && <button class="btn primary" onClick={() => download('skp')}>Download .skp</button>}
            </div></div>
          )}
          {loading && <div class="loading"><div class="box"><div class="small" style="margin-bottom:6px">{loading.label} {loading.v > 0 && loading.v < 1 ? Math.round(loading.v * 100) + '%' : ''}</div><Progress value={loading.v} /></div></div>}
          {notice && <div class="chip">{notice}</div>}
          {detail.share?.watermark && <div class="watermark">{Array.from({ length: 40 }, () => <span>{detail.share!.watermark}</span>)}</div>}
          {compare && c && <CompareSplit viewer={c.viewer} left={version!} right={compare} onClose={() => setCompare(null)} />}
          {mode === 'walk' && c?.viewer.isMobile && (
            <>
              <Joystick onMove={(x, y) => c.walk.setJoystick(x, y)} />
              <div class="updown">
                <button onPointerDown={() => c.walk.setVertical(1)} onPointerUp={() => c.walk.setVertical(0)} onPointerCancel={() => c.walk.setVertical(0)}>▲</button>
                <button onPointerDown={() => c.walk.setVertical(-1)} onPointerUp={() => c.walk.setVertical(0)} onPointerCancel={() => c.walk.setVertical(0)}>▼</button>
              </div>
            </>
          )}
          {presenting && <button class="btn" style="position:absolute;top:12px;right:12px;z-index:5" onClick={() => setPresenting(false)}>Stop presentation</button>}

          {c && !presenting && <SubBar mode={mode} c={c} manifest={manifest} onMarkup={() => setMarkup(c.viewer.snapshot())} setMode={setMode} rerender={rerender} />}

          {showScenes && scenes.length > 0 && !presenting && mode !== 'walk' && (
            <div class="scenes">
              {scenes.map((sc: SceneDef) => (
                <button class={'scene' + (activeScene === sc.name ? ' on' : '')} onClick={() => { c?.viewer.goToScene(sc); setActiveScene(sc.name); }}>
                  {sc.thumb ? <img src={sc.thumb} alt="" /> : <div style="height:58px;display:grid;place-items:center;background:var(--panel-2)"><Icon name="scenes" /></div>}
                  <span title={sc.name}>{sc.name}</span>
                </button>
              ))}
            </div>
          )}

          {!presenting && (
            <div class="toolrail">
              {tb('orbit', 'orbit', 'Orbit')}
              {tb('walk', 'walk', 'Walk')}
              {tb('section', 'section', 'Section')}
              {tb('measure', 'measure', 'Measure')}
              {tb('line', 'line', 'Draw line')}
              {tb('highlight', 'highlight', 'Highlight')}
              {tb('comment', 'comment', 'Comment pin')}
              <button class="tbtn" onClick={() => c && setMarkup(c.viewer.snapshot())} aria-label="Markup" title="Markup"><Icon name="markup" size={22} /><span class="tip">Markup snapshot</span></button>
              {scenes.length > 0 && <button class={'tbtn' + (showScenes ? ' on' : '')} onClick={() => setShowScenes(!showScenes)} aria-label="Scenes" title="Scenes"><Icon name="scenes" size={22} /><span class="tip">Scenes</span></button>}
              {pb('comments', 'comment', 'Comments & notes', openComments)}
              {pb('tags', 'tags', 'Tags')}
              {pb('views', 'views', 'Saved views')}
              {pb('settings', 'settings', 'Display')}
              {pb('info', 'info', 'Info & versions')}
              {manifest?.bom?.length ? pb('bom', 'bom', 'Components') : null}
              {scenes.length > 1 && <button class="tbtn" onClick={() => setPresenting(true)} aria-label="Present" title="Present"><Icon name="play" size={22} /><span class="tip">Present scenes</span></button>}
              {ar && version?.has_3d && <button class="tbtn" onClick={startAR} aria-label="AR" title="AR"><Icon name="ar" size={22} /><span class="tip">View in AR</span></button>}
              <button class="tbtn" onClick={() => (document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen?.())} aria-label="Fullscreen" title="Fullscreen"><Icon name="fullscreen" size={22} /><span class="tip">Fullscreen</span></button>
            </div>
          )}
        </div>

        {panel && c && (
          <SidePanel name={panel} onClose={() => setPanel(null)} c={c} detail={detail} version={version} manifest={manifest} annotations={annotations}
            selected={selected} setSelected={setSelected} canComment={canComment} canEdit={canEdit} user={s.user} unit={unit}
            onFly={flyTo} onUpdate={updateAnnotation} onDelete={deleteAnnotation} onReply={(parent, body) => saveAnnotation('comment', null, body, null, parent.id)}
            onSaveView={async (name) => { await saveAnnotation('view', getViewState(), null, name); }} onRestoreView={restoreView}
            onScene={(sc) => { c.viewer.goToScene(sc); setActiveScene(sc.name); }}
            onVersion={(vid) => { setCompare(null); setVersionId(vid); }} onCompare={(v) => { setCompare(v); setPanel(null); }}
            onReload={reload} onDownload={download} rerender={rerender} />
        )}
      </div>

      {shareOpen && <ShareDialog modelId={id} versions={detail.versions} getViewState={getViewState} onClose={() => setShareOpen(false)} />}
      {markup && <MarkupEditor image={markup} canSave={canComment || !shareToken} onClose={() => setMarkup(null)}
        onSave={async (img, note) => { await saveAnnotation('markup', { image: img, camera: c?.viewer.getCameraState() }, note || null); setMarkup(null); setPanel('comments'); }} />}
      {composer && <CommentComposer onClose={() => setComposer(null)} onSave={async (text) => {
        const a = await saveAnnotation('comment', composer.data, text);
        setComposer(null);
        if (a) { setSelected(a.id); setPanel('comments'); }
      }} />}
    </div>
  );
}

function CommentComposer({ onSave, onClose }: { onSave: (text: string) => void; onClose: () => void }) {
  const [text, setText] = useState('');
  return (
    <Modal title="New comment" onClose={onClose}>
      <textarea class="input" autoFocus placeholder="Describe the issue or idea…" value={text} onInput={(e) => setText(e.currentTarget.value)} />
      <div class="row" style="justify-content:flex-end;margin-top:10px">
        <button class="btn" onClick={onClose}>Cancel</button>
        <button class="btn primary" disabled={!text.trim()} onClick={() => onSave(text.trim())}>Post</button>
      </div>
    </Modal>
  );
}

function CompareSplit({ viewer, left, right, onClose }: { viewer: Viewer; left: Version; right: Version; onClose: () => void }) {
  const [x, setX] = useState(viewer.splitX);
  const drag = (e: PointerEvent) => {
    const r = viewer.container.getBoundingClientRect();
    const v = Math.min(0.98, Math.max(0.02, (e.clientX - r.left) / r.width));
    viewer.splitX = v;
    setX(v);
    viewer.requestRender();
  };
  return (
    <>
      <div class="compare-split" style={{ left: `${x * 100}%` }}
        onPointerDown={(e) => { (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId); e.stopPropagation(); }}
        onPointerMove={(e) => { if ((e.currentTarget as HTMLElement).hasPointerCapture(e.pointerId)) drag(e); }} />
      <div class="compare-tag" style={{ left: '72px', top: '64px' }}>v{left.version_no}</div>
      <div class="compare-tag" style={{ right: '12px', top: '64px' }}>v{right.version_no}</div>
      <button class="btn sm" style="position:absolute;right:12px;top:100px;z-index:5" onClick={onClose}>Exit compare</button>
    </>
  );
}

function SubBar({ mode, c, manifest, onMarkup, setMode, rerender }: { mode: Mode; c: ViewerCtx; manifest: Manifest | null; onMarkup: () => void; setMode: (m: Mode) => void; rerender: () => void }) {
  const [, force] = useState(0);
  const up = () => { force((x) => x + 1); rerender(); };
  const colors = (
    <>{COLORS.map((col) => <button class={'swatch' + (c.tools.color === col ? ' on' : '')} style={{ background: col }} onClick={() => { c.tools.color = col; up(); }} aria-label={col} />)}</>
  );
  if (mode === 'section') {
    const sec = c.section;
    return (
      <div class="subbar">
        <span class="lbl">Section</span>
        <div class="seg">
          <button class={sec.mode === 'plane' && Math.abs(sec.plane.normal.y) > 0.99 ? 'on' : ''} onClick={() => { sec.setAxis('y'); up(); }}>Plan</button>
          <button class={sec.mode === 'plane' && Math.abs(sec.plane.normal.x) > 0.99 ? 'on' : ''} onClick={() => { sec.setAxis('x'); up(); }}>X</button>
          <button class={sec.mode === 'plane' && Math.abs(sec.plane.normal.z) > 0.99 ? 'on' : ''} onClick={() => { sec.setAxis('z'); up(); }}>Z</button>
          <button class={sec.mode === 'box' ? 'on' : ''} onClick={() => { sec.setBox(); up(); }}>Box</button>
        </div>
        <button class="btn sm" onClick={() => sec.pickFace()}>On surface</button>
        {sec.mode === 'plane' && <>
          <input type="range" min={0} max={1000} value={Math.round(sec.offset * 1000)} onInput={(e) => { sec.offset = +e.currentTarget.value / 1000; up(); }} aria-label="Section position" />
          <button class="btn sm" onClick={() => { sec.flip(); up(); }}>Flip</button>
        </>}
        {!!manifest?.section_planes?.length && (
          <select class="input" style="width:auto;min-height:32px;padding:2px 6px" value="" onChange={(e) => {
            const p = manifest.section_planes![+e.currentTarget.value];
            sec.setPlane(new THREE.Vector3().fromArray(p.normal), new THREE.Vector3().fromArray(p.point)); up();
          }}>
            <option value="">SketchUp sections…</option>
            {manifest.section_planes.map((p, i) => <option value={i}>{p.name || `Section ${i + 1}`}{p.active ? ' (active)' : ''}</option>)}
          </select>
        )}
        <label class="check small"><input type="checkbox" checked={sec.caps} onChange={(e) => { sec.setCaps(e.currentTarget.checked); up(); }} />Fill</label>
        <button class="btn sm" onClick={() => { sec.off(); setMode('orbit'); }}>Off</button>
      </div>
    );
  }
  if (mode === 'measure') {
    const kinds: [MeasureKind, string][] = [['distance', 'Distance'], ['height', 'Height'], ['angle', 'Angle'], ['area', 'Area']];
    const multi = c.tools.measureKind === 'area' || (c.tools.measureKind === 'distance' && c.tools.chainDistance);
    return (
      <div class="subbar">
        <span class="lbl">Measure</span>
        <div class="seg">{kinds.map(([k, l]) => <button class={c.tools.measureKind === k ? 'on' : ''} onClick={() => { c.tools.measureKind = k; c.tools.cancelDraft(); up(); }}>{l}</button>)}</div>
        {c.tools.measureKind === 'distance' && <label class="check small"><input type="checkbox" checked={c.tools.chainDistance} onChange={(e) => { c.tools.chainDistance = e.currentTarget.checked; up(); }} />Chain</label>}
        <select class="input" style="width:auto;min-height:32px;padding:2px 6px" value={c.tools.unit} onChange={(e) => { c.tools.unit = e.currentTarget.value as LengthUnit; up(); }}>
          {['mm', 'cm', 'm', 'in', 'ft'].map((u) => <option>{u}</option>)}
        </select>
        {multi && <button class="btn sm primary" onClick={() => { c.tools.finishDraft(); up(); }} disabled={c.tools.draftCount < (c.tools.measureKind === 'area' ? 3 : 2)}>Done</button>}
        <span class="small muted">{c.viewer.isMobile ? 'Tap points (snaps to corners & edges)' : 'Click points · snaps to vertices (green), midpoints (cyan), edges (red)'}</span>
      </div>
    );
  }
  if (mode === 'line') return <div class="subbar"><span class="lbl">Line</span>{colors}<button class="btn sm primary" onClick={() => { c.tools.finishDraft(); up(); }} disabled={c.tools.draftCount < 2}>Done</button><button class="btn sm" onClick={() => { c.tools.cancelDraft(); up(); }}>Clear</button><span class="small muted">Tap points on the model</span></div>;
  if (mode === 'highlight') return <div class="subbar"><span class="lbl">Highlight</span>{colors}<span class="small muted">Drag over surfaces · switch to Orbit to rotate</span></div>;
  if (mode === 'comment') return <div class="subbar"><span class="lbl">Comment</span><span class="small muted">Tap the model where the comment belongs</span><button class="btn sm" onClick={onMarkup}>Markup snapshot instead</button></div>;
  if (mode === 'walk') {
    const w = c.walk;
    return (
      <div class="subbar">
        <span class="lbl">Walk</span>
        <span class="small muted">{c.viewer.isMobile ? 'Joystick to move · drag to look · double-tap to jump' : 'WASD / arrows · drag to look · Q/E up/down · Shift run · double-click to jump'}</span>
        <label class="small">Speed <input type="range" min={0.2} max={10} step={0.1} value={w.speed} onInput={(e) => { w.speed = +e.currentTarget.value; up(); }} /></label>
        <label class="check small"><input type="checkbox" checked={w.gravity} onChange={(e) => { w.gravity = e.currentTarget.checked; up(); }} />Gravity</label>
        {c.viewer.isMobile && <label class="check small"><input type="checkbox" checked={w.gyro} onChange={async (e) => { const ok = await w.setGyro(e.currentTarget.checked); if (!ok) toast('Motion sensors are not available'); up(); }} />Gyroscope</label>}
      </div>
    );
  }
  return null;
}

export type { RenderMode };
