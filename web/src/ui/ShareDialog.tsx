import { useEffect, useState } from 'preact/hooks';
import qrcode from 'qrcode-generator';
import { del, fmtDate, get, patch, post, type ShareLink, type Version } from '../lib/api';
import { href, toast } from '../lib/store';
import { Modal } from './common';
import { Icon } from './icons';

export const shareUrl = (token: string) => location.origin + href(`s/${token}`);

export function QR({ text, size = 180 }: { text: string; size?: number }) {
  const qr = qrcode(0, 'M');
  qr.addData(text);
  qr.make();
  const svg = qr.createSvgTag({ cellSize: 4, margin: 2, scalable: true });
  return <div style={{ width: size, height: size, background: '#fff', borderRadius: 8, padding: 4 }} dangerouslySetInnerHTML={{ __html: svg }} />;
}

export function ShareDialog({ modelId, versions, getViewState, onClose }: { modelId: number; versions: Version[]; getViewState: () => any; onClose: () => void }) {
  const [links, setLinks] = useState<ShareLink[]>([]);
  const [form, setForm] = useState({ label: '', password: '', expires: '', allow_download: false, allow_comments: true, watermark: '', pin_version: false, with_view: false });
  const [qrFor, setQrFor] = useState<string | null>(null);
  const load = () => get<{ shares: ShareLink[] }>(`api/models/${modelId}/shares`).then((r) => setLinks(r.shares));
  useEffect(() => { load(); }, []);

  const create = async (e: Event) => {
    e.preventDefault();
    const r = await post<{ share: ShareLink }>(`api/models/${modelId}/shares`, {
      label: form.label || null, password: form.password || null, expires_at: form.expires || null,
      allow_download: form.allow_download, allow_comments: form.allow_comments, watermark: form.watermark || null,
      version_id: form.pin_version ? versions[0]?.id : null, view_state: form.with_view ? getViewState() : null,
    });
    await navigator.clipboard?.writeText(shareUrl(r.share.token)).catch(() => {});
    toast('Link created and copied');
    setQrFor(r.share.token);
    setForm({ ...form, label: '', password: '' });
    load();
  };

  const copy = (t: string) => { navigator.clipboard?.writeText(shareUrl(t)); toast('Link copied'); };
  const nativeShare = (t: string) => (navigator as any).share?.({ title: 'SketchUp model', url: shareUrl(t) }).catch(() => {});

  return (
    <Modal title="Share" onClose={onClose} wide>
      <form onSubmit={create} class="card" style="background:var(--panel-2)">
        <h3>New link</h3>
        <div class="row">
          <input class="input grow" placeholder="Label (e.g. Client review)" value={form.label} onInput={(e) => setForm({ ...form, label: e.currentTarget.value })} />
          <input class="input grow" type="password" placeholder="Password (optional)" autoComplete="new-password" value={form.password} onInput={(e) => setForm({ ...form, password: e.currentTarget.value })} />
        </div>
        <div class="row" style="margin-top:8px">
          <label class="small muted">Expires</label>
          <input class="input" style="max-width:200px" type="date" value={form.expires} onInput={(e) => setForm({ ...form, expires: e.currentTarget.value })} />
          <input class="input grow" placeholder="Watermark text (optional)" value={form.watermark} onInput={(e) => setForm({ ...form, watermark: e.currentTarget.value })} />
        </div>
        <div class="row" style="margin-top:6px;gap:16px">
          <label class="check"><input type="checkbox" checked={form.allow_download} onChange={(e) => setForm({ ...form, allow_download: e.currentTarget.checked })} />Allow .skp download</label>
          <label class="check"><input type="checkbox" checked={form.allow_comments} onChange={(e) => setForm({ ...form, allow_comments: e.currentTarget.checked })} />Allow comments &amp; markup</label>
          <label class="check"><input type="checkbox" checked={form.pin_version} onChange={(e) => setForm({ ...form, pin_version: e.currentTarget.checked })} />Pin to v{versions[0]?.version_no} (else always latest)</label>
          <label class="check"><input type="checkbox" checked={form.with_view} onChange={(e) => setForm({ ...form, with_view: e.currentTarget.checked })} />Open at current view &amp; section</label>
        </div>
        <button class="btn primary" style="margin-top:8px"><Icon name="share" size={16} />Create link</button>
      </form>

      {qrFor && (
        <div class="row" style="margin:14px 0;gap:16px;align-items:flex-start">
          <QR text={shareUrl(qrFor)} />
          <div class="col grow">
            <b>Scan to open on a phone or tablet</b>
            <code style="word-break:break-all" class="small">{shareUrl(qrFor)}</code>
            <div class="row"><button class="btn sm" onClick={() => copy(qrFor)}>Copy link</button>{'share' in navigator && <button class="btn sm" onClick={() => nativeShare(qrFor)}>Share…</button>}</div>
          </div>
        </div>
      )}

      <h3 style="margin-top:16px">Links</h3>
      <div class="table-wrap">
        <table class="t">
          <thead><tr><th>Link</th><th>Options</th><th>Views</th><th></th></tr></thead>
          <tbody>
            {links.map((l) => (
              <tr key={l.id} style={l.revoked || l.expired ? 'opacity:.5' : ''}>
                <td><b>{l.label || 'Untitled link'}</b><div class="small muted">{fmtDate(l.created_at)}{l.expires_at && ` · expires ${fmtDate(l.expires_at)}`}</div></td>
                <td class="small">
                  {l.has_password && <span class="pill">password</span>} {l.allow_download && <span class="pill">download</span>} {l.allow_comments && <span class="pill">comments</span>}
                  {l.watermark && <span class="pill">watermark</span>} {l.version_id && <span class="pill">pinned</span>} {l.revoked && <span class="pill bad">revoked</span>} {l.expired && <span class="pill bad">expired</span>}
                </td>
                <td>{l.views}</td>
                <td class="row" style="flex-wrap:nowrap">
                  <button class="btn sm" onClick={() => copy(l.token)}>Copy</button>
                  <button class="btn sm" title="QR code" onClick={() => setQrFor(l.token)}><Icon name="qr" size={16} /></button>
                  <button class="btn sm" onClick={async () => { await patch(`api/shares/${l.id}`, { revoked: !l.revoked }); load(); }}>{l.revoked ? 'Enable' : 'Revoke'}</button>
                  <button class="btn sm danger" onClick={async () => { if (confirm('Delete link?')) { await del(`api/shares/${l.id}`); load(); } }}><Icon name="trash" size={16} /></button>
                </td>
              </tr>
            ))}
            {!links.length && <tr><td colSpan={4} class="muted">No links yet</td></tr>}
          </tbody>
        </table>
      </div>
    </Modal>
  );
}
