// Augmented reality: iOS Quick Look (USDZ generated in the browser) or WebXR immersive-ar (Android/Chrome).
import * as THREE from 'three';
import { USDZExporter } from 'three/addons/exporters/USDZExporter.js';
import type { Viewer } from './Viewer';

export const isIOS = () => /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

export async function arSupport(): Promise<'quicklook' | 'webxr' | null> {
  if (isIOS()) {
    const a = document.createElement('a');
    return a.relList?.supports?.('ar') ? 'quicklook' : 'quicklook';
  }
  try {
    if ((navigator as any).xr && (await (navigator as any).xr.isSessionSupported('immersive-ar'))) return 'webxr';
  } catch { /* unsupported */ }
  return null;
}

/** Clone the visible model with plain (uncompressed) materials so it can be exported to USDZ. */
function exportableClone(v: Viewer, scale: number): THREE.Group {
  const out = new THREE.Group();
  v.modelRoot.updateMatrixWorld(true);
  v.modelRoot.traverse((o: any) => {
    if (!o.isMesh || o.userData.stencilHelper) return;
    const src = Array.isArray(o.material) ? o.material[0] : o.material;
    if (!src.visible) return;
    const mat = new THREE.MeshStandardMaterial({ color: src.color?.clone() ?? new THREE.Color(0xdddddd), roughness: 0.8, metalness: 0, transparent: src.transparent, opacity: src.opacity });
    const geom = o.geometry.clone();
    // de-quantize attributes so exporters see plain floats
    for (const k of Object.keys(geom.attributes)) {
      const a = geom.attributes[k];
      if (!(a.array instanceof Float32Array)) {
        const f = new Float32Array(a.count * a.itemSize);
        for (let i = 0; i < a.count; i++) for (let j = 0; j < a.itemSize; j++) f[i * a.itemSize + j] = a.getComponent(i, j);
        geom.setAttribute(k, new THREE.BufferAttribute(f, a.itemSize));
      }
    }
    if (o.isInstancedMesh) {
      const im = new THREE.Matrix4();
      for (let i = 0; i < o.count; i++) {
        o.getMatrixAt(i, im);
        const m = new THREE.Mesh(geom, mat);
        m.applyMatrix4(new THREE.Matrix4().multiplyMatrices(o.matrixWorld, im));
        out.add(m);
      }
    } else {
      const m = new THREE.Mesh(geom, mat);
      m.applyMatrix4(o.matrixWorld);
      out.add(m);
    }
  });
  // Put the model's footprint center at the origin, resting on the ground.
  const box = new THREE.Box3().setFromObject(out);
  const c = box.getCenter(new THREE.Vector3());
  const wrap = new THREE.Group();
  out.position.set(-c.x, -box.min.y, -c.z);
  wrap.add(out);
  wrap.scale.setScalar(scale);
  return wrap;
}

/** Scale that fits the model into ~`meters` (tabletop) or 1 for real scale. */
export function arScale(v: Viewer, mode: 'table' | 'real') {
  if (mode === 'real') return 1;
  const s = v.bounds.getSize(new THREE.Vector3());
  return Math.min(1, 0.6 / Math.max(s.x, s.z, 0.01));
}

export async function openQuickLook(v: Viewer, name: string, mode: 'table' | 'real') {
  const exporter = new USDZExporter();
  const usdz = await exporter.parseAsync(exportableClone(v, arScale(v, mode)) as any);
  const url = URL.createObjectURL(new Blob([usdz], { type: 'model/vnd.usdz+zip' }));
  const a = document.createElement('a');
  a.rel = 'ar';
  a.href = url;
  a.download = name.replace(/[^\w-]+/g, '_') + '.usdz';
  a.appendChild(document.createElement('img'));
  document.body.appendChild(a);
  a.click();
  setTimeout(() => { a.remove(); URL.revokeObjectURL(url); }, 60_000);
}

/** WebXR AR: tap to place the model on a detected surface. */
export async function startWebXR(v: Viewer, mode: 'table' | 'real', overlay: HTMLElement, onEnd: () => void) {
  const xr = (navigator as any).xr;
  const session = await xr.requestSession('immersive-ar', { requiredFeatures: ['hit-test'], optionalFeatures: ['dom-overlay'], domOverlay: { root: overlay } });
  const renderer = v.renderer;
  const scene = new THREE.Scene();
  scene.add(new THREE.HemisphereLight(0xffffff, 0x888888, 2.5));
  const model = exportableClone(v, arScale(v, mode));
  model.visible = false;
  scene.add(model);
  const reticle = new THREE.Mesh(new THREE.RingGeometry(0.08, 0.1, 32).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0xffffff }));
  reticle.matrixAutoUpdate = false;
  reticle.visible = false;
  scene.add(reticle);
  const camera = new THREE.PerspectiveCamera();

  v.paused = true;
  renderer.xr.enabled = true;
  renderer.xr.setReferenceSpaceType('local');
  await renderer.xr.setSession(session);
  const refSpace = await session.requestReferenceSpace('viewer');
  const hitSource = await session.requestHitTestSource({ space: refSpace });

  session.addEventListener('select', () => {
    if (!reticle.visible) return;
    model.position.setFromMatrixPosition(reticle.matrix);
    model.visible = true;
  });
  const end = () => {
    renderer.setAnimationLoop(null);
    renderer.xr.enabled = false;
    v.paused = false;
    v.resize();
    onEnd();
  };
  session.addEventListener('end', end);

  renderer.setAnimationLoop((_t: number, frame: any) => {
    if (frame) {
      const results = frame.getHitTestResults(hitSource);
      const space = renderer.xr.getReferenceSpace();
      if (results.length && space) {
        const pose = results[0].getPose(space);
        reticle.visible = true;
        reticle.matrix.fromArray(pose.transform.matrix);
      } else reticle.visible = false;
    }
    renderer.render(scene, camera);
  });
  return () => session.end();
}
