// Core 3D viewer: renderer, cameras, progressive GLB loading, tags, scenes, picking/snapping, render modes, compare.
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { KTX2Loader } from 'three/addons/loaders/KTX2Loader.js';
import { MeshoptDecoder } from 'three/addons/libs/meshopt_decoder.module.js';
import { CSS2DRenderer } from 'three/addons/renderers/CSS2DRenderer.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { computeBoundsTree, disposeBoundsTree, acceleratedRaycast } from 'three-mesh-bvh';
import { basePath } from '../lib/api';
import { GLTFInstancedLines } from './gltfInstancedLines';

(THREE.BufferGeometry.prototype as any).computeBoundsTree = computeBoundsTree;
(THREE.BufferGeometry.prototype as any).disposeBoundsTree = disposeBoundsTree;
THREE.Mesh.prototype.raycast = acceleratedRaycast;

export interface SceneDef { name: string; description?: string; camera: CameraState | null; hidden_tags: string[] | null; thumb?: string | null }
export interface CameraState { eye: number[]; target: number[]; up?: number[]; perspective?: boolean; fov?: number; height?: number }
export interface Manifest {
  title?: string; units?: { length: string; precision: number }; bounds?: { min: number[]; max: number[] };
  tags?: { name: string; visible: boolean; color: string }[]; scenes?: SceneDef[];
  section_planes?: { name: string; point: number[]; normal: number[]; active: boolean }[];
  bom?: { name: string; description: string; count: number; size_mm: number[] }[]; stats?: Record<string, number>;
}
export type RenderMode = 'shaded' | 'monochrome' | 'xray' | 'wireframe';
export interface PickHit { point: THREE.Vector3; normal: THREE.Vector3; object: THREE.Object3D; snapped?: 'vertex' | 'midpoint' | 'edge' | 'face' }

type Listener = (...args: any[]) => void;

export class Viewer {
  readonly renderer: THREE.WebGLRenderer;
  readonly labels: CSS2DRenderer;
  readonly scene = new THREE.Scene();
  camera: THREE.PerspectiveCamera | THREE.OrthographicCamera;
  readonly persp: THREE.PerspectiveCamera;
  readonly ortho: THREE.OrthographicCamera;
  controls: OrbitControls;
  readonly modelRoot = new THREE.Group();
  readonly overlay = new THREE.Group(); // measurements, markup, gizmos (not clipped)
  compareRoot: THREE.Group | null = null;
  splitX = 0.5;
  readonly sun: THREE.DirectionalLight;
  readonly hemi: THREE.HemisphereLight;
  bounds = new THREE.Box3(new THREE.Vector3(-5, -5, -5), new THREE.Vector3(5, 5, 5));
  clippingPlanes: THREE.Plane[] = [];
  tagState = new Map<string, boolean>();
  renderMode: RenderMode = 'shaded';
  edgesVisible = true;
  shadows = false;
  /** Set by tools while they own pointer input. */
  continuous = false;
  /** Paused while an AR session owns the renderer. */
  paused = false;
  private dirty = true;
  private interacting = false;
  private idleTimer = 0;
  private listeners = new Map<string, Set<Listener>>();
  private loader: GLTFLoader;
  private ktx2: KTX2Loader;
  private raf = 0;
  private anim: { t0: number; dur: number; from: CameraState; to: CameraState; done?: () => void } | null = null;
  private readonly maxDpr: number;
  private readonly lowDpr: number;
  private ro: ResizeObserver;
  readonly raycaster = new THREE.Raycaster();
  readonly isMobile = matchMedia('(pointer: coarse)').matches;

