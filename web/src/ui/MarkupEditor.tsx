// Full-screen 2D markup on a snapshot of the 3D view: pen, arrow, rectangle, ellipse, text.
import { useEffect, useRef, useState } from 'preact/hooks';
import { Icon } from './icons';

type Tool = 'pen' | 'arrow' | 'rect' | 'ellipse' | 'text';
type Shape = { tool: Tool; color: string; width: number; pts: [number, number][]; text?: string };
const COLORS = ['#ef4444', '#f59e0b', '#22c55e', '#2563eb', '#111827', '#ffffff'];

export function MarkupEditor({ image, onSave, onClose, canSave }: { image: string; onSave: (dataUrl: string, note: string) => void; onClose: () => void; canSave: boolean }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const [img, setImg] = useState<HTMLImageElement | null>(null);
  const [shapes, setShapes] = useState<Shape[]>([]);
  const [tool, setTool] = useState<Tool>('pen');
  const [color, setColor] = useState(COLORS[0]);
  const [note, setNote] = useState('');
  const cur = useRef<Shape | null>(null);

  useEffect(() => { const i = new Image(); i.onload = () => setImg(i); i.src = image; }, [image]);

  const draw = (list: Shape[]) => {
    const c = canvas.current, i = img;
    if (!c || !i) return;
    c.width = i.naturalWidth; c.height = i.naturalHeight;
    const g = c.getContext('2d')!;
    g.drawImage(i, 0, 0);
    for (const s of list) {
      g.strokeStyle = g.fillStyle = s.color;
      g.lineWidth = s.width;
      g.lineCap = g.lineJoin = 'round';
      const [a, b] = [s.pts[0], s.pts[s.pts.length - 1]];
      g.beginPath();
      if (s.tool === 'pen') { s.pts.forEach(([x, y], k) => (k ? g.lineTo(x, y) : g.moveTo(x, y))); g.stroke(); }
      if (s.tool === 'rect') { g.strokeRect(a[0], a[1], b[0] - a[0], b[1] - a[1]); }
      if (s.tool === 'ellipse') { g.ellipse((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, Math.abs(b[0] - a[0]) / 2, Math.abs(b[1] - a[1]) / 2, 0, 0, Math.PI * 2); g.stroke(); }
      if (s.tool === 'arrow') {
        g.moveTo(a[0], a[1]); g.lineTo(b[0], b[1]); g.stroke();
        const ang = Math.atan2(b[1] - a[1], b[0] - a[0]), h = s.width * 5;
        g.beginPath(); g.moveTo(b[0], b[1]);
        g.lineTo(b[0] - h * Math.cos(ang - 0.45), b[1] - h * Math.sin(ang - 0.45));
        g.lineTo(b[0] - h * Math.cos(ang + 0.45), b[1] - h * Math.sin(ang + 0.45));
        g.closePath(); g.fill();
      }
      if (s.tool === 'text' && s.text) {
        g.font = `700 ${s.width * 7}px system-ui, sans-serif`;
        g.lineWidth = s.width * 1.2; g.strokeStyle = s.color === '#ffffff' ? '#111827' : '#ffffff';
        g.strokeText(s.text, a[0], a[1]); g.fillText(s.text, a[0], a[1]);
      }
    }
  };
  useEffect(() => draw(shapes), [img, shapes]);

  const pos = (e: PointerEvent): [number, number] => {
    const c = canvas.current!, r = c.getBoundingClientRect();
    return [((e.clientX - r.left) / r.width) * c.width, ((e.clientY - r.top) / r.height) * c.height];
  };
  const width = () => Math.max(3, Math.round((img?.naturalWidth ?? 1200) / 300));

  const down = (e: PointerEvent) => {
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
    const p = pos(e);
    if (tool === 'text') {
      const t = prompt('Text');
      if (t) setShapes([...shapes, { tool, color, width: width(), pts: [p], text: t }]);
      return;
    }
    cur.current = { tool, color, width: width(), pts: [p, p] };
  };
  const move = (e: PointerEvent) => {
    const s = cur.current;
    if (!s) return;
    const p = pos(e);
    if (s.tool === 'pen') s.pts.push(p); else s.pts[1] = p;
    draw([...shapes, s]);
  };
  const up = () => { if (cur.current) setShapes([...shapes, cur.current]); cur.current = null; };

  const result = () => canvas.current!.toDataURL('image/jpeg', 0.85);

  return (
    <div class="markup">
      <div class="bar">
        {(['pen', 'arrow', 'rect', 'ellipse', 'text'] as Tool[]).map((t) => <button class={'btn sm' + (tool === t ? ' on' : '')} onClick={() => setTool(t)}>{t}</button>)}
        {COLORS.map((c) => <button class={'swatch' + (c === color ? ' on' : '')} style={{ background: c }} onClick={() => setColor(c)} aria-label={c} />)}
        <button class="btn sm" onClick={() => setShapes(shapes.slice(0, -1))} disabled={!shapes.length}>Undo</button>
        <span class="grow" />
        <button class="btn sm" onClick={() => { const a = document.createElement('a'); a.href = result(); a.download = 'markup.jpg'; a.click(); }}><Icon name="download" size={16} />Save image</button>
        {canSave && <input class="input" style="max-width:220px;min-height:32px;padding:4px 8px;background:#0b1220;color:#fff;border-color:#334155" placeholder="Note (optional)" value={note} onInput={(e) => setNote(e.currentTarget.value)} />}
        {canSave && <button class="btn sm on" onClick={() => onSave(result(), note)}>Post to model</button>}
        <button class="btn sm" onClick={onClose}><Icon name="close" size={16} /></button>
      </div>
      <div class="stage"><canvas ref={canvas} onPointerDown={down as any} onPointerMove={move as any} onPointerUp={up} onPointerCancel={up} /></div>
    </div>
  );
}
