import { useEffect, useState } from 'preact/hooks';
import { fmtBytes, fmtDate } from '../lib/api';
import { offline, type OfflineEntry } from '../lib/offline';
import { navigate, toast, useStore } from '../lib/store';
import { Empty, TopBar } from './common';
import { Icon } from './icons';

function Thumb({ id }: { id: number | null }) {
  const [src, setSrc] = useState<string | null>(null);
  useEffect(() => {
    let u: string | null = null;
    if (id) offline.fileUrl(id).then((x) => { u = x; setSrc(x); });
    return () => { if (u) URL.revokeObjectURL(u); };
  }, [id]);
  return src ? <img src={src} alt="" /> : <Icon name="views" size={32} />;
}

export function OfflinePage() {
  const s = useStore();
  const [list, setList] = useState<OfflineEntry[]>([]);
  const [usage, setUsage] = useState({ usage: 0, quota: 0, persisted: false });
  const load = async () => { setList(await offline.list()); setUsage(await offline.usage()); };
  useEffect(() => { load(); }, []);

  const open = (e: OfflineEntry) => navigate(e.share ? `/s/${e.share.token}` : `/m/${e.model_id}`);

  return (
    <>
      <TopBar />
      <main class="page">
        <div class="toolbar-line">
          <h1 class="grow" style="margin:0">Offline library</h1>
          {list.length > 0 && <button class="btn danger" onClick={async () => { if (confirm('Delete all offline models from this device?')) { await offline.clear(); load(); toast('Offline library cleared'); } }}><Icon name="trash" size={16} />Delete all</button>}
        </div>
        <div class="card" style="margin-bottom:16px">
          <div class="row"><b>Storage on this device</b><span class="grow" /><span class="muted">{fmtBytes(usage.usage)} used{usage.quota ? ` of ${fmtBytes(usage.quota)} available` : ''}</span></div>
          <div class="gauge" style="margin-top:8px"><div style={{ width: `${usage.quota ? Math.min(100, (usage.usage / usage.quota) * 100) : 0}%` }} /></div>
          <p class="small muted" style="margin-bottom:0">
            {usage.persisted ? '✔ Storage is persistent – the browser will not clear these files automatically.' : 'Tip: install this app to your home screen so the browser keeps offline files longer.'}
            {!offline.supported() && <b class="bad"> This browser does not support offline storage.</b>}
          </p>
        </div>
        {!list.length ? (
          <Empty>No models saved for offline use yet.<br />Open a model and tap <b>Save offline</b>.</Empty>
        ) : (
          <div class="grid">
            {list.map((e) => (
              <div class="mcard" key={e.model_id}>
                <button class="thumb" style="border:0;cursor:pointer;padding:0" onClick={() => open(e)}><Thumb id={e.thumb_file_id} /></button>
                <div class="body">
                  <div class="name">{e.name}</div>
                  <div class="small muted">{e.project} · v{e.version_no} · {fmtBytes(e.bytes)}</div>
                  <div class="small muted">Saved {fmtDate(e.saved_at.replace('T', ' ').slice(0, 19))}</div>
                  <div class="row" style="margin-top:6px">
                    <button class="btn sm primary grow" onClick={() => open(e)}>Open</button>
                    <button class="btn sm danger" title="Remove from this device" onClick={async () => { await offline.remove(e.model_id); load(); toast('Removed from device'); }}><Icon name="trash" size={16} /></button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
        {!s.online && <p class="muted small" style="margin-top:16px">You are offline. Models listed here open without internet.</p>}
      </main>
    </>
  );
}