  constructor(readonly container: HTMLElement) {
    this.renderer = new THREE.WebGLRenderer({ antialias: true, stencil: true, preserveDrawingBuffer: false, powerPreference: 'high-performance' });
    this.maxDpr = Math.min(window.devicePixelRatio || 1, this.isMobile ? 2 : 2);
    this.lowDpr = Math.min(1, this.maxDpr);
    this.renderer.setPixelRatio(this.maxDpr);
    this.renderer.localClippingEnabled = true;
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.NeutralToneMapping;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.renderer.domElement.className = 'viewer-canvas';
    container.appendChild(this.renderer.domElement);

    this.labels = new CSS2DRenderer();
    this.labels.domElement.className = 'viewer-labels';
    container.appendChild(this.labels.domElement);

    this.scene.background = new THREE.Color(0xeef1f5);
    const pmrem = new THREE.PMREMGenerator(this.renderer);
    this.scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    this.scene.environmentIntensity = 0.6;
    this.hemi = new THREE.HemisphereLight(0xffffff, 0xb0b4bb, 1.2);
    this.sun = new THREE.DirectionalLight(0xffffff, 1.6);
    this.sun.shadow.mapSize.set(2048, 2048);
    this.sun.shadow.bias = -0.0005;
    this.scene.add(this.hemi, this.sun, this.sun.target, this.modelRoot, this.overlay);

    this.persp = new THREE.PerspectiveCamera(45, 1, 0.05, 5000);
    this.ortho = new THREE.OrthographicCamera(-10, 10, 10, -10, -5000, 5000);
    this.camera = this.persp;
    this.persp.position.set(10, 8, 10);

    this.controls = this.makeControls();

    this.ktx2 = new KTX2Loader().setTranscoderPath(basePath + 'libs/basis/').detectSupport(this.renderer);
    this.loader = new GLTFLoader().setMeshoptDecoder(MeshoptDecoder).setKTX2Loader(this.ktx2);
    this.loader.register((parser) => new GLTFInstancedLines(parser) as any);

    this.ro = new ResizeObserver(() => this.resize());
    this.ro.observe(container);
    this.resize();
    this.renderer.domElement.addEventListener('dblclick', (e) => this.onDoubleTap(e));
    this.installDoubleTap();
    this.loop();
  }

  // ------------------------------------------------------------------ events
  on(ev: string, fn: Listener) { (this.listeners.get(ev) ?? this.listeners.set(ev, new Set()).get(ev)!).add(fn); return () => this.listeners.get(ev)!.delete(fn); }
  emit(ev: string, ...args: any[]) { this.listeners.get(ev)?.forEach((f) => f(...args)); }

  // ------------------------------------------------------------------ rendering
  requestRender() { this.dirty = true; }

  private makeControls() {
    const c = new OrbitControls(this.camera, this.renderer.domElement);
    c.enableDamping = true;
    c.dampingFactor = 0.12;
    c.zoomToCursor = true;
    c.screenSpacePanning = true;
    c.touches = { ONE: THREE.TOUCH.ROTATE, TWO: THREE.TOUCH.DOLLY_PAN };
    c.mouseButtons = { LEFT: THREE.MOUSE.ROTATE, MIDDLE: THREE.MOUSE.PAN, RIGHT: THREE.MOUSE.PAN };
    c.addEventListener('change', () => { this.requestRender(); this.emit('camera'); });
    c.addEventListener('start', () => this.setInteracting(true));
    c.addEventListener('end', () => this.setInteracting(false));
    return c;
  }

  /** Lower resolution while moving, full resolution when still: smooth on phones, crisp when stopped. */
  setInteracting(on: boolean) {
    clearTimeout(this.idleTimer);
    if (on) {
      if (!this.interacting) { this.interacting = true; this.renderer.setPixelRatio(this.lowDpr); this.resize(); }
    } else {
      this.idleTimer = window.setTimeout(() => { this.interacting = false; this.renderer.setPixelRatio(this.maxDpr); this.resize(); }, 250);
    }
  }

  resize() {
    const w = this.container.clientWidth || 1;
    const h = this.container.clientHeight || 1;
    this.renderer.setSize(w, h, false);
    this.labels.setSize(w, h);
    this.persp.aspect = w / h;
    this.persp.updateProjectionMatrix();
    this.updateOrthoFrustum();
    this.requestRender();
  }

  private loop = () => {
    this.raf = requestAnimationFrame(this.loop);
    if (this.paused) return;
    if (this.anim) this.stepAnim();
    const damping = this.controls.enabled && this.controls.update();
    this.emit('tick');
    if (this.dirty || damping || this.continuous || this.anim) {
      this.dirty = false;
      this.render();
    }
  };

