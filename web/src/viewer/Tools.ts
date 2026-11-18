// Interactive tools (measure / line / highlight / comment pin) and rendering of saved annotations.
import * as THREE from 'three';
import { Line2 } from 'three/addons/lines/Line2.js';
import { LineGeometry } from 'three/addons/lines/LineGeometry.js';
import { LineMaterial } from 'three/addons/lines/LineMaterial.js';
import { CSS2DObject } from 'three/addons/renderers/CSS2DRenderer.js';
import type { Viewer, PickHit } from './Viewer';
import { fmtAngle, fmtArea, fmtLength, type LengthUnit } from './units';

export type ToolName = 'none' | 'measure' | 'line' | 'highlight' | 'comment';
export type MeasureKind = 'distance' | 'height' | 'angle' | 'area';
export interface DraftResult { type: 'measure' | 'line' | 'highlight' | 'comment'; data: any }
export interface AnnotationLike { id: number | string; type: string; data: any; body?: string | null; status?: string; author_name?: string; parent_id?: number | null }

const V = (a: number[]) => new THREE.Vector3().fromArray(a);
const SNAP_COLORS: Record<string, number> = { vertex: 0x16a34a, midpoint: 0x0891b2, edge: 0xdc2626, face: 0x2563eb };

export function measureText(kind: MeasureKind, pts: THREE.Vector3[], unit: LengthUnit, precision = 0): string {
  if (kind === 'distance' && pts.length >= 2) {
    let d = 0;
    for (let i = 1; i < pts.length; i++) d += pts[i].distanceTo(pts[i - 1]);
    return fmtLength(d, unit, precision);
  }
  if (kind === 'height' && pts.length >= 2) return '↕ ' + fmtLength(Math.abs(pts[1].y - pts[0].y), unit, precision);
  if (kind === 'angle' && pts.length >= 3) return fmtAngle(pts[0].clone().sub(pts[1]).angleTo(pts[2].clone().sub(pts[1])));
  if (kind === 'area' && pts.length >= 3) {
    // Newell's method → area of a (planar) polygon in 3D
    const n = new THREE.Vector3();
    for (let i = 0; i < pts.length; i++) n.add(pts[i].clone().cross(pts[(i + 1) % pts.length]));
    return fmtArea(n.length() / 2, unit);
  }
  return '';
}

export class Annotator {
  tool: ToolName = 'none';
  measureKind: MeasureKind = 'distance';
  color = '#ef4444';
  unit: LengthUnit = 'mm';
  precision = 0;
  onCreate: (r: DraftResult) => void = () => {};
  onSelect: (id: number | string) => void = () => {};
  private draft: THREE.Vector3[] = [];
  private draftGroup = new THREE.Group();
  private savedGroup = new THREE.Group();
  private marker: THREE.Mesh;
  private lineMats: LineMaterial[] = [];
  private down: { x: number; y: number; t: number; id: number } | null = null;
  private painting = false;
  private unsubs: (() => void)[] = [];
  visible = true;

  constructor(private v: Viewer) {
    v.overlay.add(this.savedGroup, this.draftGroup);
    this.marker = new THREE.Mesh(new THREE.SphereGeometry(1, 16, 12), new THREE.MeshBasicMaterial({ color: 0x2563eb, depthTest: false }));
    this.marker.renderOrder = 1000;
    this.marker.visible = false;
    v.overlay.add(this.marker);
    const el = v.renderer.domElement;
    el.addEventListener('pointerdown', this.onDown);
    el.addEventListener('pointermove', this.onMove);
    el.addEventListener('pointerup', this.onUp);
    this.unsubs.push(v.on('render', () => this.updateResolution()));
  }

  dispose() {
    const el = this.v.renderer.domElement;
    el.removeEventListener('pointerdown', this.onDown);
    el.removeEventListener('pointermove', this.onMove);
    el.removeEventListener('pointerup', this.onUp);
    this.unsubs.forEach((u) => u());
  }

