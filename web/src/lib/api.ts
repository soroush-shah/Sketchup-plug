// API client for the PHP backend. Handles CSRF, share-link credentials and offline fallbacks.
import { offline } from './offline';

export type Role = 'admin' | 'editor' | 'viewer';
export interface User { id: number; email: string; name: string; role: Role; active: number; created_at: string; last_login_at: string | null; permissions?: number }
export interface FileRec { id: number; kind: 'skp' | 'full' | 'preview' | 'manifest' | 'thumb' | 'attachment'; filename: string; size: number; original_size: number; sha256: string; mime: string; gzipped: boolean; created_at: string }
export interface Version {
  id: number; model_id: number; version_no: number; note: string | null; status: string; has_3d: boolean; source: string;
  approval_status: 'pending' | 'approved' | 'changes_requested'; approval_note: string | null; approved_at: string | null; approved_by_name: string | null;
  stats: Record<string, number> | null; created_at: string; created_by_name: string | null; files: FileRec[];
}
export interface ModelSummary {
  id: number; project_id: number; name: string; description: string | null; created_at: string; updated_at: string;
  current_version_id: number | null; version_no: number | null; has_3d: boolean; approval_status: string | null;
  thumb_file_id: number | null; stored_size: number; skp_size: number; view_size: number; open_comments: number;
}
export interface Project { id: number; name: string; description: string | null; created_at: string; role: string | null; models: ModelSummary[] }
export interface ShareLink {
  id: number; token: string; label: string | null; allow_download: boolean; allow_comments: boolean; watermark: string | null;
  view_state: any; expires_at: string | null; version_id: number | null; model_id: number; has_password: boolean; views: number;
  revoked: boolean; created_at: string; model_name: string; expired: boolean;
}
export interface ModelDetail {
  model: ModelSummary; project: { id: number; name: string }; versions: Version[]; role: 'viewer' | 'commenter' | 'editor';
  can_download: boolean; share: null | { token: string; label: string | null; allow_download: boolean; allow_comments: boolean; watermark: string | null; view_state: any; version_id: number | null };
}
export interface Annotation {
  id: number; model_id: number; version_id: number | null; parent_id: number | null; user_id: number | null; author_name: string;
  type: 'measure' | 'line' | 'highlight' | 'note' | 'comment' | 'markup' | 'view' | 'section'; title: string | null; body: string | null;
  data: any; status: 'open' | 'resolved'; created_at: string; updated_at: string;
}

export class ApiError extends Error {
  constructor(public status: number, message: string, public data: any = {}) { super(message); }
}

let csrf: string | null = null;
/** Active share credentials (set when viewing through a share link). */
export const shareCtx: { token: string | null; key: string | null } = { token: null, key: null };

export const basePath = (() => {
  const b = document.querySelector('base')?.getAttribute('href') || '/';
  return b.endsWith('/') ? b : b + '/';
})();

