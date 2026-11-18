import { useEffect, useState } from 'preact/hooks';
import { del, fmtBytes, fmtDate, get, patch, post, type Project, type ShareLink, type User } from '../lib/api';
import { toast, useStore } from '../lib/store';
import { Link, Modal, TopBar } from './common';
import { Icon } from './icons';
import { shareUrl } from './ShareDialog';

type Tab = 'overview' | 'users' | 'access' | 'shares' | 'tokens' | 'activity';

export function Admin() {
  const [tab, setTab] = useState<Tab>(() => (new URLSearchParams(location.search).get('tab') as Tab) || 'overview');
  const go = (t: Tab) => { setTab(t); history.replaceState(null, '', `?tab=${t}`); };
  const tabs: [Tab, string][] = [['overview', 'Overview'], ['users', 'Users'], ['access', 'Access'], ['shares', 'Share links'], ['tokens', 'Plugin tokens'], ['activity', 'Activity']];
  return (
    <>
      <TopBar />
      <main class="page">
        <h1>Admin</h1>
        <div class="tabs">{tabs.map(([t, l]) => <button class={tab === t ? 'on' : ''} onClick={() => go(t)}>{l}</button>)}</div>
        {tab === 'overview' && <Overview />}
        {tab === 'users' && <Users />}
        {tab === 'access' && <Access />}
        {tab === 'shares' && <Shares />}
        {tab === 'tokens' && <Tokens />}
        {tab === 'activity' && <Activity />}
      </main>
    </>
  );
}

function Overview() {
  const [s, setS] = useState<any>(null);
  const load = () => get('api/admin/stats').then(setS);
  useEffect(() => { load(); }, []);
  if (!s) return <p class="muted">Loading…</p>;
  const cap = s.storage_quota || (s.disk_free ? s.storage_used + s.disk_free : 0);
  const stat = (v: any, l: string) => <div class="card stat"><div class="v">{v}</div><div class="l">{l}</div></div>;
  const kind: Record<string, string> = { skp: 'Original .skp', full: '3D view', preview: 'Previews', manifest: 'Manifests', thumb: 'Thumbnails', attachment: 'Attachments' };
  return (
    <>
      <div class="stats">
        {stat(s.models, 'Models')}{stat(s.projects, 'Projects')}{stat(s.versions, 'Versions')}{stat(s.users, 'Users')}
        {stat(s.shares, 'Active share links')}{stat(s.share_views, 'Share link views')}{stat(s.open_comments, 'Open comments')}{stat(fmtBytes(s.storage_used), 'Storage used')}
      </div>
      <div class="card" style="margin-bottom:16px">
        <div class="row"><b>Storage</b><span class="grow" /><span class="muted">{fmtBytes(s.storage_used)}{cap ? ` of ${fmtBytes(cap)}` : ''}{s.disk_free != null && ` · ${fmtBytes(s.disk_free)} free on disk`}</span></div>
        {cap > 0 && <div class="gauge" style="margin-top:8px"><div style={{ width: `${Math.min(100, (s.storage_used / cap) * 100)}%` }} /></div>}
        <table class="t small" style="margin-top:10px">
          <thead><tr><th>Type</th><th>Files</th><th>Stored</th><th>Original</th></tr></thead>
          <tbody>{s.by_kind.map((k: any) => <tr><td>{kind[k.kind] ?? k.kind}</td><td>{k.n}</td><td>{fmtBytes(+k.size)}</td><td>{fmtBytes(+k.original_size)}</td></tr>)}</tbody>
        </table>
        <div class="row" style="margin-top:10px">
          <span class="small muted grow">Unfinished uploads: {fmtBytes(s.storage_tmp)}</span>
          <button class="btn sm" onClick={async () => { const r = await post('api/admin/cleanup'); toast(`Removed ${r.removed_uploads} uploads, ${r.removed_versions} broken versions`); load(); }}>Clean up</button>
        </div>
      </div>
      <div class="card">
        <b>Largest models</b>
        <table class="t small"><tbody>{s.biggest_models.map((m: any) => <tr><td><Link to={`/m/${m.id}`}>{m.name}</Link></td><td>{fmtBytes(+m.size)}</td></tr>)}</tbody></table>
      </div>
    </>
  );
}

