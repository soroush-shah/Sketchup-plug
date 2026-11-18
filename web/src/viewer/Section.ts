// Section plane & section box with stencil-filled caps and draggable handles (mouse + touch).
import * as THREE from 'three';
import type { Viewer } from './Viewer';

export type SectionMode = 'off' | 'plane' | 'box';
export interface SectionState { mode: SectionMode; normal?: number[]; constant?: number; min?: number[]; max?: number[]; caps?: boolean }

const AXES = [new THREE.Vector3(1, 0, 0), new THREE.Vector3(0, 1, 0), new THREE.Vector3(0, 0, 1)];
const MAX_CAP_MESHES = 400;

export class SectionTool {
  mode: SectionMode = 'off';
  caps = true;
  capColor = new THREE.Color(0xd94b4b);
  readonly plane = new THREE.Plane(new THREE.Vector3(0, -1, 0), 0);
  readonly box = new THREE.Box3();
  private boxPlanes: THREE.Plane[] = [];
  private helpers = new THREE.Group();
  private stencil = new THREE.Group();
  private handles: THREE.Mesh[] = [];
  private drag: { handle: THREE.Mesh; axis: THREE.Vector3; start: number; origin: number } | null = null;
  private pickNext = false;
  private unsubs: (() => void)[] = [];

  constructor(private v: Viewer) {
    v.overlay.add(this.helpers);
    v.scene.add(this.stencil);
    const el = v.renderer.domElement;
    el.addEventListener('pointerdown', this.onDown, { capture: true });
    window.addEventListener('pointermove', this.onMove);
    window.addEventListener('pointerup', this.onUp);
    this.unsubs.push(v.on('model', () => this.rebuild()));
  }

  dispose() {
    const el = this.v.renderer.domElement;
    el.removeEventListener('pointerdown', this.onDown, { capture: true } as any);
    window.removeEventListener('pointermove', this.onMove);
    window.removeEventListener('pointerup', this.onUp);
    this.unsubs.forEach((u) => u());
    this.off();
  }

  get planes(): THREE.Plane[] {
    return this.mode === 'plane' ? [this.plane] : this.mode === 'box' ? this.boxPlanes : [];
  }

  // ------------------------------------------------------------------ public API
  off() {
    this.mode = 'off';
    this.pickNext = false;
    this.v.setClipping([]);
    this.clearCaps();
    this.helpers.clear();
    this.handles = [];
    this.v.requestRender();
    this.v.emit('section');
  }

  /** Axis-aligned plane through the model center. axis: x | y (horizontal plan cut) | z */
  setAxis(axis: 'x' | 'y' | 'z', flip = false) {
    const i = { x: 0, y: 1, z: 2 }[axis];
    const n = AXES[i].clone().multiplyScalar(flip ? 1 : -1);
    const c = this.v.bounds.getCenter(new THREE.Vector3());
    this.plane.setFromNormalAndCoplanarPoint(n, c);
    this.enable('plane');
  }

  /** Plane from an arbitrary point + normal (normal points to the kept side). */
  setPlane(normal: THREE.Vector3, point: THREE.Vector3) {
    this.plane.setFromNormalAndCoplanarPoint(normal.clone().normalize(), point);
    this.enable('plane');
  }

  /** Next tap on the model places a section plane on that surface. */
  pickFace() {
    this.pickNext = true;
    this.v.emit('section-pick', true);
  }

  flip() {
    if (this.mode !== 'plane') return;
    this.plane.negate();
    this.update();
  }

  /** 0..1 position of the plane across the model bounds along its normal. */
  get offset(): number {
    const [lo, hi] = this.range();
    return hi > lo ? (-this.plane.constant - lo) / (hi - lo) : 0.5;
  }

  set offset(t: number) {
    const [lo, hi] = this.range();
    this.plane.constant = -(lo + (hi - lo) * THREE.MathUtils.clamp(t, 0, 1));
    this.update();
  }

  private range(): [number, number] {
    const b = this.v.bounds;
    const n = this.plane.normal;
    let lo = Infinity, hi = -Infinity;
    for (let i = 0; i < 8; i++) {
      const p = new THREE.Vector3(i & 1 ? b.max.x : b.min.x, i & 2 ? b.max.y : b.min.y, i & 4 ? b.max.z : b.min.z);
      const d = n.dot(p);
      lo = Math.min(lo, d); hi = Math.max(hi, d);
    }
    const pad = (hi - lo) * 0.01;
    return [lo - pad, hi + pad];
  }

