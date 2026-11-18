// Tiny global store + path router (no dependencies).
import { useEffect, useState } from 'preact/hooks';
import { basePath, type User } from './api';

type Sub = () => void;
const subs = new Set<Sub>();
export const state = {
  user: null as User | null,
  loaded: false,
  online: navigator.onLine,
  toast: null as string | null,
};
export function setState(p: Partial<typeof state>) { Object.assign(state, p); subs.forEach((s) => s()); }
export function useStore() {
  const [, force] = useState(0);
  useEffect(() => { const f = () => force((x) => x + 1); subs.add(f); return () => { subs.delete(f); }; }, []);
  return state;
}

let toastTimer = 0;
export function toast(msg: string, ms = 3200) {
  clearTimeout(toastTimer);
  setState({ toast: msg });
  toastTimer = window.setTimeout(() => setState({ toast: null }), ms);
}

window.addEventListener('online', () => setState({ online: true }));
window.addEventListener('offline', () => setState({ online: false }));

// ---------------------------------------------------------------- router
const routeSubs = new Set<Sub>();
export function currentPath(): string {
  let p = location.pathname;
  const b = new URL(basePath, location.origin).pathname;
  if (p.startsWith(b)) p = '/' + p.slice(b.length);
  return p.replace(/\/+$/, '') || '/';
}
export function navigate(path: string, replace = false) {
  const full = basePath + path.replace(/^\//, '');
  replace ? history.replaceState(null, '', full) : history.pushState(null, '', full);
  routeSubs.forEach((s) => s());
  window.scrollTo(0, 0);
}
window.addEventListener('popstate', () => routeSubs.forEach((s) => s()));
export function useRoute() {
  const [, force] = useState(0);
  useEffect(() => { const f = () => force((x) => x + 1); routeSubs.add(f); return () => { routeSubs.delete(f); }; }, []);
  return { path: currentPath(), query: new URLSearchParams(location.search) };
}

/** <a> that navigates client-side. */
export function linkHandler(path: string) {
  return (e: MouseEvent) => {
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
    e.preventDefault();
    navigate(path);
  };
}
export const href = (path: string) => basePath + path.replace(/^\//, '');