  render() {
    const r = this.renderer;
    if (this.compareRoot) {
      const w = this.container.clientWidth, h = this.container.clientHeight;
      const x = Math.round(w * this.splitX);
      r.setScissorTest(true);
      this.compareRoot.visible = false; this.modelRoot.visible = true;
      r.setScissor(0, 0, x, h); r.setViewport(0, 0, w, h); r.render(this.scene, this.camera);
      this.compareRoot.visible = true; this.modelRoot.visible = false;
      r.setScissor(x, 0, w - x, h); r.render(this.scene, this.camera);
      this.modelRoot.visible = true;
      r.setScissorTest(false);
    } else {
      r.render(this.scene, this.camera);
    }
    this.labels.render(this.scene, this.camera);
    this.emit('render');
  }

  /** PNG/JPEG of the current view (for markups and thumbnails). */
  snapshot(type = 'image/jpeg', quality = 0.85, maxW = 1600): string {
    this.render();
    const src = this.renderer.domElement;
    const scale = Math.min(1, maxW / src.width);
    const c = document.createElement('canvas');
    c.width = Math.round(src.width * scale);
    c.height = Math.round(src.height * scale);
    c.getContext('2d')!.drawImage(src, 0, 0, c.width, c.height);
    return c.toDataURL(type, quality);
  }

  // ------------------------------------------------------------------ loading
  async parse(buffer: ArrayBuffer): Promise<THREE.Group> {
    const gltf = await this.loader.parseAsync(buffer, '');
    return gltf.scene;
  }

  /** Replace the displayed model (used for preview → full swap and version switch). */
  setModel(root: THREE.Group, opts: { keepCamera?: boolean } = {}) {
    this.disposeGroup(this.modelRoot);
    this.modelRoot.clear();
    this.prepare(root);
    this.modelRoot.add(root);
    this.modelRoot.updateMatrixWorld(true);
    this.bounds = new THREE.Box3().setFromObject(this.modelRoot);
    if (this.bounds.isEmpty()) this.bounds.set(new THREE.Vector3(-1, -1, -1), new THREE.Vector3(1, 1, 1));
    const size = this.bounds.getSize(new THREE.Vector3()).length();
    this.persp.near = Math.max(0.01, size / 5000);
    this.persp.far = size * 20 + 100;
    this.persp.updateProjectionMatrix();
    this.placeSun();
    this.applyTags();
    this.applyRenderMode();
    this.applyClipping();
    if (!opts.keepCamera) this.fit();
    this.emit('model', root);
    this.requestRender();
  }

  setCompareModel(root: THREE.Group | null) {
    if (this.compareRoot) { this.disposeGroup(this.compareRoot); this.scene.remove(this.compareRoot); }
    this.compareRoot = null;
    if (root) {
      this.prepare(root);
      this.compareRoot = new THREE.Group();
      this.compareRoot.add(root);
      this.scene.add(this.compareRoot);
      this.applyTags();
      this.applyRenderMode();
      this.applyClipping();
    }
    this.requestRender();
  }

  private prepare(root: THREE.Object3D) {
    root.traverse((o: any) => {
      if (o.isMesh) {
        o.geometry.computeBoundsTree?.();
        o.castShadow = o.receiveShadow = true;
        const mats: THREE.Material[] = Array.isArray(o.material) ? o.material : [o.material];
        for (const m of mats) {
          m.side = THREE.DoubleSide;
          m.userData.orig ??= { color: (m as any).color?.clone(), map: (m as any).map, opacity: m.opacity, transparent: m.transparent, depthWrite: m.depthWrite };
        }
      }
      if (o.isLine || o.isLineSegments) {
        o.userData.isEdge = true;
        o.raycast = () => {}; // edges are snapped via faces, not picked
        o.renderOrder = 1;
        const m = o.material as THREE.LineBasicMaterial;
        m.userData.isEdges = true;
        m.userData.orig ??= { color: m.color.clone(), opacity: m.opacity, transparent: m.transparent };
      }
    });
  }

