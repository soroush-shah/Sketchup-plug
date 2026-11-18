import { useRef } from 'preact/hooks';

/** Virtual thumb-stick for walking on touch screens. Calls onMove(x, y) with values in -1..1 (y = forward). */
export function Joystick({ onMove }: { onMove: (x: number, y: number) => void }) {
  const base = useRef<HTMLDivElement>(null);
  const knob = useRef<HTMLDivElement>(null);
  const id = useRef<number | null>(null);

  const update = (e: PointerEvent) => {
    const r = base.current!.getBoundingClientRect();
    const R = r.width / 2;
    let dx = e.clientX - (r.left + R), dy = e.clientY - (r.top + R);
    const len = Math.hypot(dx, dy);
    if (len > R) { dx *= R / len; dy *= R / len; }
    knob.current!.style.transform = `translate(${dx}px, ${dy}px)`;
    const dead = 0.12;
    const nx = Math.abs(dx / R) < dead ? 0 : dx / R, ny = Math.abs(dy / R) < dead ? 0 : -dy / R;
    onMove(nx, ny);
  };
  const end = () => { id.current = null; knob.current!.style.transform = ''; onMove(0, 0); };

  return (
    <div class="joystick" ref={base}
      onPointerDown={(e) => { id.current = e.pointerId; (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId); update(e); e.stopPropagation(); }}
      onPointerMove={(e) => { if (e.pointerId === id.current) update(e); }}
      onPointerUp={end} onPointerCancel={end}>
      <div class="knob" ref={knob} />
    </div>
  );
}
