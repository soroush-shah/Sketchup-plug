import { useEffect, useState } from 'preact/hooks';
import { del, get, post, fmtDate } from '../lib/api';
import { href, toast, useStore } from '../lib/store';
import { TopBar } from './common';
import { Icon } from './icons';

interface Token { id: number; name: string; prefix: string; revoked: number; last_used_at: string | null; created_at: string }

export function Account() {
  const s = useStore();
  const [tokens, setTokens] = useState<Token[]>([]);
  const [newToken, setNewToken] = useState<string | null>(null);
  const [name, setName] = useState('My SketchUp');
  const [pw, setPw] = useState({ current: '', password: '' });
  const load = () => get<{ tokens: Token[] }>('api/me/tokens').then((r) => setTokens(r.tokens));
  useEffect(() => { load(); }, []);
  const canUpload = s.user?.role !== 'viewer';

  return (
    <>
      <TopBar />
      <main class="page" style="max-width:820px">
        <h1>Account</h1>
        <p class="muted">{s.user?.name} · {s.user?.email} · <span class="pill">{s.user?.role}</span></p>

        {canUpload && (
          <section class="card" style="margin:16px 0">
            <h2>SketchUp plugin</h2>
            <ol class="muted" style="padding-left:18px;line-height:1.7">
              <li><a href={href('downloads/skpshare.rbz')} download>Download the plugin (.rbz)</a></li>
              <li>In SketchUp: <b>Extensions → Extension Manager → Install Extension</b> and pick the .rbz file.</li>
              <li>Create a token below and paste it, with this site's address (<code>{location.origin + href('')}</code>), into <b>Extensions → SkpShare → Publish</b> → Settings.</li>
            </ol>
            <h3 style="margin-top:16px">Plugin tokens</h3>
            {newToken && (
              <div class="card" style="background:var(--panel-2);margin-bottom:12px">
                <b>Copy this token now – it will not be shown again:</b>
                <div class="row" style="margin-top:8px"><input class="input grow" readOnly value={newToken} onFocus={(e) => e.currentTarget.select()} />
                  <button class="btn" onClick={() => { navigator.clipboard?.writeText(newToken); toast('Copied'); }}>Copy</button></div>
              </div>
            )}
            <form class="row" onSubmit={async (e) => { e.preventDefault(); const r = await post<{ token: string }>('api/me/tokens', { name }); setNewToken(r.token); load(); }}>
              <input class="input grow" value={name} onInput={(e) => setName(e.currentTarget.value)} placeholder="Token name (e.g. Office PC)" />
              <button class="btn primary"><Icon name="plus" size={16} />Create token</button>
            </form>
            <div class="table-wrap" style="margin-top:10px">
              <table class="t">
                <thead><tr><th>Name</th><th>Token</th><th>Last used</th><th></th></tr></thead>
                <tbody>
                  {tokens.map((t) => (
                    <tr key={t.id}>
                      <td>{t.name}</td><td><code>{t.prefix}…</code></td><td>{fmtDate(t.last_used_at)}</td>
                      <td>{t.revoked ? <span class="pill bad">revoked</span> : <button class="btn sm danger" onClick={async () => { if (confirm('Revoke this token?')) { await del(`api/me/tokens/${t.id}`); load(); } }}>Revoke</button>}</td>
                    </tr>
                  ))}
                  {!tokens.length && <tr><td colSpan={4} class="muted">No tokens yet</td></tr>}
                </tbody>
              </table>
            </div>
          </section>
        )}

        <section class="card" style="margin:16px 0">
          <h2>Change password</h2>
          <form onSubmit={async (e) => {
            e.preventDefault();
            try { await post('api/me/password', pw); toast('Password changed'); setPw({ current: '', password: '' }); } catch (err: any) { toast(err.message); }
          }}>
            <label class="f">Current password</label>
            <input class="input" type="password" autoComplete="current-password" value={pw.current} onInput={(e) => setPw({ ...pw, current: e.currentTarget.value })} />
            <label class="f">New password (min 8)</label>
            <input class="input" type="password" autoComplete="new-password" minLength={8} value={pw.password} onInput={(e) => setPw({ ...pw, password: e.currentTarget.value })} />
            <button class="btn primary" style="margin-top:12px">Update password</button>
          </form>
        </section>

        <section class="card">
          <h2>Appearance</h2>
          <div class="seg">
            {(['auto', 'light', 'dark'] as const).map((t) => (
              <button class={(localStorage.getItem('theme') || 'auto') === t ? 'on' : ''} onClick={() => {
                try { t === 'auto' ? localStorage.removeItem('theme') : localStorage.setItem('theme', t); } catch { /* private mode */ }
                applyTheme(); toast('Theme: ' + t);
              }}>{t}</button>
            ))}
          </div>
        </section>
      </main>
    </>
  );
}

export function applyTheme() {
  let t: string | null = null;
  try { t = localStorage.getItem('theme'); } catch { /* ignore */ }
  if (t) document.documentElement.dataset.theme = t; else delete document.documentElement.dataset.theme;
}
applyTheme();
