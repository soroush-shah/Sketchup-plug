// In-app offline library backed by the Cache Storage API.
// Saved models (GLB + manifest + thumbnail + comments, optionally the .skp) open without a network.
import type { Annotation, ModelDetail, FileRec } from './api';

const CACHE = 'skpshare-offline-v1';
const base = () => {
  const b = document.querySelector('base')?.getAttribute('href') || '/';
  return (b.endsWith('/') ? b : b + '/') + '__offline/';
};
const key = (k: string) => new Request(base() + k);

export interface OfflineEntry {
  model_id: number; name: string; project: string; version_id: number; version_no: number;
  bytes: number; saved_at: string; thumb_file_id: number | null; files: number[]; share: { token: string; key: string | null } | null;
}

const supported = () => typeof caches !== 'undefined';

async function readJson<T>(k: string): Promise<T | null> {
  if (!supported()) return null;
  const c = await caches.open(CACHE);
  const r = await c.match(key(k));
  return r ? r.json() : null;
}

async function writeJson(k: string, v: unknown) {
  const c = await caches.open(CACHE);
  await c.put(key(k), new Response(JSON.stringify(v), { headers: { 'Content-Type': 'application/json' } }));
}

export const offline = {
  supported,

  async list(): Promise<OfflineEntry[]> {
    return (await readJson<OfflineEntry[]>('index')) ?? [];
  },

  async entry(modelId: number): Promise<OfflineEntry | null> {
    return (await this.list()).find((e) => e.model_id === modelId) ?? null;
  },

  async getModel(modelId: number): Promise<{ detail: ModelDetail; annotations: Annotation[] } | null> {
    return readJson(`model/${modelId}`);
  },

  async getFile(fileId: number): Promise<ArrayBuffer | null> {
    if (!supported()) return null;
    try {
      const c = await caches.open(CACHE);
      const r = await c.match(key(`file/${fileId}`));
      return r ? r.arrayBuffer() : null;
    } catch {
      return null;
    }
  },

  async fileUrl(fileId: number): Promise<string | null> {
    const b = await this.getFile(fileId);
    return b ? URL.createObjectURL(new Blob([b])) : null;
  },

  /** Download the files of the shown version into the offline cache. */
  async save(detail: ModelDetail, versionId: number, annotations: Annotation[], fileUrl: (id: number) => string,
    opts: { includeSkp: boolean; share: OfflineEntry['share'] }, onProgress: (done: number, total: number) => void): Promise<OfflineEntry> {
    if (!supported()) throw new Error('This browser does not support offline storage');
    try { await navigator.storage?.persist?.(); } catch { /* optional */ }
    const v = detail.versions.find((x) => x.id === versionId)!;
    const wanted: FileRec[] = v.files.filter((f) => ['full', 'preview', 'manifest', 'thumb'].includes(f.kind) || (opts.includeSkp && f.kind === 'skp'));
    const total = wanted.reduce((s, f) => s + (f.gzipped ? f.original_size : f.size), 0);
    let done = 0;
    const c = await caches.open(CACHE);
    for (const f of wanted) {
      if (await c.match(key(`file/${f.id}`))) { done += f.size; onProgress(done, total); continue; }
      const res = await fetch(fileUrl(f.id), { credentials: 'same-origin' });
      if (!res.ok || !res.body) throw new Error(`Download of ${f.kind} failed (HTTP ${res.status})`);
      const reader = res.body.getReader();
      const parts: Uint8Array[] = [];
      for (;;) {
        const { done: end, value } = await reader.read();
        if (end) break;
        parts.push(value);
        done += value.byteLength;
        onProgress(done, total);
      }
      await c.put(key(`file/${f.id}`), new Response(new Blob(parts as BlobPart[], { type: f.mime }), {
        headers: { 'Content-Type': f.mime, 'X-Filename': encodeURIComponent(f.filename) },
      }));
    }
    const pinned: ModelDetail = { ...detail, versions: [{ ...v, files: wanted }] };
    await writeJson(`model/${detail.model.id}`, { detail: pinned, annotations });
    const entry: OfflineEntry = {
      model_id: detail.model.id, name: detail.model.name, project: detail.project.name, version_id: v.id, version_no: v.version_no,
      bytes: total, saved_at: new Date().toISOString(), thumb_file_id: wanted.find((f) => f.kind === 'thumb')?.id ?? null,
      files: wanted.map((f) => f.id), share: opts.share,
    };
    const list = (await this.list()).filter((e) => e.model_id !== entry.model_id);
    // Drop files of a previously saved version that are no longer referenced.
    const old = (await this.list()).find((e) => e.model_id === entry.model_id);
    if (old) for (const id of old.files) if (!entry.files.includes(id)) await c.delete(key(`file/${id}`));
    await writeJson('index', [entry, ...list]);
    return entry;
  },

  async updateAnnotations(modelId: number, annotations: Annotation[]) {
    const m = await this.getModel(modelId);
    if (m) await writeJson(`model/${modelId}`, { ...m, annotations });
  },

  async remove(modelId: number) {
    const c = await caches.open(CACHE);
    const list = await this.list();
    const e = list.find((x) => x.model_id === modelId);
    if (e) for (const id of e.files) await c.delete(key(`file/${id}`));
    await c.delete(key(`model/${modelId}`));
    await writeJson('index', list.filter((x) => x.model_id !== modelId));
  },

  async clear() {
    if (supported()) await caches.delete(CACHE);
  },

  async usage(): Promise<{ usage: number; quota: number; persisted: boolean }> {
    const est = (await navigator.storage?.estimate?.()) ?? {};
    const persisted = (await navigator.storage?.persisted?.()) ?? false;
    return { usage: est.usage ?? 0, quota: est.quota ?? 0, persisted };
  },
};
