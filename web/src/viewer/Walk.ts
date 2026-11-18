// First-person walk mode: WASD + drag-to-look on desktop; virtual joystick + drag/gyroscope look on phones.
import * as THREE from 'three';
import type { Viewer } from './Viewer';

export class WalkControls {
  active = false;
  eyeHeight = 1.6;
  speed = 1.4; // m/s, scaled by the UI slider
  gravity = true;
  gyro = false;
  private yaw = 0;
  private pitch = 0;
  private move = new THREE.Vector2(); // joystick: x strafe, y forward (-1..1)
  private vertical = 0;
  private keys = new Set<string>();
  private look: { id: number; x: number; y: number } | null = null;
  private last = performance.now();
  private unsub: (() => void) | null = null;
  private gyroQ = new THREE.Quaternion();
  private gyroYawOffset = 0;
  private hasGyroData = false;
  private down = new THREE.Raycaster();

  constructor(private v: Viewer) {}

  async enable() {
    if (this.active) return;
    this.active = true;
    const v = this.v;
    v.setProjection(true);
    v.controls.enabled = false;
    v.continuous = true;
    const e = new THREE.Euler().setFromQuaternion(v.camera.quaternion, 'YXZ');
    this.yaw = e.y;
    this.pitch = THREE.MathUtils.clamp(e.x, -1.2, 1.2);
    // Scale speed to the model: tiny models should not be crossed in a tenth of a second.
    const size = v.bounds.getSize(new THREE.Vector3());
    this.speed = THREE.MathUtils.clamp(Math.max(size.x, size.z) / 25, 0.6, 6);
    if (this.gravity) this.dropToFloor(true);
    const el = v.renderer.domElement;
    el.addEventListener('pointerdown', this.onDown);
    window.addEventListener('pointermove', this.onMove);
    window.addEventListener('pointerup', this.onUp);
    window.addEventListener('keydown', this.onKey);
    window.addEventListener('keyup', this.onKey);
    this.unsub = v.on('tick', this.tick);
    this.unsubTap = v.on('doubletap', (ev: PointerEvent) => this.teleport(ev));
    this.last = performance.now();
  }

  private unsubTap: (() => void) | null = null;

  disable() {
    if (!this.active) return;
    this.active = false;
    const v = this.v;
    const el = v.renderer.domElement;
    el.removeEventListener('pointerdown', this.onDown);
    window.removeEventListener('pointermove', this.onMove);
    window.removeEventListener('pointerup', this.onUp);
    window.removeEventListener('keydown', this.onKey);
    window.removeEventListener('keyup', this.onKey);
    this.unsub?.(); this.unsubTap?.();
    this.setGyro(false);
    v.continuous = false;
    // Put the orbit target in front of the camera so orbiting continues naturally.
    const dir = v.camera.getWorldDirection(new THREE.Vector3());
    v.controls.target.copy(v.camera.position).addScaledVector(dir, 3);
    v.camera.up.set(0, 1, 0);
    v.controls.enabled = true;
    v.controls.update();
    v.requestRender();
  }

  setJoystick(x: number, y: number) { this.move.set(x, y); }
  setVertical(dir: number) { this.vertical = dir; }

  async setGyro(on: boolean): Promise<boolean> {
    if (on) {
      const DOE: any = (window as any).DeviceOrientationEvent;
      if (!DOE) return false;
      if (typeof DOE.requestPermission === 'function') {
        try { if ((await DOE.requestPermission()) !== 'granted') return false; } catch { return false; }
      }
      this.hasGyroData = false;
      window.addEventListener('deviceorientation', this.onOrient);
      this.gyro = true;
    } else {
      window.removeEventListener('deviceorientation', this.onOrient);
      this.gyro = false;
    }
    return true;
  }