  private disposeGroup(g: THREE.Object3D) {
    g.traverse((o: any) => {
      if (o.geometry) { o.geometry.disposeBoundsTree?.(); o.geometry.dispose(); }
      const mats = o.material ? (Array.isArray(o.material) ? o.material : [o.material]) : [];
      for (const m of mats) { for (const v of Object.values(m)) if ((v as any)?.isTexture) (v as THREE.Texture).dispose(); m.dispose(); }
    });
  }

  private roots(): THREE.Object3D[] { return this.compareRoot ? [this.modelRoot, this.compareRoot] : [this.modelRoot]; }

  forEachMaterial(fn: (m: THREE.Material, o: THREE.Object3D) => void) {
    for (const r of this.roots()) r.traverse((o: any) => {
      if (!o.material) return;
      for (const m of Array.isArray(o.material) ? o.material : [o.material]) fn(m, o);
    });
  }

  // ------------------------------------------------------------------ camera
  fit(box = this.bounds, animate = false) {
    const center = box.getCenter(new THREE.Vector3());
    const r = box.getBoundingSphere(new THREE.Sphere()).radius || 1;
    const dir = new THREE.Vector3(1, 0.75, 1).normalize();
    const dist = r / Math.sin(THREE.MathUtils.degToRad(this.persp.fov / 2)) * 1.05;
    const to: CameraState = { eye: center.clone().addScaledVector(dir, dist).toArray(), target: center.toArray(), up: [0, 1, 0] };
    animate ? this.animateTo(to) : this.setCameraState(to);
  }

  standardView(view: 'top' | 'front' | 'back' | 'left' | 'right' | 'iso') {
    const c = this.bounds.getCenter(new THREE.Vector3());
    const r = this.bounds.getBoundingSphere(new THREE.Sphere()).radius || 1;
    const d = r / Math.sin(THREE.MathUtils.degToRad(this.persp.fov / 2)) * 1.05;
    const dirs: Record<string, number[]> = { top: [0, 1, 0.0001], front: [0, 0, 1], back: [0, 0, -1], left: [-1, 0, 0], right: [1, 0, 0], iso: [1, 0.8, 1] };
    const dir = new THREE.Vector3(...dirs[view]).normalize();
    this.animateTo({ eye: c.clone().addScaledVector(dir, d).toArray(), target: c.toArray(), up: view === 'top' ? [0, 0, -1] : [0, 1, 0] });
  }

  getCameraState(): CameraState {
    const cam = this.camera;
    return {
      eye: cam.position.toArray(), target: this.controls.target.toArray(), up: cam.up.toArray(),
      perspective: cam === this.persp, fov: this.persp.fov, height: cam === this.ortho ? (this.ortho.top - this.ortho.bottom) / this.ortho.zoom : undefined,
    };
  }

  setCameraState(s: CameraState) {
    if (s.perspective === false) this.setProjection(false); else if (s.perspective === true) this.setProjection(true);
    this.camera.position.fromArray(s.eye);
    this.controls.target.fromArray(s.target);
    this.camera.up.fromArray(s.up ?? [0, 1, 0]);
    if (s.fov && this.camera === this.persp) { this.persp.fov = THREE.MathUtils.clamp(s.fov, 10, 100); this.persp.updateProjectionMatrix(); }
    if (s.height && this.camera === this.ortho) { this.ortho.zoom = 1; this.orthoHeight = s.height; this.updateOrthoFrustum(); }
    this.camera.lookAt(this.controls.target);
    this.controls.update();
    this.requestRender();
    this.emit('camera');
  }

  animateTo(to: CameraState, dur = 900, done?: () => void) {
    if (to.perspective !== undefined && (to.perspective !== (this.camera === this.persp))) { this.setCameraState(to); done?.(); return; }
    this.anim = { t0: performance.now(), dur, from: this.getCameraState(), to, done };
  }