  setTool(t: ToolName) {
    this.cancelDraft();
    this.tool = t;
    // The highlighter paints with one finger, so orbiting is paused while it is active.
    this.v.controls.enabled = t !== 'highlight';
    this.marker.visible = false;
    this.v.renderer.domElement.style.cursor = t === 'none' ? '' : 'crosshair';
    this.v.requestRender();
  }

  cancelDraft() {
    this.draft = [];
    this.clearGroup(this.draftGroup);
    this.v.requestRender();
    this.v.emit('draft', 0);
  }

  /** Finish multi-point drafts (polyline, area). */
  finishDraft() {
    if (this.tool === 'line' && this.draft.length >= 2) this.onCreate({ type: 'line', data: { points: this.draft.map((p) => p.toArray()), color: this.color } });
    if (this.tool === 'measure' && this.measureKind === 'area' && this.draft.length >= 3) this.onCreate({ type: 'measure', data: { kind: 'area', points: this.draft.map((p) => p.toArray()) } });
    if (this.tool === 'measure' && this.measureKind === 'distance' && this.draft.length >= 2) this.onCreate({ type: 'measure', data: { kind: 'distance', points: this.draft.map((p) => p.toArray()) } });
    this.cancelDraft();
  }

  get draftCount() { return this.draft.length; }

  // ------------------------------------------------------------------ pointer
  private markerSize() {
    const d = this.v.camera.position.distanceTo(this.v.controls.target);
    return (this.v.camera as THREE.PerspectiveCamera).isPerspectiveCamera ? Math.max(0.005, d * 0.008) : 0.05 / (this.v.camera as THREE.OrthographicCamera).zoom;
  }

  private onDown = (e: PointerEvent) => {
    if (this.tool === 'none') return;
    this.down = { x: e.clientX, y: e.clientY, t: performance.now(), id: e.pointerId };
    if (this.tool === 'highlight' && e.isPrimary) {
      this.painting = true;
      this.draft = [];
      this.paint(e);
    }
  };

  private onMove = (e: PointerEvent) => {
    if (this.tool === 'none') return;
    if (this.painting) { this.paint(e); return; }
    if (e.pointerType === 'mouse' && (this.tool === 'measure' || this.tool === 'line' || this.tool === 'comment')) {
      const hit = this.v.pick(e.clientX, e.clientY, this.tool !== 'comment');
      this.showMarker(hit);
      if (hit && this.draft.length) this.drawDraft(hit.point);
    }
  };

  private onUp = (e: PointerEvent) => {
    if (this.tool === 'none' || !this.down || e.pointerId !== this.down.id) return;
    const moved = Math.hypot(e.clientX - this.down.x, e.clientY - this.down.y);
    const quick = performance.now() - this.down.t < 500;
    this.down = null;
    if (this.painting) {
      this.painting = false;
      if (this.draft.length >= 2) this.onCreate({ type: 'highlight', data: { points: this.draft.map((p) => p.toArray()), color: this.color, width: this.v.isMobile ? 18 : 14 } });
      this.cancelDraft();
      return;
    }
    if (moved > 8 || !quick) return; // it was an orbit/pan gesture
    const hit = this.v.pick(e.clientX, e.clientY, this.tool !== 'comment');
    if (!hit) return;
    this.showMarker(hit);
    this.tap(hit);
  };

  private tap(hit: PickHit) {
    const p = hit.point.clone();
    if (this.tool === 'comment') {
      this.onCreate({ type: 'comment', data: { point: p.toArray(), normal: hit.normal.toArray(), camera: this.v.getCameraState() } });
      return;
    }
    if (this.tool === 'line') p.addScaledVector(hit.normal, 0.002);
    this.draft.push(p);
    this.v.emit('draft', this.draft.length);
    if (this.tool === 'measure') {
      const need = { distance: 0, height: 2, angle: 3, area: 0 }[this.measureKind];
      if (need && this.draft.length >= need) {
        this.onCreate({ type: 'measure', data: { kind: this.measureKind, points: this.draft.map((x) => x.toArray()) } });
        this.cancelDraft();
        return;
      }
      if (this.measureKind === 'distance' && this.draft.length === 2 && !this.chainDistance) {
        this.onCreate({ type: 'measure', data: { kind: 'distance', points: this.draft.map((x) => x.toArray()) } });
        this.cancelDraft();
        return;
      }
    }
    this.drawDraft();
  }

