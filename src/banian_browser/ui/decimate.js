/* Banian Browser - polygon reduction (quadric error metrics, half-edge collapse).
 *
 *   BBDecimate.simplify(input, opts, onProgress) -> Promise(result)
 *     input  : { positions: Float32Array(n*3), uvs: Float32Array(n*2)|null,
 *                indices: Uint32Array(m*3), groups: Int32Array(m)|null }  (material per triangle)
 *     opts   : { ratio: 0..1 (target fraction of triangles), tolerance: max error distance
 *                (same units as positions, 0 = off), keepSeams: true, keepBorders: true }
 *     result : same layout as input, plus { before, after }
 *
 * Vertices are welded by position (+ UV + material when keepSeams). UV seams, material
 * borders and open mesh borders are locked so textures and outlines stay intact.
 * A collapse keeps the surviving vertex unchanged, so its UV stays exact.
 * Works in plain ES5 so it runs in every SketchUp HtmlDialog.
 */
(function (root) {
  'use strict';

  function Heap() { this.c = []; this.e = []; this.a = []; this.b = []; }
  Heap.prototype.size = function () { return this.c.length; };
  Heap.prototype.push = function (cost, edgeA, edgeB, stamp) {
    var c = this.c, a = this.a, b = this.b, e = this.e;
    var i = c.length;
    c.push(cost); a.push(edgeA); b.push(edgeB); e.push(stamp);
    while (i > 0) {
      var p = (i - 1) >> 1;
      if (c[p] <= c[i]) break;
      this.swap(i, p);
      i = p;
    }
  };
  Heap.prototype.swap = function (i, j) {
    var t;
    t = this.c[i]; this.c[i] = this.c[j]; this.c[j] = t;
    t = this.a[i]; this.a[i] = this.a[j]; this.a[j] = t;
    t = this.b[i]; this.b[i] = this.b[j]; this.b[j] = t;
    t = this.e[i]; this.e[i] = this.e[j]; this.e[j] = t;
  };
  Heap.prototype.pop = function (out) {
    var c = this.c;
    var n = c.length;
    if (!n) return false;
    out[0] = c[0]; out[1] = this.a[0]; out[2] = this.b[0]; out[3] = this.e[0];
    var last = n - 1;
    if (last > 0) {
      c[0] = c[last]; this.a[0] = this.a[last]; this.b[0] = this.b[last]; this.e[0] = this.e[last];
    }
    c.pop(); this.a.pop(); this.b.pop(); this.e.pop();
    n = c.length;
    var i = 0;
    for (;;) {
      var l = 2 * i + 1, r = l + 1, m = i;
      if (l < n && c[l] < c[m]) m = l;
      if (r < n && c[r] < c[m]) m = r;
      if (m === i) break;
      this.swap(i, m);
      i = m;
    }
    return true;
  };

  function weld(input, keepSeams) {
    var P = input.positions, UV = input.uvs, I = input.indices, G = input.groups;
    var n = P.length / 3;
    var minX = Infinity, minY = Infinity, minZ = Infinity, maxX = -Infinity, maxY = -Infinity, maxZ = -Infinity;
    for (var i = 0; i < n; i++) {
      var x = P[i * 3], y = P[i * 3 + 1], z = P[i * 3 + 2];
      if (x < minX) minX = x; if (x > maxX) maxX = x;
      if (y < minY) minY = y; if (y > maxY) maxY = y;
      if (z < minZ) minZ = z; if (z > maxZ) maxZ = z;
    }
    var diag = Math.sqrt((maxX - minX) * (maxX - minX) + (maxY - minY) * (maxY - minY) + (maxZ - minZ) * (maxZ - minZ)) || 1;
    var q = 1e-6 * diag;
    var map = {};
    var pos = [], uv = [], vgroup = [];
    var remap = new Int32Array(n);
    var triGroup = G || null;
    // vertex -> group: when keepSeams we weld per material group, so a vertex used by
    // two materials is split and the material border becomes a locked border.
    var vertGroupOfTri = null;
    if (keepSeams && G) {
      vertGroupOfTri = new Int32Array(n);
      for (var t0 = 0; t0 < I.length / 3; t0++) {
        vertGroupOfTri[I[t0 * 3]] = G[t0]; vertGroupOfTri[I[t0 * 3 + 1]] = G[t0]; vertGroupOfTri[I[t0 * 3 + 2]] = G[t0];
      }
    }
    for (var v = 0; v < n; v++) {
      var key = Math.round(P[v * 3] / q) + '_' + Math.round(P[v * 3 + 1] / q) + '_' + Math.round(P[v * 3 + 2] / q);
      if (keepSeams && UV) key += '_' + Math.round(UV[v * 2] * 1e5) + '_' + Math.round(UV[v * 2 + 1] * 1e5);
      if (vertGroupOfTri) key += '_' + vertGroupOfTri[v];
      var id = map[key];
      if (id === undefined) {
        id = pos.length / 3;
        map[key] = id;
        pos.push(P[v * 3], P[v * 3 + 1], P[v * 3 + 2]);
        if (UV) uv.push(UV[v * 2], UV[v * 2 + 1]);
      }
      remap[v] = id;
    }
    var tris = [];
    var groups = [];
    var m = I.length / 3;
    for (var t = 0; t < m; t++) {
      var a = remap[I[t * 3]], b = remap[I[t * 3 + 1]], c = remap[I[t * 3 + 2]];
      if (a === b || b === c || a === c) continue;
      tris.push(a, b, c);
      groups.push(triGroup ? triGroup[t] : 0);
    }
    return { pos: new Float64Array(pos), uv: UV ? new Float64Array(uv) : null, tris: new Int32Array(tris), groups: new Int32Array(groups), diag: diag };
  }

  function planeOf(pos, a, b, c, out) {
    var ax = pos[a * 3], ay = pos[a * 3 + 1], az = pos[a * 3 + 2];
    var ux = pos[b * 3] - ax, uy = pos[b * 3 + 1] - ay, uz = pos[b * 3 + 2] - az;
    var vx = pos[c * 3] - ax, vy = pos[c * 3 + 1] - ay, vz = pos[c * 3 + 2] - az;
    var nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    var len = Math.sqrt(nx * nx + ny * ny + nz * nz);
    if (len < 1e-30) return 0;
    nx /= len; ny /= len; nz /= len;
    out[0] = nx; out[1] = ny; out[2] = nz; out[3] = -(nx * ax + ny * ay + nz * az);
    return len * 0.5;
  }

  function addPlane(Q, v, p, w) {
    var o = v * 10, a = p[0], b = p[1], c = p[2], d = p[3];
    Q[o] += w * a * a; Q[o + 1] += w * a * b; Q[o + 2] += w * a * c; Q[o + 3] += w * a * d;
    Q[o + 4] += w * b * b; Q[o + 5] += w * b * c; Q[o + 6] += w * b * d;
    Q[o + 7] += w * c * c; Q[o + 8] += w * c * d; Q[o + 9] += w * d * d;
  }

  function evalQ(Q, u, v, x, y, z) {
    var o = u * 10, k = v * 10;
    var a2 = Q[o] + Q[k], ab = Q[o + 1] + Q[k + 1], ac = Q[o + 2] + Q[k + 2], ad = Q[o + 3] + Q[k + 3];
    var b2 = Q[o + 4] + Q[k + 4], bc = Q[o + 5] + Q[k + 5], bd = Q[o + 6] + Q[k + 6];
    var c2 = Q[o + 7] + Q[k + 7], cd = Q[o + 8] + Q[k + 8], d2 = Q[o + 9] + Q[k + 9];
    var e = a2 * x * x + 2 * ab * x * y + 2 * ac * x * z + 2 * ad * x + b2 * y * y + 2 * bc * y * z + 2 * bd * y + c2 * z * z + 2 * cd * z + d2;
    return e < 0 ? 0 : e;
  }

  function simplify(input, opts, onProgress) {
    opts = opts || {};
    var ratio = opts.ratio == null ? 0.5 : Math.max(0, Math.min(1, opts.ratio));
    var tol = opts.tolerance > 0 ? opts.tolerance : 0;
    var keepSeams = opts.keepSeams !== false;
    var keepBorders = opts.keepBorders !== false;
    return new Promise(function (resolve) {
      var W = weld(input, keepSeams);
      var pos = W.pos, tris = W.tris, nV = pos.length / 3, nT = tris.length / 3;
      var before = input.indices.length / 3;
      var target = Math.max(1, Math.floor(before * ratio));
      if (ratio >= 0.999 && !tol) { resolve(finish(W, null, before)); return; }

      // vertex -> triangle lists
      var vt = new Array(nV);
      for (var i = 0; i < nV; i++) vt[i] = [];
      for (var t = 0; t < nT; t++) { vt[tris[t * 3]].push(t); vt[tris[t * 3 + 1]].push(t); vt[tris[t * 3 + 2]].push(t); }

      // quadrics + border detection
      var Q = new Float64Array(nV * 10);
      var plane = [0, 0, 0, 0];
      var edgeCount = {};
      for (t = 0; t < nT; t++) {
        var a = tris[t * 3], b = tris[t * 3 + 1], c = tris[t * 3 + 2];
        if (planeOf(pos, a, b, c, plane)) { addPlane(Q, a, plane, 1); addPlane(Q, b, plane, 1); addPlane(Q, c, plane, 1); }
        countEdge(edgeCount, a, b); countEdge(edgeCount, b, c); countEdge(edgeCount, c, a);
      }
      var locked = new Uint8Array(nV);
      var edges = [];
      Object.keys(edgeCount).forEach(function (k) {
        var s = k.split('_');
        var u = +s[0], v = +s[1];
        if (edgeCount[k] === 1) {
          if (keepBorders) { locked[u] = 1; locked[v] = 1; } else addBorderQuadric(Q, pos, vt, tris, u, v);
        }
        edges.push(u, v);
      });
      edgeCount = null;

      var alive = new Uint8Array(nT); for (t = 0; t < nT; t++) alive[t] = 1;
      var vdead = new Uint8Array(nV);
      var stamp = new Int32Array(nV);
      var heap = new Heap();
      var live = nT;
      var tol2 = tol * tol;

      function push(u, v) {
        if (locked[u] && locked[v]) return;
        var best = Infinity, from = -1, to = -1;
        if (!locked[u]) { var e1 = evalQ(Q, u, v, pos[v * 3], pos[v * 3 + 1], pos[v * 3 + 2]); if (e1 < best) { best = e1; from = u; to = v; } }
        if (!locked[v]) { var e2 = evalQ(Q, u, v, pos[u * 3], pos[u * 3 + 1], pos[u * 3 + 2]); if (e2 < best) { best = e2; from = v; to = u; } }
        if (from < 0) return;
        heap.push(best, from, to, stamp[from] * 1048576 + stamp[to]);
      }
      for (i = 0; i < edges.length; i += 2) push(edges[i], edges[i + 1]);
      edges = null;

      var out = [0, 0, 0, 0];
      var nOld = [0, 0, 0], nNew = [0, 0, 0];
      var steps = 0;

      function canCollapse(u, v) {
        // link condition: u and v must share at most two neighbours (manifold)
        var shared = 0, seen = {};
        var lu = vt[u], lv = vt[v], k, j, tt, w;
        for (k = 0; k < lu.length; k++) {
          tt = lu[k]; if (!alive[tt]) continue;
          for (j = 0; j < 3; j++) { w = tris[tt * 3 + j]; if (w !== u) seen[w] = 1; }
        }
        var counted = {};
        for (k = 0; k < lv.length; k++) {
          tt = lv[k]; if (!alive[tt]) continue;
          for (j = 0; j < 3; j++) { w = tris[tt * 3 + j]; if (w !== v && w !== u && seen[w] && !counted[w]) { counted[w] = 1; shared++; } }
        }
        if (shared > 2) return false;
        // no flipped or degenerate triangles around u
        var vx = pos[v * 3], vy = pos[v * 3 + 1], vz = pos[v * 3 + 2];
        for (k = 0; k < lu.length; k++) {
          tt = lu[k]; if (!alive[tt]) continue;
          var i0 = tris[tt * 3], i1 = tris[tt * 3 + 1], i2 = tris[tt * 3 + 2];
          if (i0 === v || i1 === v || i2 === v) continue;
          if (!normal(pos, i0, i1, i2, -1, 0, 0, 0, nOld)) continue;
          var ok = normal(pos, i0, i1, i2, u, vx, vy, vz, nNew);
          if (!ok) return false;
          if (nOld[0] * nNew[0] + nOld[1] * nNew[1] + nOld[2] * nNew[2] < 0.25) return false;
        }
        return true;
      }

      function collapse(u, v) {
        var lu = vt[u];
        var lv = vt[v];
        for (var k = 0; k < lu.length; k++) {
          var tt = lu[k];
          if (!alive[tt]) continue;
          var o = tt * 3;
          if (tris[o] === v || tris[o + 1] === v || tris[o + 2] === v) {
            alive[tt] = 0; live--;
            continue;
          }
          if (tris[o] === u) tris[o] = v; else if (tris[o + 1] === u) tris[o + 1] = v; else tris[o + 2] = v;
          lv.push(tt);
        }
        vt[u] = [];
        vdead[u] = 1;
        var ou = u * 10, ov = v * 10;
        for (k = 0; k < 10; k++) Q[ov + k] += Q[ou + k];
        // compact v's list and refresh its edges
        var fresh = [], nb = {};
        for (k = 0; k < lv.length; k++) {
          var t2 = lv[k];
          if (!alive[t2] || fresh.indexOf(t2) >= 0) continue;
          fresh.push(t2);
          for (var j = 0; j < 3; j++) { var w = tris[t2 * 3 + j]; if (w !== v) nb[w] = 1; }
        }
        vt[v] = fresh;
        stamp[v]++;
        Object.keys(nb).forEach(function (w) { push(v, +w); });
      }

      function valid(from, to, st) {
        if (vdead[from] || vdead[to]) return false;
        return st === stamp[from] * 1048576 + stamp[to];
      }

      function run() {
        var t0 = Date.now();
        while (live > target && heap.pop(out)) {
          var cost = out[0], from = out[1], to = out[2];
          if (!valid(from, to, out[3])) continue;
          if (tol && cost > tol2) break;
          if (!shareTri(from, to)) continue;
          if (!canCollapse(from, to)) continue;
          collapse(from, to);
          if (++steps % 2000 === 0 && Date.now() - t0 > 40) {
            if (onProgress) onProgress(1 - (live - target) / Math.max(1, nT - target));
            setTimeout(run, 0);
            return;
          }
        }
        if (onProgress) onProgress(1);
        resolve(finish(W, alive, before));
      }

      function shareTri(u, v) {
        var l = vt[u];
        for (var k = 0; k < l.length; k++) {
          var tt = l[k];
          if (alive[tt] && (tris[tt * 3] === v || tris[tt * 3 + 1] === v || tris[tt * 3 + 2] === v)) return true;
        }
        return false;
      }

      run();
    });
  }

  function countEdge(map, a, b) {
    var k = a < b ? a + '_' + b : b + '_' + a;
    map[k] = (map[k] || 0) + 1;
  }

  function addBorderQuadric(Q, pos, vt, tris, u, v) {
    // plane through the border edge, perpendicular to its face: keeps the outline
    var l = vt[u];
    for (var k = 0; k < l.length; k++) {
      var t = l[k], a = tris[t * 3], b = tris[t * 3 + 1], c = tris[t * 3 + 2];
      if ((a === v || b === v || c === v)) {
        var p = [0, 0, 0, 0];
        if (!planeOf(pos, a, b, c, p)) return;
        var ex = pos[v * 3] - pos[u * 3], ey = pos[v * 3 + 1] - pos[u * 3 + 1], ez = pos[v * 3 + 2] - pos[u * 3 + 2];
        var nx = ey * p[2] - ez * p[1], ny = ez * p[0] - ex * p[2], nz = ex * p[1] - ey * p[0];
        var len = Math.sqrt(nx * nx + ny * ny + nz * nz);
        if (len < 1e-30) return;
        nx /= len; ny /= len; nz /= len;
        var bp = [nx, ny, nz, -(nx * pos[u * 3] + ny * pos[u * 3 + 1] + nz * pos[u * 3 + 2])];
        addPlane(Q, u, bp, 10); addPlane(Q, v, bp, 10);
        return;
      }
    }
  }

  // triangle normal; when `sub` >= 0 that vertex is replaced by (x, y, z)
  function normal(pos, i0, i1, i2, sub, x, y, z, out) {
    var ax = pos[i0 * 3], ay = pos[i0 * 3 + 1], az = pos[i0 * 3 + 2];
    var bx = pos[i1 * 3], by = pos[i1 * 3 + 1], bz = pos[i1 * 3 + 2];
    var cx = pos[i2 * 3], cy = pos[i2 * 3 + 1], cz = pos[i2 * 3 + 2];
    if (sub === i0) { ax = x; ay = y; az = z; } else if (sub === i1) { bx = x; by = y; bz = z; } else if (sub === i2) { cx = x; cy = y; cz = z; }
    var ux = bx - ax, uy = by - ay, uz = bz - az, vx = cx - ax, vy = cy - ay, vz = cz - az;
    var nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    var len = Math.sqrt(nx * nx + ny * ny + nz * nz);
    if (len < 1e-20) return false;
    out[0] = nx / len; out[1] = ny / len; out[2] = nz / len;
    return true;
  }

  function finish(W, alive, before) {
    var tris = W.tris, nT = tris.length / 3;
    var used = new Int32Array(W.pos.length / 3); for (var i = 0; i < used.length; i++) used[i] = -1;
    var pos = [], uv = [], idx = [], grp = [];
    for (var t = 0; t < nT; t++) {
      if (alive && !alive[t]) continue;
      for (var j = 0; j < 3; j++) {
        var v = tris[t * 3 + j];
        if (used[v] < 0) {
          used[v] = pos.length / 3;
          pos.push(W.pos[v * 3], W.pos[v * 3 + 1], W.pos[v * 3 + 2]);
          if (W.uv) uv.push(W.uv[v * 2], W.uv[v * 2 + 1]);
        }
        idx.push(used[v]);
      }
      grp.push(W.groups[t]);
    }
    return {
      positions: new Float32Array(pos),
      uvs: W.uv ? new Float32Array(uv) : null,
      indices: new Uint32Array(idx),
      groups: new Int32Array(grp),
      before: before,
      after: idx.length / 3
    };
  }

  root.BBDecimate = { simplify: simplify };
})(typeof window !== 'undefined' ? window : this);