export function url(path: string, query: Record<string, string | number | undefined | null> = {}): string {
  const q = new URLSearchParams();
  if (shareCtx.token) { q.set('share', shareCtx.token); if (shareCtx.key) q.set('k', shareCtx.key); }
  for (const [k, v] of Object.entries(query)) if (v !== undefined && v !== null) q.set(k, String(v));
  const s = q.toString();
  return basePath + path.replace(/^\//, '') + (s ? '?' + s : '');
}

export const fileUrl = (id: number, download = false) => url(`api/files/${id}`, download ? { download: 1 } : {});

export async function api<T = any>(method: string, path: string, body?: unknown): Promise<T> {
  const headers: Record<string, string> = { Accept: 'application/json' };
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (csrf && method !== 'GET') headers['X-CSRF-Token'] = csrf;
  // Some shared hosts (ModSecurity) block PUT/PATCH/DELETE: tunnel them through POST.
  let wire = method;
  if (method !== 'GET' && method !== 'POST') { headers['X-HTTP-Method-Override'] = method; wire = 'POST'; }
  let res: Response;
  try {
    res = await fetch(url(path), { method: wire, headers, credentials: 'same-origin', body: body === undefined ? undefined : JSON.stringify(body) });
  } catch (e) {
    throw new ApiError(0, 'You are offline or the server cannot be reached');
  }
  const text = await res.text();
  let data: any = {};
  try { data = text ? JSON.parse(text) : {}; } catch { data = { error: `Unexpected response (HTTP ${res.status})` }; }
  if (!res.ok) throw new ApiError(res.status, data.error || `HTTP ${res.status}`, data);
  if (data.csrf) csrf = data.csrf;
  return data as T;
}

export const get = <T = any>(p: string) => api<T>('GET', p);
export const post = <T = any>(p: string, b?: unknown) => api<T>('POST', p, b ?? {});
export const patch = <T = any>(p: string, b?: unknown) => api<T>('PATCH', p, b ?? {});
export const del = <T = any>(p: string) => api<T>('DELETE', p);

/** Model detail with offline fallback (saved models open without network). */
export async function loadModel(id: number): Promise<ModelDetail & { offline?: boolean }> {
  try {
    return await get<ModelDetail>(`api/models/${id}`);
  } catch (e) {
    const saved = await offline.getModel(id);
    if (saved && (e as ApiError).status === 0) return { ...saved.detail, offline: true };
    throw e;
  }
}

export async function loadAnnotations(modelId: number): Promise<Annotation[]> {
  try {
    return (await get<{ annotations: Annotation[] }>(`api/models/${modelId}/annotations`)).annotations;
  } catch (e) {
    const saved = await offline.getModel(modelId);
    if (saved) return saved.annotations;
    throw e;
  }
}

/** Fetch a stored file as ArrayBuffer with progress; served from the offline cache when available. */
export async function fetchFile(id: number, onProgress?: (loaded: number, total: number) => void, signal?: AbortSignal): Promise<ArrayBuffer> {
  const cached = await offline.getFile(id);
  if (cached) { onProgress?.(cached.byteLength, cached.byteLength); return cached; }
  const res = await fetch(fileUrl(id), { credentials: 'same-origin', signal });
  if (!res.ok) throw new ApiError(res.status, `Download failed (HTTP ${res.status})`);
  const total = Number(res.headers.get('Content-Length')) || 0;
  if (!res.body || !onProgress) return res.arrayBuffer();
  const reader = res.body.getReader();
  const parts: Uint8Array[] = [];
  let loaded = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    parts.push(value);
    loaded += value.byteLength;
    onProgress(loaded, total);
  }
  const out = new Uint8Array(loaded);
  let o = 0;
  for (const p of parts) { out.set(p, o); o += p.byteLength; }
  return out.buffer;
}

// ---------------------------------------------------------------- chunked upload (web)

export async function uploadFile(versionId: number, kind: FileRec['kind'], file: Blob, filename: string,
  onProgress?: (sent: number, total: number) => void): Promise<void> {
  const sha = await sha256(file);
  const sess = await post<{ id: string; chunk_size: number; total_chunks: number; received: number[] }>('api/uploads',
    { version_id: versionId, kind, filename, size: file.size, sha256: sha, gzipped: false });
  const done = new Set(sess.received);
  let sent = done.size * sess.chunk_size;
  const queue = Array.from({ length: sess.total_chunks }, (_, i) => i).filter((i) => !done.has(i));
  const worker = async () => {
    while (queue.length) {
      const n = queue.shift()!;
      const blob = file.slice(n * sess.chunk_size, (n + 1) * sess.chunk_size);
      for (let attempt = 0; ; attempt++) {
        try {
          const res = await fetch(url(`api/uploads/${sess.id}/chunks/${n}`), {
            method: 'POST', credentials: 'same-origin', body: blob,
            headers: { 'X-CSRF-Token': csrf || '', 'Content-Type': 'application/octet-stream' },
          });
          if (!res.ok) throw new ApiError(res.status, (await res.json().catch(() => ({}))).error || `HTTP ${res.status}`);
          break;
        } catch (e) {
          if (attempt >= 4 || ((e as ApiError).status >= 400 && (e as ApiError).status < 500)) throw e;
          await new Promise((r) => setTimeout(r, 1000 * 2 ** attempt));
        }
      }
      sent = Math.min(file.size, sent + blob.size);
      onProgress?.(sent, file.size);
    }
  };
  await Promise.all([worker(), worker(), worker()]); // 3 parallel chunks
  await post(`api/uploads/${sess.id}/complete`);
}

async function sha256(file: Blob): Promise<string | null> {
  // Hashing a multi-GB file in the browser is memory-hungry; skip above 512 MB (chunks are still checked).
  if (file.size > 512 * 1024 * 1024 || !crypto.subtle) return null;
  const buf = await crypto.subtle.digest('SHA-256', await file.arrayBuffer());
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

export function fmtBytes(b: number | null | undefined): string {
  if (!b) return '0 B';
  const e = Math.min(4, Math.floor(Math.log(b) / Math.log(1024)));
  return (b / 1024 ** e).toFixed(e ? 1 : 0) + ' ' + ['B', 'KB', 'MB', 'GB', 'TB'][e];
}

export function fmtDate(s: string | null | undefined): string {
  if (!s) return '–';
  const d = new Date(s.replace(' ', 'T') + 'Z');
  return d.toLocaleString(undefined, { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}