  /** When true, distance measurement keeps adding segments until "Done". */
  chainDistance = false;

  private paint(e: PointerEvent) {
    const hit = this.v.pick(e.clientX, e.clientY);
    if (!hit) return;
    const p = hit.point.clone().addScaledVector(hit.normal, 0.004);
    const last = this.draft[this.draft.length - 1];
    if (last && this.v.toScreen(last).distanceTo(new THREE.Vector2(e.clientX, e.clientY)) < 4) return;
    this.draft.push(p);
    this.clearGroup(this.draftGroup);
    if (this.draft.length >= 2) this.draftGroup.add(this.fatLine(this.draft, this.color, this.v.isMobile ? 18 : 14, 0.45, true));
    this.v.requestRender();
  }

  private showMarker(hit: PickHit | null) {
    if (!hit) { this.marker.visible = false; this.v.requestRender(); return; }
    this.marker.visible = true;
    this.marker.position.copy(hit.point);
    this.marker.scale.setScalar(this.markerSize() * (hit.snapped === 'face' ? 0.6 : 1));
    (this.marker.material as THREE.MeshBasicMaterial).color.setHex(SNAP_COLORS[hit.snapped ?? 'face']);
    this.v.requestRender();
  }

  private drawDraft(cursor?: THREE.Vector3) {
    this.clearGroup(this.draftGroup);
    const pts = cursor ? [...this.draft, cursor] : this.draft;
    if (pts.length >= 2) {
      const closed = this.tool === 'measure' && this.measureKind === 'area' && pts.length >= 3;
      this.draftGroup.add(this.fatLine(closed ? [...pts, pts[0]] : pts, this.tool === 'line' ? this.color : '#2563eb', 2.5, 1, true, true));
      if (this.tool === 'measure') this.draftGroup.add(this.label(measureText(this.measureKind, pts, this.unit, this.precision), pts[pts.length - 1], 'draft'));
    }
    for (const p of this.draft) this.draftGroup.add(this.dot(p, '#2563eb'));
    this.v.requestRender();
  }

  // ------------------------------------------------------------------ saved annotations
  setAnnotations(list: AnnotationLike[], selected?: number | string | null) {
    this.clearGroup(this.savedGroup);
    let pin = 0;
    for (const a of list) {
      const d = a.data;
      if (!d) continue;
      if (a.type === 'measure' && d.points?.length >= 2) {
        const pts = d.points.map(V);
        const closed = d.kind === 'area';
        this.savedGroup.add(this.fatLine(closed ? [...pts, pts[0]] : d.kind === 'height' ? [pts[0], new THREE.Vector3(pts[0].x, pts[1].y, pts[0].z), pts[1]] : pts, '#0f172a', 2, 1, true));
        for (const p of pts) this.savedGroup.add(this.dot(p, '#0f172a'));
        const mid = d.kind === 'angle' ? pts[1] : pts.reduce((s: THREE.Vector3, p: THREE.Vector3) => s.add(p), new THREE.Vector3()).multiplyScalar(1 / pts.length);
        const l = this.label(measureText(d.kind, pts, this.unit, this.precision), mid, 'measure', a.id);
        this.savedGroup.add(l);
      } else if (a.type === 'line' && d.points?.length >= 2) {
        this.savedGroup.add(this.fatLine(d.points.map(V), d.color || '#ef4444', 3, 1, false));
      } else if (a.type === 'highlight' && d.points?.length >= 2) {
        this.savedGroup.add(this.fatLine(d.points.map(V), d.color || '#facc15', d.width || 14, 0.45, false));
      } else if ((a.type === 'comment' || a.type === 'note') && d.point && !a.parent_id) {
        pin++;
        const el = document.createElement('button');
        el.className = 'pin' + (a.status === 'resolved' ? ' resolved' : '') + (selected === a.id ? ' selected' : '');
        el.textContent = String(pin);
        el.title = (a.author_name ? a.author_name + ': ' : '') + (a.body ?? '');
        el.onpointerdown = (ev) => ev.stopPropagation();
        el.onclick = (ev) => { ev.stopPropagation(); this.onSelect(a.id); };
        const o = new CSS2DObject(el);
        o.position.fromArray(d.point);
        this.savedGroup.add(o);
      }
    }
    this.savedGroup.visible = this.visible;
    this.v.requestRender();
  }