  private onOrient = (e: DeviceOrientationEvent) => {
    if (e.alpha === null) return;
    const deg = THREE.MathUtils.degToRad;
    const orient = deg((screen.orientation?.angle ?? (window as any).orientation ?? 0) as number);
    const euler = new THREE.Euler(deg(e.beta ?? 0), deg(e.alpha ?? 0), -deg(e.gamma ?? 0), 'YXZ');
    const q = new THREE.Quaternion().setFromEuler(euler);
    q.multiply(new THREE.Quaternion(-Math.sqrt(0.5), 0, 0, Math.sqrt(0.5))); // camera looks out the back of the device
    q.multiply(new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 0, 1), -orient));
    if (!this.hasGyroData) {
      // Align the device's current heading with the current view direction.
      const e2 = new THREE.Euler().setFromQuaternion(q, 'YXZ');
      this.gyroYawOffset = this.yaw - e2.y;
      this.hasGyroData = true;
    }
    this.gyroQ.copy(q);
  };

  private onDown = (e: PointerEvent) => {
    if (this.look || (e.target as HTMLElement) !== this.v.renderer.domElement) return;
    this.look = { id: e.pointerId, x: e.clientX, y: e.clientY };
    this.v.setInteracting(true);
  };

  private onMove = (e: PointerEvent) => {
    if (!this.look || e.pointerId !== this.look.id) return;
    const k = this.v.isMobile ? 0.005 : 0.0035;
    const dx = e.clientX - this.look.x, dy = e.clientY - this.look.y;
    this.look.x = e.clientX; this.look.y = e.clientY;
    if (this.gyro) this.gyroYawOffset += dx * k;
    else {
      this.yaw += dx * k;
      this.pitch = THREE.MathUtils.clamp(this.pitch + dy * k, -1.45, 1.45);
    }
  };

  private onUp = (e: PointerEvent) => {
    if (this.look && e.pointerId === this.look.id) { this.look = null; this.v.setInteracting(false); }
  };

  private onKey = (e: KeyboardEvent) => {
    if ((e.target as HTMLElement)?.closest?.('input,textarea')) return;
    const k = e.key.toLowerCase();
    if (['w', 'a', 's', 'd', 'q', 'e', 'arrowup', 'arrowdown', 'arrowleft', 'arrowright', 'shift'].includes(k)) {
      e.type === 'keydown' ? this.keys.add(k) : this.keys.delete(k);
      e.preventDefault();
    }
  };

  private teleport(e: PointerEvent) {
    const hit = this.v.pick(e.clientX, e.clientY);
    if (!hit) return;
    const p = hit.point.clone();
    if (hit.normal.y > 0.6) p.y += this.eyeHeight; // tapped a floor
    else p.addScaledVector(hit.normal, 0.5);
    const cam = this.v.camera;
    const from = cam.position.clone();
    const t0 = performance.now();
    const step = () => {
      const t = Math.min(1, (performance.now() - t0) / 500);
      cam.position.lerpVectors(from, p, 1 - Math.pow(1 - t, 3));
      if (t < 1) requestAnimationFrame(step);
    };
    step();
  }

  private dropToFloor(snap: boolean) {
    const cam = this.v.camera;
    this.down.set(cam.position.clone().add(new THREE.Vector3(0, 0.4, 0)), new THREE.Vector3(0, -1, 0));
    this.down.far = 50;
    const hit = this.v.raycaster;
    hit.set(this.down.ray.origin, this.down.ray.direction);
    hit.far = 50;
    const roots = [this.v.modelRoot];
    const h = hit.intersectObjects(roots, true).find((x: any) => x.object.isMesh && x.object.material?.visible !== false);
    hit.far = Infinity;
    if (!h) return;
    const target = h.point.y + this.eyeHeight;
    cam.position.y = snap ? target : THREE.MathUtils.lerp(cam.position.y, target, 0.25);
  }

  private blocked(dir: THREE.Vector3, dist: number): boolean {
    const rc = this.v.raycaster;
    const cam = this.v.camera;
    for (const yOff of [0, -this.eyeHeight + 0.5]) {
      rc.set(cam.position.clone().add(new THREE.Vector3(0, yOff, 0)), dir);
      rc.far = dist + 0.3;
      const h = rc.intersectObjects([this.v.modelRoot], true).find((x: any) => x.object.isMesh && x.object.material?.visible !== false);
      rc.far = Infinity;
      if (h) return true;
    }
    return false;
  }

  private tick = () => {
    const now = performance.now();
    const dt = Math.min(0.1, (now - this.last) / 1000);
    this.last = now;
    const cam = this.v.camera;

    if (this.gyro && this.hasGyroData) {
      const yawQ = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), this.gyroYawOffset);
      cam.quaternion.copy(yawQ).multiply(this.gyroQ);
      const e = new THREE.Euler().setFromQuaternion(cam.quaternion, 'YXZ');
      this.yaw = e.y;
    } else {
      cam.quaternion.setFromEuler(new THREE.Euler(this.pitch, this.yaw, 0, 'YXZ'));
    }

    let fwd = this.move.y, side = this.move.x, up = this.vertical;
    const k = this.keys;
    if (k.has('w') || k.has('arrowup')) fwd += 1;
    if (k.has('s') || k.has('arrowdown')) fwd -= 1;
    if (k.has('d')) side += 1;
    if (k.has('a')) side -= 1;
    if (k.has('arrowleft')) this.yaw += dt * 1.6;
    if (k.has('arrowright')) this.yaw -= dt * 1.6;
    if (k.has('e')) up += 1;
    if (k.has('q')) up -= 1;
    const run = k.has('shift') ? 2.5 : 1;

    if (fwd || side || up) {
      const forward = new THREE.Vector3(-Math.sin(this.yaw), 0, -Math.cos(this.yaw));
      const right = new THREE.Vector3(Math.cos(this.yaw), 0, -Math.sin(this.yaw));
      const step = new THREE.Vector3().addScaledVector(forward, fwd).addScaledVector(right, side);
      const len = Math.min(1, step.length());
      if (len > 0) {
        step.normalize();
        const dist = len * this.speed * run * dt;
        if (!this.blocked(step, dist)) cam.position.addScaledVector(step, dist);
      }
      if (up) {
        cam.position.y += up * this.speed * dt;
        if (this.gravity && up) this.eyeHeight = Math.max(0.3, this.eyeHeight + up * this.speed * dt);
      }
      this.v.emit('camera');
    }
    if (this.gravity) this.dropToFloor(false);
  };
}