  private stepAnim() {
    const a = this.anim!;
    const t = Math.min(1, (performance.now() - a.t0) / a.dur);
    const k = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
    const lerp = (x: number[], y: number[]) => x.map((v, i) => v + (y[i] - v) * k);
    this.camera.position.fromArray(lerp(a.from.eye, a.to.eye));
    this.controls.target.fromArray(lerp(a.from.target, a.to.target));
    this.camera.up.fromArray(lerp(a.from.up ?? [0, 1, 0], a.to.up ?? [0, 1, 0])).normalize();
    if (a.to.fov && this.camera === this.persp) { this.persp.fov = a.from.fov! + (a.to.fov - a.from.fov!) * k; this.persp.updateProjectionMatrix(); }
    this.camera.lookAt(this.controls.target);
    this.emit('camera');
    if (t >= 1) { this.anim = null; this.controls.update(); a.done?.(); }
  }

  private orthoHeight = 10;
  setProjection(perspective: boolean) {
    const want = perspective ? this.persp : this.ortho;
    if (want === this.camera) return;
    const target = this.controls.target.clone();
    if (!perspective) {
      const dist = this.persp.position.distanceTo(target);
      this.orthoHeight = 2 * dist * Math.tan(THREE.MathUtils.degToRad(this.persp.fov / 2));
      this.ortho.zoom = 1;
      this.updateOrthoFrustum();
    }
    want.position.copy(this.camera.position);
    want.up.copy(this.camera.up);
    this.camera = want;
    this.controls.dispose();
    this.controls = this.makeControls();
    this.controls.target.copy(target);
    this.camera.lookAt(target);
    this.controls.update();
    this.emit('projection', perspective);
    this.requestRender();
  }

  private updateOrthoFrustum() {
    const aspect = (this.container.clientWidth || 1) / (this.container.clientHeight || 1);
    const h = this.orthoHeight / 2;
    this.ortho.top = h; this.ortho.bottom = -h; this.ortho.left = -h * aspect; this.ortho.right = h * aspect;
    this.ortho.near = -this.bounds.getSize(new THREE.Vector3()).length() * 4 - 100;
    this.ortho.far = -this.ortho.near;
    this.ortho.updateProjectionMatrix();
  }

  // Double-tap / double-click: orbit around the tapped point and move closer.
  private installDoubleTap() {
    let last = 0, lx = 0, ly = 0;
    this.renderer.domElement.addEventListener('pointerup', (e) => {
      if (e.pointerType !== 'touch') return;
      const now = performance.now();
      if (now - last < 300 && Math.hypot(e.clientX - lx, e.clientY - ly) < 30) { this.onDoubleTap(e); last = 0; } else { last = now; lx = e.clientX; ly = e.clientY; }
    });
  }

  private onDoubleTap(e: MouseEvent | PointerEvent) {
    if (!this.controls.enabled) { this.emit('doubletap', e); return; }
    const hit = this.pick(e.clientX, e.clientY);
    if (!hit) return;
    const eye = this.camera.position.clone();
    const newEye = eye.clone().lerp(hit.point, 0.5);
    this.animateTo({ eye: newEye.toArray(), target: hit.point.toArray(), up: this.camera.up.toArray() }, 600);
  }

  // ------------------------------------------------------------------ picking
  ndc(clientX: number, clientY: number) {
    const r = this.renderer.domElement.getBoundingClientRect();
    return new THREE.Vector2(((clientX - r.left) / r.width) * 2 - 1, -((clientY - r.top) / r.height) * 2 + 1);
  }

  toScreen(p: THREE.Vector3) {
    const v = p.clone().project(this.camera);
    const r = this.renderer.domElement.getBoundingClientRect();
    return new THREE.Vector2((v.x + 1) / 2 * r.width + r.left, (1 - v.y) / 2 * r.height + r.top);
  }

  private isClipped(p: THREE.Vector3) {
    return this.clippingPlanes.some((pl) => pl.distanceToPoint(p) < -1e-4);
  }