  setVisible(on: boolean) { this.visible = on; this.savedGroup.visible = on; this.savedGroup.traverse((o) => { if ((o as any).isCSS2DObject) o.visible = on; }); this.v.requestRender(); }

  // ------------------------------------------------------------------ primitives
  private fatLine(pts: THREE.Vector3[], color: string, width: number, opacity: number, onTop: boolean, dashed = false): Line2 {
    const g = new LineGeometry();
    g.setPositions(pts.flatMap((p) => [p.x, p.y, p.z]));
    const m = new LineMaterial({ color: new THREE.Color(color).getHex(), linewidth: width, transparent: opacity < 1 || onTop, opacity, depthTest: !onTop, dashed, dashSize: 0.1, gapSize: 0.05 });
    m.resolution.set(this.v.container.clientWidth, this.v.container.clientHeight);
    if (!onTop) {
      // Strokes are drawn on surfaces: pull them towards the camera to avoid z-fighting with the wall.
      m.polygonOffset = true;
      m.polygonOffsetFactor = -8;
      m.polygonOffsetUnits = -8;
    }
    if (opacity < 1) {
      // Translucent strokes: draw each pixel once (stencil) so overlapping segments don't darken at joints.
      m.stencilWrite = true;
      m.stencilRef = 1;
      m.stencilFunc = THREE.NotEqualStencilFunc;
      m.stencilZPass = THREE.ReplaceStencilOp;
      m.depthWrite = false;
    }
    this.lineMats.push(m);
    const l = new Line2(g, m);
    if (dashed) l.computeLineDistances();
    l.renderOrder = onTop ? 998 : opacity < 1 ? 50 : 2;
    l.raycast = () => {};
    return l;
  }

  private dot(p: THREE.Vector3, color: string) {
    const m = new THREE.Mesh(new THREE.SphereGeometry(1, 10, 8), new THREE.MeshBasicMaterial({ color, depthTest: false }));
    m.position.copy(p);
    m.scale.setScalar(this.markerSize() * 0.5);
    m.renderOrder = 999;
    m.raycast = () => {};
    m.userData.dot = true;
    return m;
  }

  private label(text: string, at: THREE.Vector3, cls: string, id?: number | string) {
    const el = document.createElement('div');
    el.className = 'mlabel ' + cls;
    el.textContent = text;
    if (id !== undefined) { el.onpointerdown = (e) => e.stopPropagation(); el.onclick = () => this.onSelect(id); }
    const o = new CSS2DObject(el);
    o.position.copy(at);
    return o;
  }

  private clearGroup(g: THREE.Group) {
    g.traverse((o: any) => {
      if (o.isCSS2DObject) o.element.remove();
      o.geometry?.dispose?.();
      if (o.material) { this.lineMats = this.lineMats.filter((m) => m !== o.material); o.material.dispose(); }
    });
    g.clear();
  }

  private updateResolution() {
    const w = this.v.container.clientWidth, h = this.v.container.clientHeight;
    for (const m of this.lineMats) m.resolution.set(w, h);
    const s = this.markerSize() * 0.5;
    for (const g of [this.savedGroup, this.draftGroup]) g.children.forEach((o) => { if (o.userData.dot) o.scale.setScalar(s); });
  }
}
