// Small inline icon set (stroke icons, 24px grid).
const P: Record<string, string> = {
  orbit: 'M12 3a9 9 0 1 0 9 9M12 3c2.5 2.5 3.5 5.5 3.5 9s-1 6.5-3.5 9m0-18C9.5 5.5 8.5 8.5 8.5 12s1 6.5 3.5 9M3.5 9h17M3.5 15h17M21 3v4h-4',
  walk: 'M13 4a1.5 1.5 0 1 0 0-.01M10 21l2-6 2 2v4m-4-9 1-4 4 2 2 3m-7-1-2 3',
  section: 'M4 7l8-4 8 4v10l-8 4-8-4zM2 13h20',
  measure: 'M3 17 17 3l4 4L7 21zM7 13l2 2m1-5 2 2m1-5 2 2',
  line: 'M4 20 20 4M4 20h4M4 20v-4',
  highlight: 'M9 11l-5 5v4h4l5-5M14 6l4 4M12 8l6-6 4 4-6 6',
  comment: 'M4 5h16v11H9l-5 4z',
  markup: 'M4 4h16v12H4zM8 20h8M12 16v4M8 8l3 3 5-4',
  tags: 'M3 12V3h9l9 9-9 9zM7.5 7.5h.01',
  scenes: 'M4 6h16v12H4zM4 10h16M9 6v4m6-4v4',
  views: 'M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12zM12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6',
  settings: 'M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6M19 12a7 7 0 0 0-.1-1.2l2-1.6-2-3.4-2.4.9a7 7 0 0 0-2-1.2L14 3h-4l-.5 2.5a7 7 0 0 0-2 1.2l-2.4-.9-2 3.4 2 1.6a7 7 0 0 0 0 2.4l-2 1.6 2 3.4 2.4-.9a7 7 0 0 0 2 1.2L10 21h4l.5-2.5a7 7 0 0 0 2-1.2l2.4.9 2-3.4-2-1.6c.1-.4.1-.8.1-1.2',
  info: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18M12 11v6m0-9h.01',
  ar: 'M3 7V4h3M21 7V4h-3M3 17v3h3M21 17v3h-3M12 7l5 3v5l-5 3-5-3v-5z',
  play: 'M7 4v16l13-8z',
  bom: 'M4 5h16M4 10h16M4 15h10M4 20h7',
  home: 'M3 11l9-7 9 7v9h-6v-6H9v6H3z',
  back: 'M15 5l-7 7 7 7',
  share: 'M18 8a3 3 0 1 0-3-3M6 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6m12 7a3 3 0 1 0 0-6M8.6 13.5l6.8 4M15.4 6.5l-6.8 4',
  download: 'M12 4v12m-5-5 5 5 5-5M4 20h16',
  offline: 'M12 4v10m-4-4 4 4 4-4M5 18a4 4 0 0 1 0-8 6 6 0 0 1 11.5-2A4.5 4.5 0 0 1 19 17',
  close: 'M6 6l12 12M18 6 6 18',
  compare: 'M12 3v18M5 7h4v10H5zM15 7h4v10h-4z',
  versions: 'M12 3l9 5-9 5-9-5zM3 13l9 5 9-5M3 17l9 5 9-5',
  fullscreen: 'M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5',
  check: 'M5 12l5 5L20 7',
  trash: 'M4 7h16M9 7V4h6v3m-8 0 1 13h8l1-13',
  plus: 'M12 5v14M5 12h14',
  upload: 'M12 20V8m-5 5 5-5 5 5M4 4h16',
  user: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8M4 21a8 8 0 0 1 16 0',
  admin: 'M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z',
  qr: 'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h2v2h-2zM18 18h2v2h-2zM14 18h2M18 14h2',
  eye: 'M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12zM12 10a2 2 0 1 0 0 4 2 2 0 0 0 0-4',
  eyeoff: 'M3 3l18 18M10.6 6.1A9.9 9.9 0 0 1 12 6c6 0 10 6 10 6a17 17 0 0 1-3.2 3.8M6.6 6.6C3.8 8.4 2 12 2 12s4 7 10 7c1.7 0 3.2-.5 4.4-1.2',
  sun: 'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4',
  logout: 'M15 4h4v16h-4M10 8l-4 4 4 4M6 12h10',
};

export function Icon({ name, size = 20 }: { name: string; size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d={P[name] ?? P.info} />
    </svg>
  );
}
