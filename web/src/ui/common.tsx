import type { ComponentChildren } from 'preact';
import { useEffect } from 'preact/hooks';
import { href, linkHandler, navigate, setState, useRoute, useStore } from '../lib/store';
import { post } from '../lib/api';
import { Icon } from './icons';

export function Link({ to, children, class: cls }: { to: string; children: ComponentChildren; class?: string }) {
  return <a href={href(to)} onClick={linkHandler(to)} class={cls}>{children}</a>;
}

export function Modal({ title, onClose, children, wide }: { title: string; onClose: () => void; children: ComponentChildren; wide?: boolean }) {
  useEffect(() => {
    const k = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', k);
    return () => window.removeEventListener('keydown', k);
  }, [onClose]);
  return (
    <div class="modal-bg" onPointerDown={(e) => e.target === e.currentTarget && onClose()}>
      <div class={'modal' + (wide ? ' wide' : '')} role="dialog" aria-label={title}>
        <div class="modal-head"><h2>{title}</h2><button class="btn ghost sm" onClick={onClose} aria-label="Close"><Icon name="close" /></button></div>
        {children}
      </div>
    </div>
  );
}

export function Toast() {
  const s = useStore();
  return s.toast ? <div class="toast" role="status">{s.toast}</div> : null;
}

export function TopBar() {
  const s = useStore();
  const { path } = useRoute();
  const u = s.user;
  const nav = (to: string, icon: string, label: string) => (
    <Link to={to} class={path === to || (to !== '/' && path.startsWith(to)) ? 'on' : ''}><span class="row" style="gap:6px"><Icon name={icon} size={18} /><span>{label}</span></span></Link>
  );
  return (
    <>
      {!s.online && <div class="offline-banner">Offline – showing models saved on this device</div>}
      <header class="topbar">
        <Link to="/" class="brand"><img src={href('icons/icon.svg')} alt="" />SkpShare</Link>
        <nav class="nav">
          {u && nav('/', 'home', 'Models')}
          {nav('/offline', 'offline', 'Offline')}
          {u?.role === 'admin' && nav('/admin', 'admin', 'Admin')}
        </nav>
        <span class="grow" />
        {u ? (
          <>
            <Link to="/account" class="btn ghost sm"><Icon name="user" size={18} /><span class="hide-sm">{u.name}</span></Link>
            <button class="btn ghost sm" title="Log out" onClick={async () => { await post('api/auth/logout').catch(() => {}); setState({ user: null }); navigate('/login'); }}><Icon name="logout" size={18} /></button>
          </>
        ) : <Link to="/login" class="btn sm">Log in</Link>}
      </header>
    </>
  );
}

export function Progress({ value }: { value: number }) {
  return <div class="progress"><div style={{ width: `${Math.round(Math.max(0, Math.min(1, value)) * 100)}%` }} /></div>;
}

export function Empty({ children }: { children: ComponentChildren }) {
  return <div class="card muted" style="text-align:center;padding:40px 16px">{children}</div>;
}

export const approvalPill = (s: string | null | undefined) =>
  s === 'approved' ? <span class="pill ok">Approved</span> : s === 'changes_requested' ? <span class="pill bad">Changes requested</span> : s ? <span class="pill warn">Pending review</span> : null;