  setBox(box?: THREE.Box3) {
    if (box) this.box.copy(box);
    else {
      const size = this.v.bounds.getSize(new THREE.Vector3());
      this.box.copy(this.v.bounds).expandByVector(size.multiplyScalar(0.01));
    }
    this.enable('box');
  }

  setCaps(on: boolean) { this.caps = on; this.rebuild(); }

  getState(): SectionState {
    if (this.mode === 'plane') return { mode: 'plane', normal: this.plane.normal.toArray(), constant: this.plane.constant, caps: this.caps };
    if (this.mode === 'box') return { mode: 'box', min: this.box.min.toArray(), max: this.box.max.toArray(), caps: this.caps };
    return { mode: 'off' };
  }

  setState(s: SectionState | null | undefined) {
    if (!s || s.mode === 'off') return this.off();
    if (s.caps !== undefined) this.caps = s.caps;
    if (s.mode === 'plane' && s.normal) { this.plane.normal.fromArray(s.normal); this.plane.constant = s.constant ?? 0; this.enable('plane'); }
    if (s.mode === 'box' && s.min && s.max) this.setBox(new THREE.Box3(new THREE.Vector3().fromArray(s.min), new THREE.Vector3().fromArray(s.max)));
  }

  // ------------------------------------------------------------------ internals
  private enable(mode: SectionMode) {
    this.mode = mode;
    if (mode === 'box' && this.boxPlanes.length !== 6) this.boxPlanes = Array.from({ length: 6 }, () => new THREE.Plane());
    this.rebuild();
  }

  private update() {
    if (this.mode === 'box') {
      const b = this.box;
      // inward-facing normals: keep the inside of the box
      const defs: [THREE.Vector3, number][] = [
        [new THREE.Vector3(1, 0, 0), -b.min.x], [new THREE.Vector3(-1, 0, 0), b.max.x],
        [new THREE.Vector3(0, 1, 0), -b.min.y], [new THREE.Vector3(0, -1, 0), b.max.y],
        [new THREE.Vector3(0, 0, 1), -b.min.z], [new THREE.Vector3(0, 0, -1), b.max.z],
      ];
      defs.forEach(([n, c], i) => this.boxPlanes[i].set(n, c));
    }
    this.updateHelpers();
    this.updateCapPlanes();
    this.v.requestRender();
    this.v.emit('section');
  }

  private rebuild() {
    if (this.mode === 'off') return;
    this.v.setClipping(this.planes);
    this.buildHelpers();
    this.buildCaps();
    this.update();
  }

  // ---- helpers & handles
  private handleMat = new THREE.MeshBasicMaterial({ color: 0x2563eb, depthTest: false, transparent: true, opacity: 0.9 });

