// GLTFLoader plugin: EXT_mesh_gpu_instancing for nodes that contain LINE primitives (SketchUp edges).
// three.js' built-in handler only supports triangles and leaves such nodes un-instanced, which puts the
// edges of repeated components (and gltfpack's dequantization transform) in the wrong place.
// Triangles become InstancedMesh; lines are expanded once per instance into a single LineSegments.
import * as THREE from 'three';

const EXT = 'EXT_mesh_gpu_instancing';

export class GLTFInstancedLines {
  name = 'SKPSHARE_instanced_lines';
  constructor(private parser: any) {}

  createNodeMesh(nodeIndex: number) {
    const json = this.parser.json;
    const nodeDef = json.nodes[nodeIndex];
    if (!nodeDef.extensions?.[EXT] || nodeDef.mesh === undefined) return null;
    const meshDef = json.meshes[nodeDef.mesh];
    const hasLines = meshDef.primitives.some((p: any) => p.mode === 1 || p.mode === 2 || p.mode === 3);
    if (!hasLines) return null; // the built-in plugin handles pure triangle meshes

    const attrsDef = nodeDef.extensions[EXT].attributes as Record<string, number>;
    const attrs: Record<string, THREE.BufferAttribute> = {};
    const pending: Promise<any>[] = Object.entries(attrsDef).map(([k, i]) =>
      this.parser.getDependency('accessor', i).then((a: THREE.BufferAttribute) => (attrs[k] = a)));
    pending.push(this.parser.createNodeMesh(nodeIndex));

    return Promise.all(pending).then((res) => {
      const node: THREE.Object3D = res.pop();
      const count = Object.values(attrs)[0]?.count ?? 0;
      const matrices: THREE.Matrix4[] = [];
      const p = new THREE.Vector3(), q = new THREE.Quaternion(), s = new THREE.Vector3();
      for (let i = 0; i < count; i++) {
        p.set(0, 0, 0); q.set(0, 0, 0, 1); s.set(1, 1, 1);
        if (attrs.TRANSLATION) p.fromBufferAttribute(attrs.TRANSLATION, i);
        if (attrs.ROTATION) q.fromBufferAttribute(attrs.ROTATION as any, i);
        if (attrs.SCALE) s.fromBufferAttribute(attrs.SCALE, i);
        matrices.push(new THREE.Matrix4().compose(p, q, s));
      }
      const parts: THREE.Object3D[] = (node as any).isGroup ? [...node.children] : [node];
      const out: THREE.Object3D[] = parts.map((o: any) => {
        if (o.isMesh) {
          const im = new THREE.InstancedMesh(o.geometry, o.material, count);
          matrices.forEach((m, i) => im.setMatrixAt(i, m));
          im.name = o.name;
          im.userData = o.userData;
          return im;
        }
        if (o.isLine) return expandLines(o, matrices);
        return o;
      });
      if (out.length === 1 && !(node as any).isGroup) {
        out[0].position.copy(node.position); out[0].quaternion.copy(node.quaternion); out[0].scale.copy(node.scale);
        return out[0];
      }
      const g = new THREE.Group();
      g.name = node.name;
      out.forEach((o) => g.add(o));
      return g;
    });
  }
}

function expandLines(line: THREE.LineSegments, matrices: THREE.Matrix4[]): THREE.LineSegments {
  const src = line.geometry.index ? line.geometry.toNonIndexed() : line.geometry;
  const pos = src.attributes.position;
  const n = pos.count;
  const out = new Float32Array(n * 3 * matrices.length);
  const v = new THREE.Vector3();
  let o = 0;
  for (const m of matrices) {
    for (let i = 0; i < n; i++) {
      v.fromBufferAttribute(pos, i).applyMatrix4(m);
      out[o++] = v.x; out[o++] = v.y; out[o++] = v.z;
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(out, 3));
  const l = new THREE.LineSegments(g, line.material);
  l.name = line.name;
  l.userData = line.userData;
  return l;
}
