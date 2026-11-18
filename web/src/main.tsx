import { render } from 'preact';
import { useEffect } from 'preact/hooks';
import './styles.css';
import { get, basePath, type User } from './lib/api';
import { navigate, setState, useRoute, useStore } from './lib/store';
import { Toast } from './ui/common';
import { Login } from './ui/Login';
import { Library } from './ui/Library';
import { ModelPage } from './ui/ModelPage';
import { ShareGate } from './ui/ShareGate';
import { OfflinePage } from './ui/OfflinePage';
import { Admin } from './ui/Admin';
import { Account } from './ui/Account';

function App() {
  const s = useStore();
  const { path } = useRoute();

  useEffect(() => {
    get<{ user: User | null }>('api/me')
      .then((r) => setState({ user: r.user, loaded: true }))
      .catch(() => setState({ loaded: true }));
  }, []);

  if (!s.loaded) return null;

  let m: RegExpMatchArray | null;
  if ((m = path.match(/^\/s\/([\w-]+)$/))) return <><ShareGate token={m[1]} /><Toast /></>;
  if ((m = path.match(/^\/m\/(\d+)$/))) return <><ModelPage id={+m[1]} /><Toast /></>;
  if (path === '/offline') return <><OfflinePage /><Toast /></>;
  if (path === '/login') return <><Login /><Toast /></>;
  if (!s.user) return <Redirect to={s.online ? `/login${path !== '/' ? '?next=' + encodeURIComponent(path) : ''}` : '/offline'} />;
  if (path === '/admin' && s.user.role === 'admin') return <><Admin /><Toast /></>;
  if (path === '/account') return <><Account /><Toast /></>;
  return <><Library /><Toast /></>;
}

function Redirect({ to }: { to: string }) {
  useEffect(() => navigate(to, true), [to]);
  return null;
}

render(<App />, document.getElementById('app')!);

if ('serviceWorker' in navigator && import.meta.env.PROD) {
  navigator.serviceWorker.register(basePath + 'sw.js', { scope: basePath }).catch(() => {});
}