  /** Raycast the visible, unclipped model. */
  pick(clientX: number, clientY: number, snap = false): PickHit | null {
    this.raycaster.setFromCamera(this.ndc(clientX, clientY), this.camera);
    (this.raycaster as any).firstHitOnly = false;
    const hits = this.raycaster.intersectObjects(this.roots().filter((r) => r.visible), true);
    for (const h of hits) {
      const o: any = h.object;
      if (!o.isMesh || !this.visibleInTree(o) || this.isClipped(h.point)) continue;
      const mat = Array.isArray(o.material) ? o.material[h.face?.materialIndex ?? 0] : o.material;
      if (mat && !mat.visible) continue;
      const normal = (h.face?.normal ?? new THREE.Vector3(0, 1, 0)).clone();
      const nm = new THREE.Matrix3().getNormalMatrix(o.matrixWorld);
      if (o.isInstancedMesh && h.instanceId !== undefined) {
        const im = new THREE.Matrix4(); o.getMatrixAt(h.instanceId, im);
        nm.getNormalMatrix(new THREE.Matrix4().multiplyMatrices(o.matrixWorld, im));
      }
      normal.applyMatrix3(nm).normalize();
      if (normal.dot(this.raycaster.ray.direction) > 0) normal.negate();
      const res: PickHit = { point: h.point.clone(), normal, object: o, snapped: 'face' };
      if (snap && h.face) this.snapHit(res, h, clientX, clientY);
      return res;
    }
    return null;
  }

  private visibleInTree(o: THREE.Object3D) {
    for (let p: THREE.Object3D | null = o; p; p = p.parent) if (!p.visible) return false;
    return true;
  }

  /** Snap to the hit triangle's vertices, edge midpoints or edges when within ~14px on screen. */
  private snapHit(res: PickHit, h: THREE.Intersection, cx: number, cy: number) {
    const o: any = h.object;
    const pos = o.geometry.attributes.position;
    const m = o.matrixWorld.clone();
    if (o.isInstancedMesh && h.instanceId !== undefined) { const im = new THREE.Matrix4(); o.getMatrixAt(h.instanceId, im); m.multiply(im); }
    const f = h.face!;
    const v = [f.a, f.b, f.c].map((i) => new THREE.Vector3().fromBufferAttribute(pos, i).applyMatrix4(m));
    const mouse = new THREE.Vector2(cx, cy);
    const tol = this.isMobile ? 22 : 14;
    let best: { p: THREE.Vector3; d: number; kind: PickHit['snapped'] } | null = null;
    const consider = (p: THREE.Vector3, kind: PickHit['snapped'], bias = 0) => {
      const d = this.toScreen(p).distanceTo(mouse) + bias;
      if (d < tol && (!best || d < best.d)) best = { p, d, kind };
    };
    v.forEach((p) => consider(p, 'vertex'));
    for (let i = 0; i < 3; i++) consider(v[i].clone().add(v[(i + 1) % 3]).multiplyScalar(0.5), 'midpoint', 2);
    if (!best) {
      for (let i = 0; i < 3; i++) {
        const line = new THREE.Line3(v[i], v[(i + 1) % 3]);
        consider(line.closestPointToPoint(res.point, true, new THREE.Vector3()), 'edge', 4);
      }
    }
    if (best) { res.point.copy((best as any).p); res.snapped = (best as any).kind; }
  }

  // ------------------------------------------------------------------ tags
  /** Tags come from material extras written by the SkpShare plugin. */
  listTags(): string[] {
    const s = new Set<string>();
    this.forEachMaterial((m) => { if (m.userData.tag) s.add(m.userData.tag); });
    return [...s].sort((a, b) => (a === 'Untagged' ? -1 : b === 'Untagged' ? 1 : a.localeCompare(b)));
  }

  initTagState(manifest: Manifest | null) {
    this.tagState.clear();
    this.forEachMaterial((m) => {
      const t = m.userData.tag;
      if (t && !this.tagState.has(t)) this.tagState.set(t, m.userData.tagVisible !== false);
    });
    manifest?.tags?.forEach((t) => { if (this.tagState.has(t.name)) this.tagState.set(t.name, t.visible); });
    this.applyTags();
  }

  setTagVisible(tag: string, on: boolean) { this.tagState.set(tag, on); this.applyTags(); }

  applyTags() {
    this.forEachMaterial((m) => {
      const t = m.userData.tag;
      const tagOn = t ? this.tagState.get(t) !== false : true;
      m.visible = tagOn && (!m.userData.isEdges || this.edgesVisible);
    });
    this.requestRender();
  }

