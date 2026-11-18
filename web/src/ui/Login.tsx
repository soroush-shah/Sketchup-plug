import { useState } from 'preact/hooks';
import { post, type User } from '../lib/api';
import { href, navigate, setState } from '../lib/store';
import { Link } from './common';

export function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async (e: Event) => {
    e.preventDefault();
    setBusy(true);
    setErr('');
    try {
      const r = await post<{ user: User }>('api/auth/login', { email, password });
      setState({ user: r.user });
      const next = new URLSearchParams(location.search).get('next');
      navigate(next && next.startsWith('/') ? next : '/', true);
    } catch (e: any) {
      setErr(e.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div style="min-height:100vh;display:grid;place-items:center;padding:16px">
      <form class="card" style="width:min(380px,100%);padding:28px" onSubmit={submit}>
        <div class="row" style="justify-content:center;margin-bottom:16px"><img src={href('icons/icon.svg')} width={44} height={44} alt="" /></div>
        <h1 style="text-align:center">SkpShare</h1>
        <p class="muted" style="text-align:center;margin-top:0">View and share SketchUp models</p>
        {err && <div class="error">{err}</div>}
        <label class="f">Email</label>
        <input class="input" type="email" autoComplete="username" required value={email} onInput={(e) => setEmail(e.currentTarget.value)} />
        <label class="f">Password</label>
        <input class="input" type="password" autoComplete="current-password" required value={password} onInput={(e) => setPassword(e.currentTarget.value)} />
        <button class="btn primary" style="width:100%;margin-top:18px" disabled={busy}>{busy ? 'Signing in…' : 'Sign in'}</button>
        <p class="small muted" style="text-align:center;margin-bottom:0">No account? Ask your administrator. <br /><Link to="/offline">Open offline library</Link></p>
      </form>
    </div>
  );
}