  private buildHelpers() {
    this.helpers.clear();
    this.handles = [];
    const size = this.v.bounds.getSize(new THREE.Vector3()).length() || 10;
    const r = size * (this.v.isMobile ? 0.018 : 0.012);
    const sphere = new THREE.SphereGeometry(1, 16, 12);
    if (this.mode === 'plane') {
      const quad = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), new THREE.MeshBasicMaterial({
        color: 0x2563eb, transparent: true, opacity: 0.08, side: THREE.DoubleSide, depthWrite: false,
      }));
      quad.name = 'quad';
      const outline = new THREE.LineSegments(new THREE.EdgesGeometry(new THREE.PlaneGeometry(1, 1)), new THREE.LineBasicMaterial({ color: 0x2563eb }));
      outline.name = 'outline';
      const h = new THREE.Mesh(sphere, this.handleMat);
      h.scale.setScalar(r);
      h.renderOrder = 999;
      h.userData.axis = -1;
      this.handles.push(h);
      this.helpers.add(quad, outline, h);
    } else if (this.mode === 'box') {
      const edges = new THREE.LineSegments(new THREE.EdgesGeometry(new THREE.BoxGeometry(1, 1, 1)), new THREE.LineBasicMaterial({ color: 0x2563eb }));
      edges.name = 'boxEdges';
      this.helpers.add(edges);
      for (let i = 0; i < 6; i++) {
        const h = new THREE.Mesh(sphere, this.handleMat);
        h.scale.setScalar(r);
        h.renderOrder = 999;
        h.userData.face = i;
        this.handles.push(h);
        this.helpers.add(h);
      }
    }
  }

  private updateHelpers() {
    if (this.mode === 'plane') {
      const c = this.plane.projectPoint(this.v.bounds.getCenter(new THREE.Vector3()), new THREE.Vector3());
      const size = this.v.bounds.getSize(new THREE.Vector3()).length() * 1.1;
      const q = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 0, 1), this.plane.normal);
      for (const name of ['quad', 'outline']) {
        const o = this.helpers.getObjectByName(name)!;
        o.position.copy(c); o.quaternion.copy(q); o.scale.set(size, size, 1);
      }
      this.handles[0]?.position.copy(c);
    } else if (this.mode === 'box') {
      const b = this.box, c = b.getCenter(new THREE.Vector3()), s = b.getSize(new THREE.Vector3());
      const e = this.helpers.getObjectByName('boxEdges')!;
      e.position.copy(c); e.scale.copy(s).max(new THREE.Vector3(1e-4, 1e-4, 1e-4));
      const pos = [[b.min.x, c.y, c.z], [b.max.x, c.y, c.z], [c.x, b.min.y, c.z], [c.x, b.max.y, c.z], [c.x, c.y, b.min.z], [c.x, c.y, b.max.z]];
      this.handles.forEach((h, i) => h.position.fromArray(pos[i]));
    }
  }

  private onDown = (e: PointerEvent) => {
    if (this.pickNext) {
      const hit = this.v.pick(e.clientX, e.clientY);
      if (hit) {
        this.pickNext = false;
        this.v.emit('section-pick', false);
        // keep what lies behind the tapped surface
        this.setPlane(hit.normal.clone().negate(), hit.point);
        e.stopImmediatePropagation();
      }
      return;
    }
    if (this.mode === 'off' || !this.handles.length) return;
    const rc = new THREE.Raycaster();
    rc.setFromCamera(this.v.ndc(e.clientX, e.clientY), this.v.camera);
    // enlarge hit area for touch
    const tol = this.v.isMobile ? 2.2 : 1.4;
    this.handles.forEach((h) => h.scale.multiplyScalar(tol));
    h_update(this.handles);
    const hit = rc.intersectObjects(this.handles, false)[0];
    this.handles.forEach((h) => h.scale.multiplyScalar(1 / tol));
    h_update(this.handles);
    if (!hit) return;
    const handle = hit.object as THREE.Mesh;
    const axis = this.mode === 'plane' ? this.plane.normal.clone() : AXES[Math.floor(handle.userData.face / 2)].clone();
    this.drag = { handle, axis, start: this.axisParam(e, handle.position, axis), origin: 0 };
    this.drag.origin = this.mode === 'plane' ? -this.plane.constant : this.boxValue(handle.userData.face);
    this.v.controls.enabled = false;
    this.v.setInteracting(true);
    e.stopImmediatePropagation();
    e.preventDefault();
  };

  private onMove = (e: PointerEvent) => {
    if (!this.drag) return;
    const d = this.drag;
    const t = this.axisParam(e, d.handle.position, d.axis) - d.start;
    if (this.mode === 'plane') this.plane.constant = -(d.origin + t);
    else this.setBoxValue(d.handle.userData.face, d.origin + t);
    this.update();
  };

  private onUp = () => {
    if (!this.drag) return;
    this.drag = null;
    this.v.controls.enabled = true;
    this.v.setInteracting(false);
  };

  /** Parameter along `axis` (through `origin`) closest to the pointer ray. */
  private axisParam(e: PointerEvent, origin: THREE.Vector3, axis: THREE.Vector3): number {
    const rc = new THREE.Raycaster();
    rc.setFromCamera(this.v.ndc(e.clientX, e.clientY), this.v.camera);
    const r = rc.ray;
    const w0 = origin.clone().sub(r.origin);
    const a = axis.dot(axis), b = axis.dot(r.direction), c = r.direction.dot(r.direction);
    const d = axis.dot(w0), ee = r.direction.dot(w0);
    const den = a * c - b * b;
    const s = Math.abs(den) < 1e-9 ? 0 : (b * ee - c * d) / den;
    // absolute coordinate along the (unit) axis – independent of the handle moving during the drag
    return axis.dot(origin) + s;
  }

  private boxValue(face: number) {
    const k = (['x', 'y', 'z'] as const)[Math.floor(face / 2)];
    return face % 2 ? this.box.max[k] : this.box.min[k];
  }

  private setBoxValue(face: number, val: number) {
    const k = (['x', 'y', 'z'] as const)[Math.floor(face / 2)];
    const gap = this.v.bounds.getSize(new THREE.Vector3())[k] * 0.005 + 1e-3;
    if (face % 2) this.box.max[k] = Math.max(val, this.box.min[k] + gap);
    else this.box.min[k] = Math.min(val, this.box.max[k] - gap);
  }

  // ---- stencil caps
  private capMeshes: THREE.Mesh[] = [];

  private clearCaps() {
    this.stencil.traverse((o: any) => { if (o.material && !o.userData.shared) o.material.dispose(); });
    this.stencil.clear();
    for (const r of [this.v.modelRoot, this.v.compareRoot]) r?.traverse((o: any) => {
      for (const c of [...o.children]) if (c.userData.stencilHelper) { o.remove(c); c.material.dispose(); }
    });
    this.capMeshes = [];
  }

  private buildCaps() {
    this.clearCaps();
    if (!this.caps || this.mode === 'off') return;
    const meshes: THREE.Mesh[] = [];
    this.v.modelRoot.traverse((o: any) => { if (o.isMesh && !o.userData.stencilHelper) meshes.push(o); });
    const planes = this.planes;
    if (meshes.length * planes.length > MAX_CAP_MESHES * (this.mode === 'plane' ? 6 : 1)) {
      this.v.emit('notice', 'Model has too many parts for filled section caps; showing open cut.');
      return;
    }
    const capSize = this.v.bounds.getSize(new THREE.Vector3()).length() * 2;
    planes.forEach((plane, i) => {
      const base = { depthWrite: false, depthTest: false, colorWrite: false, stencilWrite: true, stencilFunc: THREE.AlwaysStencilFunc, clippingPlanes: [plane] };
      const back = new THREE.MeshBasicMaterial({ ...base, side: THREE.BackSide, stencilFail: THREE.IncrementWrapStencilOp, stencilZFail: THREE.IncrementWrapStencilOp, stencilZPass: THREE.IncrementWrapStencilOp });
      const front = new THREE.MeshBasicMaterial({ ...base, side: THREE.FrontSide, stencilFail: THREE.DecrementWrapStencilOp, stencilZFail: THREE.DecrementWrapStencilOp, stencilZPass: THREE.DecrementWrapStencilOp });
      back.userData.noClip = front.userData.noClip = true;
      for (const m of meshes) {
        for (const mat of [back, front]) {
          let h: THREE.Mesh;
          if ((m as any).isInstancedMesh) {
            const im = m as unknown as THREE.InstancedMesh;
            const ih = new THREE.InstancedMesh(im.geometry, mat, im.count);
            ih.instanceMatrix = im.instanceMatrix;
            h = ih;
          } else h = new THREE.Mesh(m.geometry, mat);
          h.userData.stencilHelper = true;
          h.renderOrder = i + 1;
          h.raycast = () => {};
          m.add(h);
        }
      }
      const others = planes.filter((p) => p !== plane);
      const capMat = new THREE.MeshStandardMaterial({
        color: this.capColor, metalness: 0, roughness: 0.8, clippingPlanes: others, side: THREE.DoubleSide,
        stencilWrite: true, stencilRef: 0, stencilFunc: THREE.NotEqualStencilFunc,
        stencilFail: THREE.ReplaceStencilOp, stencilZFail: THREE.ReplaceStencilOp, stencilZPass: THREE.ReplaceStencilOp,
      });
      const cap = new THREE.Mesh(new THREE.PlaneGeometry(capSize, capSize), capMat);
      cap.userData.plane = plane;
      cap.renderOrder = i + 1.1;
      cap.raycast = () => {};
      cap.onAfterRender = (r) => r.clearStencil();
      this.capMeshes.push(cap);
      this.stencil.add(cap);
    });
  }

  private updateCapPlanes() {
    const c = this.v.bounds.getCenter(new THREE.Vector3());
    for (const cap of this.capMeshes) {
      const p: THREE.Plane = cap.userData.plane;
      p.coplanarPoint(cap.position);
      cap.position.copy(p.projectPoint(c, new THREE.Vector3()));
      cap.lookAt(cap.position.clone().sub(p.normal));
    }
  }
}

function h_update(hs: THREE.Object3D[]) { hs.forEach((h) => h.updateMatrixWorld(true)); }