  setEdges(on: boolean) {
    this.edgesVisible = on;
    this.applyTags();
  }

  // ------------------------------------------------------------------ scenes
  goToScene(s: SceneDef, animate = true) {
    if (s.hidden_tags) {
      const hidden = new Set(s.hidden_tags);
      for (const t of this.tagState.keys()) this.tagState.set(t, !hidden.has(t));
      this.applyTags();
      this.emit('tags');
    }
    if (s.camera) {
      const to = { ...s.camera, up: s.camera.up ?? [0, 1, 0] };
      animate ? this.animateTo(to) : this.setCameraState(to);
    }
  }

  // ------------------------------------------------------------------ appearance
  setRenderMode(mode: RenderMode) { this.renderMode = mode; this.applyRenderMode(); }

  applyRenderMode() {
    const mode = this.renderMode;
    this.forEachMaterial((m: any, o: any) => {
      const orig = m.userData.orig;
      if (!orig) return;
      if (o.userData.isEdge) {
        m.color.copy(orig.color);
        m.opacity = mode === 'xray' ? 0.35 : orig.opacity;
        m.transparent = mode === 'xray' || orig.transparent;
        m.needsUpdate = true;
        return;
      }
      m.wireframe = mode === 'wireframe';
      if (m.color) m.color.copy(mode === 'monochrome' ? new THREE.Color(0xf2f2f2) : orig.color);
      m.map = mode === 'monochrome' ? null : orig.map;
      if (mode === 'xray') { m.transparent = true; m.opacity = 0.18; m.depthWrite = false; }
      else { m.transparent = orig.transparent; m.opacity = orig.opacity; m.depthWrite = orig.depthWrite; }
      m.needsUpdate = true;
    });
    this.requestRender();
  }

  setBackground(color: string) { (this.scene.background as THREE.Color).set(color); this.requestRender(); }

  setShadows(on: boolean) {
    this.shadows = on;
    this.renderer.shadowMap.enabled = on;
    this.sun.castShadow = on;
    this.forEachMaterial((m) => (m.needsUpdate = true));
    this.requestRender();
  }

  sunAngles = { azimuth: 135, elevation: 45 };
  setSun(azimuth: number, elevation: number) { this.sunAngles = { azimuth, elevation }; this.placeSun(); }

  private placeSun() {
    const c = this.bounds.getCenter(new THREE.Vector3());
    const r = this.bounds.getBoundingSphere(new THREE.Sphere()).radius || 10;
    const az = THREE.MathUtils.degToRad(this.sunAngles.azimuth), el = THREE.MathUtils.degToRad(this.sunAngles.elevation);
    this.sun.position.set(c.x + Math.cos(el) * Math.sin(az) * r * 2, c.y + Math.sin(el) * r * 2, c.z + Math.cos(el) * Math.cos(az) * r * 2);
    this.sun.target.position.copy(c);
    const cam = this.sun.shadow.camera as THREE.OrthographicCamera;
    cam.left = -r; cam.right = r; cam.top = r; cam.bottom = -r; cam.near = 0.1; cam.far = r * 5;
    cam.updateProjectionMatrix();
    this.requestRender();
  }

  // ------------------------------------------------------------------ clipping (driven by Section tool)
  setClipping(planes: THREE.Plane[]) { this.clippingPlanes = planes; this.applyClipping(); }

  applyClipping() {
    this.forEachMaterial((m: any) => {
      if (m.userData.noClip) return;
      m.clippingPlanes = this.clippingPlanes.length ? this.clippingPlanes : null;
      m.needsUpdate = true;
    });
    this.requestRender();
  }

  dispose() {
    cancelAnimationFrame(this.raf);
    this.ro.disconnect();
    this.controls.dispose();
    this.disposeGroup(this.modelRoot);
    if (this.compareRoot) this.disposeGroup(this.compareRoot);
    this.ktx2.dispose();
    this.renderer.dispose();
    this.renderer.domElement.remove();
    this.labels.domElement.remove();
  }
}