function Users() {
  const me = useStore().user!;
  const [users, setUsers] = useState<User[]>([]);
  const [form, setForm] = useState<{ name: string; email: string; role: string; password: string } | null>(null);
  const [created, setCreated] = useState<{ email: string; password: string } | null>(null);
  const load = () => get<{ users: User[] }>('api/admin/users').then((r) => setUsers(r.users));
  useEffect(() => { load(); }, []);
  const roleHelp = { admin: 'Everything, incl. users & settings', editor: 'Upload, create projects, share', viewer: 'Only sees what is granted' };

  return (
    <>
      <div class="row" style="margin-bottom:12px"><span class="muted grow">Global roles: admin – full control; editor – can publish from SketchUp and share; viewer – can only open what you grant in “Access”.</span>
        <button class="btn primary" onClick={() => setForm({ name: '', email: '', role: 'viewer', password: '' })}><Icon name="plus" size={16} />New user</button></div>
      {created && (
        <div class="card" style="margin-bottom:12px;background:var(--panel-2)">
          <b>Send these credentials to the user</b> (password shown once):
          <div class="row" style="margin-top:6px"><code class="grow">{created.email} / {created.password}</code>
            <button class="btn sm" onClick={() => { navigator.clipboard?.writeText(`${location.origin}\nEmail: ${created.email}\nPassword: ${created.password}`); toast('Copied'); }}>Copy</button>
            <button class="btn sm ghost" onClick={() => setCreated(null)}><Icon name="close" size={14} /></button></div>
        </div>
      )}
      <div class="table-wrap">
        <table class="t">
          <thead><tr><th>Name</th><th>Role</th><th>Access</th><th>Last login</th><th></th></tr></thead>
          <tbody>
            {users.map((u) => (
              <tr key={u.id} style={u.active ? '' : 'opacity:.5'}>
                <td><b>{u.name}</b><div class="small muted">{u.email}</div></td>
                <td>
                  <select class="input" style="width:auto;min-height:32px;padding:2px 6px" value={u.role} disabled={u.id === me.id}
                    onChange={async (e) => { await patch(`api/admin/users/${u.id}`, { role: e.currentTarget.value }); load(); }}>
                    <option value="admin">admin</option><option value="editor">editor</option><option value="viewer">viewer</option>
                  </select>
                </td>
                <td>{u.role === 'admin' ? <span class="muted small">all</span> : <span class="small">{u.permissions} grant(s)</span>}</td>
                <td class="small">{fmtDate(u.last_login_at)}</td>
                <td class="row" style="flex-wrap:nowrap">
                  {u.id !== me.id && <button class="btn sm" onClick={async () => { await patch(`api/admin/users/${u.id}`, { active: !u.active }); load(); }}>{u.active ? 'Disable' : 'Enable'}</button>}
                  <button class="btn sm" onClick={async () => { if (!confirm(`Reset password for ${u.email}?`)) return; const r = await patch<{ password: string }>(`api/admin/users/${u.id}`, { reset_password: true }); setCreated({ email: u.email, password: r.password }); }}>Reset password</button>
                  {u.id !== me.id && <button class="btn sm danger" onClick={async () => { if (confirm(`Delete ${u.email}?`)) { await del(`api/admin/users/${u.id}`); load(); } }}><Icon name="trash" size={14} /></button>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {form && (
        <Modal title="New user" onClose={() => setForm(null)}>
          <form onSubmit={async (e) => {
            e.preventDefault();
            try {
              const r = await post<{ password: string }>('api/admin/users', { ...form, password: form.password || null });
              setCreated({ email: form.email, password: r.password });
              setForm(null);
              load();
            } catch (ex: any) { toast(ex.message); }
          }}>
            <label class="f">Name</label><input class="input" required value={form.name} onInput={(e) => setForm({ ...form, name: e.currentTarget.value })} />
            <label class="f">Email</label><input class="input" type="email" required value={form.email} onInput={(e) => setForm({ ...form, email: e.currentTarget.value })} />
            <label class="f">Role</label>
            <select class="input" value={form.role} onChange={(e) => setForm({ ...form, role: e.currentTarget.value })}>
              {Object.entries(roleHelp).map(([r, h]) => <option value={r}>{r} – {h}</option>)}
            </select>
            <label class="f">Password</label><input class="input" type="text" placeholder="Leave empty to generate one" value={form.password} onInput={(e) => setForm({ ...form, password: e.currentTarget.value })} />
            <div class="row" style="justify-content:flex-end;margin-top:14px"><button class="btn" type="button" onClick={() => setForm(null)}>Cancel</button><button class="btn primary">Create</button></div>
          </form>
        </Modal>
      )}
    </>
  );
}

function Access() {
  const [perms, setPerms] = useState<any[]>([]);
  const [users, setUsers] = useState<User[]>([]);
  const [projects, setProjects] = useState<Project[]>([]);
  const [form, setForm] = useState({ user_id: '', target: '', role: 'viewer' });
  const load = () => get<{ permissions: any[] }>('api/admin/permissions').then((r) => setPerms(r.permissions));
  useEffect(() => {
    load();
    get<{ users: User[] }>('api/admin/users').then((r) => setUsers(r.users.filter((u) => u.role !== 'admin')));
    get<{ projects: Project[] }>('api/projects').then((r) => setProjects(r.projects));
  }, []);

  const grant = async (e: Event) => {
    e.preventDefault();
    if (!form.user_id || !form.target) return toast('Choose a user and a project or model');
    const [kind, id] = form.target.split(':');
    await post('api/admin/permissions', { user_id: +form.user_id, [kind === 'p' ? 'project_id' : 'model_id']: +id, role: form.role });
    toast('Access granted');
    load();
  };

  return (
    <>
      <form class="card" style="margin-bottom:16px" onSubmit={grant}>
        <h3>Grant access</h3>
        <p class="small muted" style="margin-top:0">Project access covers all models in it (including future ones). <b>viewer</b> = look only · <b>commenter</b> = comments, measurements, markups, approval · <b>editor</b> = upload versions, share, delete.</p>
        <div class="row">
          <select class="input grow" value={form.user_id} onChange={(e) => setForm({ ...form, user_id: e.currentTarget.value })}>
            <option value="">User…</option>{users.map((u) => <option value={u.id}>{u.name} ({u.email})</option>)}
          </select>
          <select class="input grow" value={form.target} onChange={(e) => setForm({ ...form, target: e.currentTarget.value })}>
            <option value="">Project or model…</option>
            {projects.map((p) => (
              <optgroup label={p.name}>
                <option value={`p:${p.id}`}>▸ Whole project “{p.name}”</option>
                {p.models.map((m) => <option value={`m:${m.id}`}>{m.name}</option>)}
              </optgroup>
            ))}
          </select>
          <select class="input" style="width:auto" value={form.role} onChange={(e) => setForm({ ...form, role: e.currentTarget.value })}>
            <option value="viewer">viewer</option><option value="commenter">commenter</option><option value="editor">editor</option>
          </select>
          <button class="btn primary">Grant</button>
        </div>
      </form>
      <div class="table-wrap">
        <table class="t">
          <thead><tr><th>User</th><th>On</th><th>Role</th><th></th></tr></thead>
          <tbody>
            {perms.map((p) => (
              <tr key={p.id}>
                <td>{p.user_name}<div class="small muted">{p.user_email}</div></td>
                <td>{p.project_id ? <>Project <b>{p.project_name}</b></> : <>Model <Link to={`/m/${p.model_id}`}>{p.model_name}</Link></>}</td>
                <td><span class="pill">{p.role}</span></td>
                <td><button class="btn sm danger" onClick={async () => { await del(`api/admin/permissions/${p.id}`); load(); }}>Revoke</button></td>
              </tr>
            ))}
            {!perms.length && <tr><td colSpan={4} class="muted">No grants yet</td></tr>}
          </tbody>
        </table>
      </div>
    </>
  );
}

function Shares() {
  const [links, setLinks] = useState<ShareLink[]>([]);
  const load = () => get<{ shares: ShareLink[] }>('api/shares').then((r) => setLinks(r.shares));
  useEffect(() => { load(); }, []);
  return (
    <div class="table-wrap">
      <table class="t">
        <thead><tr><th>Model</th><th>Link</th><th>Options</th><th>Views</th><th></th></tr></thead>
        <tbody>
          {links.map((l) => (
            <tr key={l.id} style={l.revoked || l.expired ? 'opacity:.55' : ''}>
              <td><Link to={`/m/${l.model_id}`}>{l.model_name}</Link></td>
              <td>{l.label || '—'}<div class="small muted">{fmtDate(l.created_at)}{l.expires_at && ` → ${fmtDate(l.expires_at)}`}</div></td>
              <td class="small">{l.has_password && 'password '}{l.allow_download && 'download '}{l.allow_comments && 'comments '}{l.watermark && 'watermark '}{l.revoked && <span class="pill bad">revoked</span>}{l.expired && <span class="pill bad">expired</span>}</td>
              <td>{l.views}</td>
              <td class="row" style="flex-wrap:nowrap">
                <button class="btn sm" onClick={() => { navigator.clipboard?.writeText(shareUrl(l.token)); toast('Copied'); }}>Copy</button>
                <button class="btn sm" onClick={async () => { await patch(`api/shares/${l.id}`, { revoked: !l.revoked }); load(); }}>{l.revoked ? 'Enable' : 'Revoke'}</button>
                <button class="btn sm danger" onClick={async () => { if (confirm('Delete link?')) { await del(`api/shares/${l.id}`); load(); } }}><Icon name="trash" size={14} /></button>
              </td>
            </tr>
          ))}
          {!links.length && <tr><td colSpan={5} class="muted">No share links</td></tr>}
        </tbody>
      </table>
    </div>
  );
}

function Tokens() {
  const [tokens, setTokens] = useState<any[]>([]);
  const load = () => get<{ tokens: any[] }>('api/admin/tokens').then((r) => setTokens(r.tokens));
  useEffect(() => { load(); }, []);
  return (
    <div class="table-wrap">
      <table class="t">
        <thead><tr><th>User</th><th>Name</th><th>Token</th><th>Last used</th><th></th></tr></thead>
        <tbody>
          {tokens.map((t) => (
            <tr key={t.id}><td>{t.user_name}</td><td>{t.name}</td><td><code>{t.prefix}…</code></td><td>{fmtDate(t.last_used_at)}</td>
              <td>{+t.revoked ? <span class="pill bad">revoked</span> : <button class="btn sm danger" onClick={async () => { await del(`api/me/tokens/${t.id}`); load(); }}>Revoke</button>}</td></tr>
          ))}
          {!tokens.length && <tr><td colSpan={5} class="muted">No plugin tokens</td></tr>}
        </tbody>
      </table>
    </div>
  );
}

function Activity() {
  const [rows, setRows] = useState<any[]>([]);
  useEffect(() => { get<{ entries: any[] }>('api/admin/audit?limit=300').then((r) => setRows(r.entries)); }, []);
  return (
    <div class="table-wrap">
      <table class="t small">
        <thead><tr><th>When</th><th>Who</th><th>Action</th><th>Target</th><th>Details</th><th>IP</th></tr></thead>
        <tbody>{rows.map((r) => <tr key={r.id}><td>{fmtDate(r.created_at)}</td><td>{r.user_name ?? '—'}</td><td><b>{r.action.replace(/_/g, ' ')}</b></td><td>{r.target}</td><td class="muted" style="max-width:260px;overflow:hidden;text-overflow:ellipsis">{r.details}</td><td class="muted">{r.ip}</td></tr>)}</tbody>
      </table>
    </div>
  );
}
