import { useEffect, useState } from 'preact/hooks';
import { ApiError, get, post, shareCtx } from '../lib/api';
import { offline } from '../lib/offline';
import { href } from '../lib/store';
import { ModelPage } from './ModelPage';

/** Public share link: optional password, then the viewer with the link's permissions. */
export function ShareGate({ token }: { token: string }) {
  const keyName = `share-key:${token}`;
  const [state, setState] = useState<'loading' | 'password' | 'ready' | 'error'>('loading');
  const [modelId, setModelId] = useState(0);
  const [err, setErr] = useState('');
  const [label, setLabel] = useState<string | null>(null);
  const [pw, setPw] = useState('');

  const tryOpen = async () => {
    shareCtx.token = token;
    try { shareCtx.key = sessionStorage.getItem(keyName); } catch { shareCtx.key = null; }
    try {
      const r = await get<{ model_id: number }>(`api/share/${token}`);
      setModelId(r.model_id);
      setState('ready');
    } catch (e) {
      const ae = e as ApiError;
      if (ae.status === 401 && ae.data.password_required) { setLabel(ae.data.label ?? null); setState('password'); return; }
      if (ae.status === 0) {
        // offline: open a copy saved from this link
        const saved = (await offline.list()).find((x) => x.share?.token === token);
        if (saved) { shareCtx.key = saved.share!.key; setModelId(saved.model_id); setState('ready'); return; }
      }
      setErr(ae.message);
      setState('error');
    }
  };

  useEffect(() => { tryOpen(); return () => { shareCtx.token = null; shareCtx.key = null; }; }, [token]);

  if (state === 'ready') return <ModelPage id={modelId} shareToken={token} />;
  return (
    <div style="min-height:100vh;display:grid;place-items:center;padding:16px">
      <div class="card" style="width:min(380px,100%);padding:26px;text-align:center">
        <img src={href('icons/icon.svg')} width={44} height={44} alt="" />
        {state === 'loading' && <p class="muted">Opening shared model…</p>}
        {state === 'error' && <><h2>Link unavailable</h2><p class="muted">{err}</p></>}
        {state === 'password' && (
          <form onSubmit={async (e) => {
            e.preventDefault();
            setErr('');
            try {
              const r = await post<{ key: string }>(`api/share/${token}/unlock`, { password: pw });
              try { sessionStorage.setItem(keyName, r.key); } catch { /* private mode */ }
              shareCtx.key = r.key;
              tryOpen();
            } catch (ex: any) { setErr(ex.message); }
          }}>
            <h2>{label || 'Protected model'}</h2>
            <p class="muted">Enter the password you received with this link.</p>
            {err && <div class="error">{err}</div>}
            <input class="input" type="password" autoFocus value={pw} onInput={(e) => setPw(e.currentTarget.value)} style="margin-top:10px" />
            <button class="btn primary" style="width:100%;margin-top:12px">Open</button>
          </form>
        )}
      </div>
    </div>
  );
}
