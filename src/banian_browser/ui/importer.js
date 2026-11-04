/* Banian Import - Skimp-style importer / polygon reducer UI (three.js preview). */
(function () {
  'use strict';

  var BI = window.BI = {};
  var THREE = window.THREE;

  // ------------------------------------------------------------------ strings
  var L = {
    fa: {
      loading: 'در حال خواندن فایل…', parsing: 'در حال پردازش مدل…', textures: 'در حال بارگذاری تکسچرها…',
      reducing: 'در حال کاهش پلیگان…', sending: 'در حال ساخت در اسکچ‌آپ…', failed: 'خواندن مدل ممکن نشد',
      faces: 'سطوح', objects: 'آبجکت', size: 'ابعاد', format: 'فرمت', source: 'منبع',
      units: 'واحد فایل', auto: 'خودکار', up: 'محور بالا', orient: 'جهت', rot90: 'چرخش ۹۰°',
      reduction: 'کاهش پلیگان', percent: 'درصد سطوح', tolerance: 'تلورانس خطا', keep: 'نگه داشتن',
      tol_hint: 'حداکثر فاصله‌ای که سطح ساده‌شده می‌تواند از مدل اصلی فاصله بگیرد.',
      keep_seams: 'حفظ درزهای UV و مرز متریال‌ها', keep_borders: 'حفظ لبه‌های باز',
      preview: 'پیش‌نمایش کاهش', reset: 'بدون کاهش', options: 'گزینه‌ها',
      flat: 'سطوح تخت (بدون نرم‌کردن)', placeholder: 'تکسچر شطرنجی برای بررسی UV', components: 'کامپوننت برای مش‌های تکراری',
      tint: 'رنگ متریال روی تکسچر', import: 'ایمپورت', apply: 'اعمال', cancel: 'انصراف',
      wire: 'وایرفریم', tex: 'تکسچر', fit: 'نمای کامل', done: 'انجام شد',
      t_file: 'ایمپورت مدل', t_skp: 'ایمپورت و ساده‌سازی SKP', t_simplify: 'ساده‌سازی انتخاب',
      simplify_hint: 'هندسه همه نمونه‌های این کامپوننت‌ها ساده می‌شود. سلسله‌مراتب گروه‌ها حفظ می‌شود.',
      small_fix: 'مدل خیلی کوچک است؛ برای جلوگیری از حذف سطوح ریز، داخل یک کامپوننت با مقیاس ساخته می‌شود.',
      no_webgl: 'پیش‌نمایش سه‌بعدی در این نسخه اسکچ‌آپ در دسترس نیست، ولی ایمپورت انجام می‌شود.',
      missing_tex: 'تکسچر پیدا نشد',
      fsize: 'حجم فایل', fs_model: 'مدل فعلی', fs_unsaved: 'هنوز ذخیره نشده', fs_source: 'فایل منبع',
      fs_geom: 'هندسه انتخاب‌شده', fs_add: 'اضافه به مدل', fs_after: 'مدل بعد از ذخیره', fs_note: 'تخمینی است؛ حجم واقعی بعد از ذخیره در اسکچ‌آپ مشخص می‌شود. تکسچرها با کاهش پلیگان کم نمی‌شوند.'
    },
    en: {
      loading: 'Reading file…', parsing: 'Processing model…', textures: 'Loading textures…',
      reducing: 'Reducing polygons…', sending: 'Building in SketchUp…', failed: 'Could not read the model',
      faces: 'Faces', objects: 'Objects', size: 'Size', format: 'Format', source: 'Source',
      units: 'File units', auto: 'Auto', up: 'Up axis', orient: 'Orientation', rot90: 'Rotate 90°',
      reduction: 'Polygon reduction', percent: 'Face percentage', tolerance: 'Error tolerance', keep: 'Keep',
      tol_hint: 'Maximum distance the simplified surface may move away from the original.',
      keep_seams: 'Keep UV seams and material borders', keep_borders: 'Keep open edges',
      preview: 'Preview reduction', reset: 'No reduction', options: 'Options',
      flat: 'Flat shaded (no smoothing)', placeholder: 'Checker texture to inspect UVs', components: 'Components for repeated meshes',
      tint: 'Tint textures with material color', import: 'Import', apply: 'Apply', cancel: 'Cancel',
      wire: 'Wireframe', tex: 'Textures', fit: 'Zoom extents', done: 'Done',
      t_file: 'Import model', t_skp: 'Import & simplify SKP', t_simplify: 'Simplify selection',
      simplify_hint: 'Geometry of all instances of these components is simplified. Group hierarchy is kept.',
      small_fix: 'The model is very small; it is built scaled inside a component so tiny faces are not lost.',
      no_webgl: '3D preview is not available in this SketchUp version, but importing still works.',
      missing_tex: 'Texture not found',
      fsize: 'File size', fs_model: 'Current model', fs_unsaved: 'not saved yet', fs_source: 'Source file',
      fs_geom: 'Selected geometry', fs_add: 'Added to model', fs_after: 'Model after saving', fs_note: 'Estimate; the real size is known after saving in SketchUp. Textures do not shrink with polygon reduction.'
    }
  };
  var lang = 'fa';
  function t(k) { return (L[lang] && L[lang][k]) || L.en[k] || k; }

  // ------------------------------------------------------------------ bridge
  var seq = 0, pending = {}, handlers = {};
  function call(cmd, args) {
    return new Promise(function (resolve, reject) {
      var id = ++seq;
      pending[id] = { resolve: resolve, reject: reject };
      var msg = JSON.stringify({ id: id, cmd: cmd, args: args || {} });
      if (window.sketchup && window.sketchup.bi_call) window.sketchup.bi_call(msg);
      else { delete pending[id]; reject(new Error('no bridge')); }
    });
  }
  BI.reply = function (id, res) {
    var p = pending[id]; if (!p) return; delete pending[id];
    if (res && res.ok) p.resolve(res.data); else { toast((res && res.error) || 'error', true); p.reject(new Error(res && res.error)); }
  };
  BI.on = function (ev, fn) { (handlers[ev] = handlers[ev] || []).push(fn); };
  BI.emit = function (ev, data) { (handlers[ev] || []).forEach(function (fn) { fn(data); }); };

  function $(id) { return document.getElementById(id); }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function icon(n) { return '<svg class="i"><use xlink:href="#i-' + n + '"/></svg>'; }
  function fmt(n) { return Math.round(n).toLocaleString('en-US'); }
  function toast(msg, err) {
    var d = document.createElement('div'); d.className = 't' + (err ? ' err' : ''); d.textContent = msg;
    $('toast').appendChild(d); setTimeout(function () { if (d.parentNode) d.parentNode.removeChild(d); }, err ? 5000 : 2500);
  }
  function busy(text, frac) {
    var b = $('busy');
    if (text === false) { b.classList.add('hidden'); return; }
    b.classList.remove('hidden');
    $('busy-t').textContent = text;
    $('busy-b').style.width = Math.round((frac || 0) * 100) + '%';
  }
  function tick() { return new Promise(function (r) { setTimeout(r, 0); }); }

  // ------------------------------------------------------------------ file access through Ruby
  var reads = {}, rseq = 0;
  function b64ToBytes(b64) {
    var bin = atob(b64), n = bin.length, out = new Uint8Array(n);
    for (var i = 0; i < n; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  BI.on('chunk', function (c) {
    var r = reads[c.req];
    if (!r) return;
    if (c.error) { delete reads[c.req]; r.resolve(null); return; }
    var bytes = b64ToBytes(c.data);
    r.parts.push(bytes); r.got += bytes.length;
    if (r.onProgress && r.size) r.onProgress(r.got / r.size);
    if (c.last) {
      delete reads[c.req];
      var all = new Uint8Array(r.got), off = 0;
      r.parts.forEach(function (p) { all.set(p, off); off += p.length; });
      r.resolve({ buffer: all.buffer, path: r.path });
    }
  });
  function readFile(path, onProgress) {
    return new Promise(function (resolve) {
      var req = 'r' + (++rseq);
      reads[req] = { parts: [], got: 0, resolve: resolve, onProgress: onProgress };
      call('read', { path: path, base: S.dir, req: req }).then(function (res) {
        if (!res || res.missing) { delete reads[req]; resolve(null); return; }
        if (reads[req]) { reads[req].size = res.size; reads[req].path = res.path; }
      }, function () { delete reads[req]; resolve(null); });
    });
  }

  // ------------------------------------------------------------------ paths
  var BASE = 'bbfile://';
  function resolvePath(url) {
    var u = String(url);
    if (u.indexOf(BASE) === 0) u = u.slice(BASE.length);
    try { u = decodeURIComponent(u); } catch (e) { /* keep */ }
    u = u.replace(/\\/g, '/');
    var abs = /[A-Za-z]:\//.exec(u);
    if (abs && abs.index > 0) u = u.slice(abs.index);
    var out = [];
    u.split('/').forEach(function (seg, i) {
      if (seg === '..') { if (out.length > 1) out.pop(); } else if (seg !== '.' && (seg !== '' || i === 0)) out.push(seg);
    });
    return out.join('/');
  }
  function extOf(p) { var m = /\.([^.\/]+)$/.exec(p); return m ? m[1].toLowerCase() : ''; }

  // ------------------------------------------------------------------ texture interception
  var texReg = {};
  var blobs = {};
  var origTexLoad = THREE.TextureLoader.prototype.load;
  THREE.TextureLoader.prototype.load = function (url, onLoad, onProgress, onError) {
    var full = (this.path || '') + url;
    if (/^(blob:|data:)/.test(url)) return origTexLoad.call(this, url, onLoad, onProgress, onError);
    var p = resolvePath(full);
    if (blobs[p]) return origTexLoad.call(this, blobs[p], onLoad, onProgress, onError);
    var tex = new THREE.Texture();
    tex.userData.src = p;
    (texReg[p] = texReg[p] || []).push(tex);
    if (onLoad) setTimeout(function () { onLoad(tex); }, 0);
    return tex;
  };
  var imageCache = {};

  // textures cloned by loaders after interception still need their image
  function fillClones(root) {
    if (!root) return;
    root.traverse(function (o) {
      if (!o.material) return;
      (Array.isArray(o.material) ? o.material : [o.material]).forEach(function (m) {
        ['map', 'emissiveMap', 'alphaMap'].forEach(function (k) {
          var tx = m && m[k];
          if (tx && tx.userData && tx.userData.src && !tx.image && imageCache[tx.userData.src]) {
            var c = imageCache[tx.userData.src];
            tx.image = c.image; tx.userData.path = c.path; tx.needsUpdate = true;
          }
        });
      });
    });
  }

  function loadTextures(onProgress) {
    var keys = Object.keys(texReg);
    var i = 0;
    function next() {
      if (i >= keys.length) return Promise.resolve();
      var p = keys[i++];
      if (onProgress) onProgress(i / keys.length);
      return readFile(p).then(function (res) {
        var list = texReg[p];
        if (!res) { S.missing.push(p); return; }
        S.texBytes += res.buffer.byteLength;
        list.forEach(function (tx) { tx.userData.path = res.path; });
        var ext = extOf(res.path);
        if (ext === 'tga' || ext === 'tif' || ext === 'tiff') {
          try {
            var loader = ext === 'tga' ? new THREE.TGALoader() : new THREE.TIFFLoader();
            var d = loader.parse(res.buffer);
            var cv = document.createElement('canvas'); cv.width = d.width; cv.height = d.height;
            var ctx = cv.getContext('2d'); var img = ctx.createImageData(d.width, d.height);
            img.data.set(d.data.subarray ? d.data.subarray(0, img.data.length) : d.data);
            ctx.putImageData(img, 0, 0);
            imageCache[p] = { image: cv, path: res.path };
            list.forEach(function (tx) { tx.image = cv; tx.flipY = !d.flipY; tx.needsUpdate = true; });
            redraw();
          } catch (e) { /* preview without it */ }
          return;
        }
        return new Promise(function (resolve) {
          var url = URL.createObjectURL(new Blob([res.buffer]));
          var img = new Image();
          img.onload = function () { imageCache[p] = { image: img, path: res.path }; list.forEach(function (tx) { tx.image = img; tx.needsUpdate = true; }); redraw(); resolve(); };
          img.onerror = function () { resolve(); };
          img.src = url;
        });
      }).then(next);
    }
    return next();
  }

  // ------------------------------------------------------------------ state
  var S = {
    info: null, mode: 'file', file: null, dir: '', root: null, content: null,
    units: 'auto', unitGuess: 'm', up: 'Y', rot: 0,
    entries: [], byKey: {}, ratio: 1, tolerance: 0, useTol: false,
    keepSeams: true, keepBorders: true, flat: false, placeholder: false, components: true, tint: false,
    wire: false, showTex: true, missing: [], webgl: true, reduced: false, texBytes: 0, size: {}, selFaces: 0
  };
  var UNIT_CM = { m: 100, cm: 1, mm: 0.1, in: 2.54, ft: 30.48 };

  // ------------------------------------------------------------------ three.js scene
  var renderer, scene, camera, controls, holder, grid;
  var dirty = true;
  function redraw() { dirty = true; }
  function initView() {
    try {
      renderer = new THREE.WebGLRenderer({ antialias: true });
    } catch (e) { S.webgl = false; return; }
    renderer.setPixelRatio(Math.min(1.5, window.devicePixelRatio || 1));
    renderer.outputEncoding = THREE.sRGBEncoding;
    $('view').insertBefore(renderer.domElement, $('ov'));
    renderer.setClearColor(document.body.className === 'dark' ? 0x2a3236 : 0xeef1f0, 1);
    scene = new THREE.Scene();
    camera = new THREE.PerspectiveCamera(40, 1, 0.1, 1e7);
    camera.up.set(0, 0, 1);
    scene.add(new THREE.HemisphereLight(0xffffff, 0x8a8f8c, 0.85));
    var dl = new THREE.DirectionalLight(0xffffff, 0.7); dl.position.set(1, -1.6, 2.2); scene.add(dl);
    var dl2 = new THREE.DirectionalLight(0xffffff, 0.25); dl2.position.set(-1.5, 1, 0.6); scene.add(dl2);
    holder = new THREE.Group(); scene.add(holder);
    controls = new THREE.OrbitControls(camera, renderer.domElement);
    controls.addEventListener('change', redraw);
    window.addEventListener('resize', resize);
    resize();
    // render only when something changed: keeps SketchUp responsive with heavy models
    (function loop() {
      requestAnimationFrame(loop);
      if (!dirty) return;
      dirty = false;
      renderer.render(scene, camera);
    })();
  }
  function resize() {
    if (!renderer) return;
    var v = $('view'); var w = v.clientWidth, h = v.clientHeight;
    renderer.setSize(w, h, false); camera.aspect = w / Math.max(1, h); camera.updateProjectionMatrix();
    redraw();
  }
  function bbox() {
    holder.updateMatrixWorld(true);
    return new THREE.Box3().setFromObject(holder);
  }
  function fitView() {
    if (!renderer) return;
    var b = bbox(); if (b.isEmpty()) return;
    var c = b.getCenter(new THREE.Vector3()), s = b.getSize(new THREE.Vector3());
    var r = Math.max(s.x, s.y, s.z) || 1;
    camera.near = r / 1000; camera.far = r * 1000; camera.updateProjectionMatrix();
    camera.position.set(c.x + r * 1.15, c.y - r * 1.6, c.z + r * 0.95);
    controls.target.copy(c); controls.update();
    if (grid) scene.remove(grid);
    var step = Math.pow(10, Math.floor(Math.log(r) / Math.LN10));
    var dark = document.body.className === 'dark';
    grid = new THREE.GridHelper(step * 10, 10, dark ? 0x56635f : 0xb7c2be, dark ? 0x3a4447 : 0xdde3e0);
    grid.rotation.x = Math.PI / 2; grid.position.set(c.x, c.y, b.min.z);
    scene.add(grid);
    redraw();
  }

  // ------------------------------------------------------------------ loading
  function textOf(buf) { return new TextDecoder('utf-8').decode(new Uint8Array(buf)); }
  function defaultMaterial(geo) {
    var vc = geo.getAttribute && geo.getAttribute('color');
    var m = new THREE.MeshStandardMaterial({ color: vc ? 0xffffff : 0xbcc3c0, vertexColors: !!vc, roughness: 0.8, metalness: 0 });
    m.userData.isDefault = true;
    return m;
  }

  function loadFile() {
    var f = S.file, ext = f.ext, base = BASE + S.dir + '/';
    busy(t('loading'), 0);
    return readFile(f.path, function (p) { busy(t('loading'), p); }).then(function (res) {
      if (!res) throw new Error(t('failed'));
      busy(t('parsing'), 0.5);
      return tick().then(function () { return parse(ext, res.buffer, base); });
    }).then(function (obj) {
      busy(t('textures'), 0.8);
      return loadTextures(function (p) { busy(t('textures'), p); }).then(function () { return obj; });
    });
  }

  function preloadGltfBuffers(json, base) {
    var uris = [];
    (json.buffers || []).forEach(function (b) { if (b.uri && !/^data:/.test(b.uri)) uris.push(b.uri); });
    var i = 0;
    function next() {
      if (i >= uris.length) return Promise.resolve();
      var p = resolvePath(base + uris[i++]);
      return readFile(p).then(function (res) { if (res) blobs[p] = URL.createObjectURL(new Blob([res.buffer])); }).then(next);
    }
    return next();
  }

  function parse(ext, buf, base) {
    var manager = new THREE.LoadingManager();
    manager.setURLModifier(function (url) { var p = resolvePath(url); return blobs[p] || url; });
    return new Promise(function (resolve, reject) {
      try {
        switch (ext) {
          case 'glb':
          case 'gltf': {
            window.createImageBitmap = undefined; // force TextureLoader (intercepted above)
            var data = buf;
            var pre = Promise.resolve();
            if (ext === 'gltf') {
              data = textOf(buf);
              pre = preloadGltfBuffers(JSON.parse(data), base);
            }
            pre.then(function () {
              new THREE.GLTFLoader(manager).parse(data, base, function (g) { resolve(g.scene); }, reject);
            });
            break;
          }
          case 'fbx': resolve(new THREE.FBXLoader(manager).parse(buf, base)); break;
          case 'obj': {
            var text = textOf(buf);
            var libs = []; var re = /^\s*mtllib\s+(.+?)\s*$/gm; var m;
            while ((m = re.exec(text))) libs.push(m[1]);
            var objLoader = new THREE.OBJLoader(manager);
            var chain = Promise.resolve();
            libs.forEach(function (lib) {
              chain = chain.then(function () {
                return readFile(resolvePath(base + lib)).then(function (res) {
                  if (!res) return;
                  var ml = new THREE.MTLLoader(manager);
                  var mats = ml.parse(textOf(res.buffer), base);
                  mats.preload();
                  objLoader.setMaterials(mats);
                });
              });
            });
            chain.then(function () { resolve(objLoader.parse(text)); }, reject);
            break;
          }
          case 'dae': resolve(new THREE.ColladaLoader(manager).parse(textOf(buf), base).scene); break;
          case '3ds': resolve(new THREE.TDSLoader(manager).parse(buf, base)); break;
          case 'stl': {
            var g = new THREE.STLLoader().parse(buf);
            g.deleteAttribute('normal'); g.computeVertexNormals();
            resolve(new THREE.Mesh(g, defaultMaterial(g)));
            break;
          }
          case 'ply': {
            var pg = new THREE.PLYLoader().parse(buf);
            if (!pg.getAttribute('normal')) pg.computeVertexNormals();
            resolve(new THREE.Mesh(pg, defaultMaterial(pg)));
            break;
          }
          case 'wrl':
          case 'vrml': resolve(new THREE.VRMLLoader(manager).parse(textOf(buf), base)); break;
          case 'usdz': resolve(new THREE.USDZLoader(manager).parse(buf)); break;
          default: reject(new Error('Unsupported format: ' + ext));
        }
      } catch (e) { reject(e); }
    });
  }

  // Geometry of the selection arrives in slices ('mgeom') so SketchUp stays responsive.
  function loadModelData() {
    busy(t('parsing'), 0);
    return new Promise(function (resolve) {
      var data = { nodes: [], geoms: {}, materials: [] }, total = 1, got = 0;
      BI.on('mgeom', function (g) {
        var list = data.geoms[g.key] || (data.geoms[g.key] = []);
        for (var i = 0; i < g.parts.length; i++) list.push(g.parts[i]);
        got += g.faces || 0;
        busy(t('parsing'), Math.min(0.95, got / total));
      });
      BI.on('mgeom_done', function (d) {
        data.materials = d.materials || [];
        if (d.error) toast(d.error, true);
        resolve(data);
      });
      call('model_data').then(function (info) {
        data.nodes = info.nodes || [];
        S.selFaces = info.faces || 0;
        total = Math.max(1, info.faces || 0);
      });
    });
  }

  // Builds three.js objects from SketchUp data (simplify / skp modes).
  function buildFromModel(data) {
    var mats = (data.materials || []).map(function (m) {
      var mat = new THREE.MeshStandardMaterial({ color: m.color || '#cccccc', roughness: 0.85, metalness: 0, side: THREE.DoubleSide });
      if (m.opacity < 0.999) { mat.transparent = true; mat.opacity = m.opacity; }
      if (m.tex && m.tex.path) {
        var tx = new THREE.Texture(); tx.userData.src = m.tex.path; tx.wrapS = tx.wrapT = THREE.RepeatWrapping;
        tx.encoding = THREE.sRGBEncoding;
        (texReg[m.tex.path] = texReg[m.tex.path] || []).push(tx);
        mat.map = tx; mat.color.set('#ffffff');
      }
      mat.name = m.name;
      return mat;
    });
    var defMat = new THREE.MeshStandardMaterial({ color: '#d8dcda', roughness: 0.9, side: THREE.DoubleSide });
    var geos = {};
    Object.keys(data.geoms || {}).forEach(function (key) {
      var parts = data.geoms[key];
      var P = [], UV = [], I = [], G = [], matList = [], hasUV = parts.some(function (p) { return !!p.uvs; });
      parts.forEach(function (part, pi) {
        var base = P.length / 3;
        for (var i = 0; i < part.pts.length; i++) P.push(part.pts[i]);
        var n = part.pts.length / 3;
        for (i = 0; i < n; i++) { if (part.uvs) UV.push(part.uvs[i * 2], part.uvs[i * 2 + 1]); else if (hasUV) UV.push(0, 0); }
        for (i = 0; i < part.tris.length; i++) I.push(part.tris[i] + base);
        for (i = 0; i < part.tris.length / 3; i++) G.push(pi);
        matList.push(part.mat >= 0 ? mats[part.mat] : defMat);
      });
      geos[key] = { geo: toGeometry({ positions: new Float32Array(P), uvs: hasUV ? new Float32Array(UV) : null, indices: new Uint32Array(I), groups: new Int32Array(G) }), mats: matList, matIds: parts.map(function (p) { return p.mat; }) };
    });
    function node(n) {
      var o;
      if (n.g && geos[n.g]) {
        o = new THREE.Mesh(geos[n.g].geo, geos[n.g].mats);
        o.userData.key = n.g; o.userData.matIds = geos[n.g].matIds;
      } else o = new THREE.Group();
      o.name = n.n || '';
      o.matrixAutoUpdate = false;
      o.matrix.fromArray(n.m);
      var kids = n.c || [];
      if (kids.length && o.isMesh) {
        var g = new THREE.Group(); g.matrixAutoUpdate = false; g.matrix.copy(o.matrix); o.matrix.identity(); g.add(o); o = g;
      }
      kids.forEach(function (c) { o.add(node(c)); });
      return o;
    }
    var root = new THREE.Group();
    (data.nodes || []).forEach(function (n) { root.add(node(n)); });
    return root;
  }

  // ------------------------------------------------------------------ geometry helpers
  function geoToInput(geo) {
    var pos = geo.getAttribute('position');
    var n = pos.count;
    var P = new Float32Array(n * 3);
    for (var i = 0; i < n; i++) { P[i * 3] = pos.getX(i); P[i * 3 + 1] = pos.getY(i); P[i * 3 + 2] = pos.getZ(i); }
    var uvA = geo.getAttribute('uv'), UV = null;
    if (uvA) { UV = new Float32Array(n * 2); for (i = 0; i < n; i++) { UV[i * 2] = uvA.getX(i); UV[i * 2 + 1] = uvA.getY(i); } }
    var I;
    if (geo.index) { I = new Uint32Array(geo.index.count); for (i = 0; i < I.length; i++) I[i] = geo.index.getX(i); }
    else { I = new Uint32Array(n - (n % 3)); for (i = 0; i < I.length; i++) I[i] = i; }
    var G = new Int32Array(I.length / 3);
    if (geo.groups && geo.groups.length) {
      geo.groups.forEach(function (gr) {
        var s = Math.floor(gr.start / 3), e = Math.min(G.length, Math.floor((gr.start + gr.count) / 3));
        for (var k = s; k < e; k++) G[k] = gr.materialIndex || 0;
      });
    }
    return { positions: P, uvs: UV, indices: I, groups: G };
  }

  function toGeometry(d) {
    // sort triangles by group so three.js draw groups are contiguous
    var nT = d.indices.length / 3, order = [];
    for (var t = 0; t < nT; t++) order.push(t);
    order.sort(function (a, b) { return d.groups[a] - d.groups[b]; });
    var idx = new Uint32Array(d.indices.length);
    for (var k = 0; k < nT; k++) { var s = order[k]; idx[k * 3] = d.indices[s * 3]; idx[k * 3 + 1] = d.indices[s * 3 + 1]; idx[k * 3 + 2] = d.indices[s * 3 + 2]; }
    var geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(d.positions, 3));
    if (d.uvs) geo.setAttribute('uv', new THREE.BufferAttribute(d.uvs, 2));
    geo.setIndex(new THREE.BufferAttribute(idx, 1));
    var start = 0;
    for (k = 0; k <= nT; k++) {
      if (k === nT || (k > 0 && d.groups[order[k]] !== d.groups[order[k - 1]])) {
        if (k > start) geo.addGroup(start * 3, (k - start) * 3, d.groups[order[start]]);
        start = k;
      }
    }
    geo.computeVertexNormals();
    return geo;
  }

  // Unique (geometry + materials) entries shared by all meshes using them.
  function collectEntries() {
    S.entries = []; S.byKey = {};
    S.content.updateMatrixWorld(true);
    S.content.traverse(function (o) {
      if (!o.isMesh || o.isSkinnedMesh && !o.geometry) return;
      if (!o.geometry || !o.geometry.getAttribute('position')) return;
      var mats = Array.isArray(o.material) ? o.material : [o.material];
      var key = o.userData.key || (o.geometry.uuid + '|' + mats.map(function (m) { return m ? m.uuid : '-'; }).join(','));
      o.userData.key = key;
      var e = S.byKey[key];
      if (!e) {
        e = { key: key, geo: o.geometry, input: geoToInput(o.geometry), reduced: null, meshes: [], mats: mats, matIds: o.userData.matIds };
        e.tris = e.input.indices.length / 3;
        S.byKey[key] = e; S.entries.push(e);
      }
      e.meshes.push(o);
    });
  }

  function totals() {
    var before = 0, after = 0;
    S.entries.forEach(function (e) {
      before += e.tris * e.meshes.length;
      after += (e.reduced ? e.reduced.after : e.tris) * e.meshes.length;
    });
    return { before: before, after: after };
  }

  // ------------------------------------------------------------------ transforms / units
  function unitCm() {
    if (S.mode !== 'file') return 2.54;
    return UNIT_CM[S.units === 'auto' ? S.unitGuess : S.units];
  }
  function applyHolder() {
    if (!holder) return;
    var s = unitCm();
    holder.rotation.set(S.mode === 'file' && S.up === 'Y' ? Math.PI / 2 : 0, 0, S.rot * Math.PI / 180);
    holder.scale.set(s, s, s);
    holder.updateMatrixWorld(true);
    redraw();
  }
  function guessUnits() {
    var b = new THREE.Box3().setFromObject(S.content);
    var size = b.getSize(new THREE.Vector3());
    var m = Math.max(size.x, size.y, size.z);
    var ext = S.file.ext;
    if (ext === 'glb' || ext === 'gltf' || ext === 'dae' || ext === 'usdz') S.unitGuess = 'm';
    else if (m > 3000) S.unitGuess = 'mm';
    else if (m > 30 || ext === 'fbx' && m > 5) S.unitGuess = 'cm';
    else S.unitGuess = 'm';
    S.up = (ext === 'stl' || ext === '3ds' || ext === 'ply') ? 'Z' : 'Y';
  }
  function sizeCm() {
    if (!holder) {
      var b0 = new THREE.Box3().setFromObject(S.content);
      return b0.getSize(new THREE.Vector3()).multiplyScalar(unitCm());
    }
    return bbox().getSize(new THREE.Vector3());
  }

  // ------------------------------------------------------------------ reduction
  // Every call cancels a run still in progress and starts over with the current
  // settings, so dragging the slider never queues work or shows stale results.
  var reduceGen = 0, reducing = null;
  function runReduction() {
    var gen = ++reduceGen;
    var stale = function () { return gen !== reduceGen; };
    var ratio = S.useTol ? 0 : S.ratio;
    var list = S.entries.slice();
    var total = 0; list.forEach(function (e) { total += e.tris; });
    var done = 0, i = 0;
    S.reduced = false;
    busy(t('reducing'), 0);
    function next() {
      if (stale()) return Promise.resolve(false);
      if (i >= list.length) return Promise.resolve(true);
      var e = list[i++];
      if (!S.useTol && ratio >= 0.999) { e.reduced = null; setGeo(e, e.geo); done += e.tris; return next(); }
      var scale = (e.meshes[0].matrixWorld.getMaxScaleOnAxis() || 1);
      var tolLocal = S.useTol ? S.tolerance / scale : 0;
      var wk = S.keepSeams ? 'w1' : 'w0';
      if (!e[wk]) e[wk] = BBDecimate.weld(e.input, S.keepSeams);
      return BBDecimate.simplify(e.input, {
        ratio: ratio, tolerance: tolLocal, keepSeams: S.keepSeams, keepBorders: S.keepBorders,
        welded: e[wk], cancelled: stale
      }, function (p) {
        if (!stale()) busy(t('reducing'), (done + p * e.tris) / Math.max(1, total));
      }).then(function (r) {
        if (!r || stale()) return false;
        done += e.tris;
        e.reduced = r;
        setGeo(e, toGeometry(r));
        // let the dialog breathe between big meshes
        return tick().then(next);
      });
    }
    reducing = tick().then(next).then(function (ok) {
      if (stale()) return reducing;
      reducing = null; S.reduced = !!ok; busy(false); renderStats();
      return ok;
    }, function (err) {
      if (!stale()) { reducing = null; busy(false); toast(String(err && err.message || err), true); }
    });
    return reducing;
  }
  function setGeo(e, geo) {
    var old = e.meshes[0] && e.meshes[0].geometry;
    e.meshes.forEach(function (m) { m.geometry = geo; });
    if (old && old !== geo && old !== e.geo) old.dispose();
    redraw();
  }
  function clearReduction() {
    reduceGen++;
    busy(false);
    S.entries.forEach(function (e) { e.reduced = null; setGeo(e, e.geo); });
    renderStats();
  }

  // ------------------------------------------------------------------ preview look
  var checker = null;
  function checkerTexture() {
    if (checker) return checker;
    var c = document.createElement('canvas'); c.width = c.height = 256;
    var x = c.getContext('2d');
    for (var i = 0; i < 8; i++) for (var j = 0; j < 8; j++) { x.fillStyle = (i + j) % 2 ? '#2f3a37' : '#e9eeec'; x.fillRect(i * 32, j * 32, 32, 32); }
    x.fillStyle = '#1e8a6e'; x.fillRect(0, 0, 32, 32);
    checker = new THREE.CanvasTexture(c); checker.wrapS = checker.wrapT = THREE.RepeatWrapping; checker.encoding = THREE.sRGBEncoding;
    checker.userData.canvas = c;
    return checker;
  }
  function eachMaterial(fn) {
    var seen = {};
    S.entries.forEach(function (e) { e.mats.forEach(function (m) { if (m && !seen[m.uuid]) { seen[m.uuid] = 1; fn(m); } }); });
  }
  function applyLook() {
    eachMaterial(function (m) {
      if (m.userData.origMap === undefined) m.userData.origMap = m.map || null;
      m.map = S.placeholder ? checkerTexture() : (S.showTex ? m.userData.origMap : null);
      m.wireframe = S.wire;
      m.flatShading = S.flat;
      m.side = THREE.DoubleSide;
      m.needsUpdate = true;
    });
    redraw();
  }

  // ------------------------------------------------------------------ export to Ruby
  function matExport(m) {
    var col = m.color ? '#' + m.color.getHexString() : '#cccccc';
    var out = { name: m.name || 'Material', color: col, opacity: m.transparent ? m.opacity : 1, tex: null };
    var map = m.userData.origMap !== undefined ? m.userData.origMap : m.map;
    if (S.placeholder) {
      out.tex = { data: checkerTexture().userData.canvas.toDataURL('image/png').split(',')[1], ext: '.png' };
    } else if (map) {
      if (map.userData && map.userData.path) out.tex = { path: map.userData.path };
      else if (map.image) {
        try {
          var img = map.image, w = img.width || img.videoWidth, h = img.height || img.videoHeight;
          if (w && h) {
            var cv = document.createElement('canvas'); cv.width = w; cv.height = h;
            var ctx = cv.getContext('2d');
            ctx.drawImage(img, 0, 0);
            var alpha = m.transparent || m.alphaTest > 0;
            out.tex = { data: cv.toDataURL(alpha ? 'image/png' : 'image/jpeg', 0.92).split(',')[1], ext: alpha ? '.png' : '.jpg' };
          }
        } catch (e) { out.tex = null; }
      }
    }
    return out;
  }

  // Splits a triangle list into parts: one per material, and so every position has a
  // single UV inside a part (SketchUp merges equal points in a PolygonMesh).
  function toParts(d, matIdOf, scale, uvFlipOf) {
    var P = d.positions, UV = d.uvs, I = d.indices, G = d.groups;
    var nv = P.length / 3, pk = new Array(nv), uk = new Array(nv);
    function pkey(v) {
      var k = pk[v];
      if (k === undefined) {
        k = pk[v] = Math.round(P[v * 3] * scale * 1e4) + ',' + Math.round(P[v * 3 + 1] * scale * 1e4) + ',' + Math.round(P[v * 3 + 2] * scale * 1e4);
        uk[v] = UV ? Math.round(UV[v * 2] * 1e5) + ',' + Math.round(UV[v * 2 + 1] * 1e5) : '';
      }
      return k;
    }
    var byMat = {}, order = [];
    for (var t = 0; t < I.length / 3; t++) {
      var id = matIdOf(G[t]);
      if (!byMat[id]) { byMat[id] = []; order.push(id); }
      byMat[id].push(t);
    }
    var parts = [];
    order.forEach(function (id) {
      var list = byMat[id], local = [];
      var uvFlip = uvFlipOf ? uvFlipOf(+id) : false;
      function newPart() { var p = { mat: +id, pts: [], uvs: UV ? [] : null, tris: [], pmap: {}, vmap: {} }; local.push(p); return p; }
      newPart();
      list.forEach(function (tri) {
        var vs = [I[tri * 3], I[tri * 3 + 1], I[tri * 3 + 2]], keys = [], uvk = [];
        for (var j = 0; j < 3; j++) { keys.push(pkey(vs[j])); uvk.push(uk[vs[j]]); }
        var part = null;
        for (var k = 0; k < local.length && !part; k++) {
          var ok = true;
          for (j = 0; j < 3; j++) { var ex = local[k].pmap[keys[j]]; if (ex !== undefined && ex !== uvk[j]) { ok = false; break; } }
          if (ok) part = local[k];
        }
        if (!part) part = local.length < 24 ? newPart() : local[local.length - 1];
        for (j = 0; j < 3; j++) {
          var vk = UV ? keys[j] + '|' + uvk[j] : keys[j];
          var ix = part.vmap[vk];
          if (ix === undefined) {
            ix = part.pts.length / 3; part.vmap[vk] = ix; part.pmap[keys[j]] = uvk[j];
            var w = vs[j];
            part.pts.push(+(P[w * 3] * scale).toFixed(4), +(P[w * 3 + 1] * scale).toFixed(4), +(P[w * 3 + 2] * scale).toFixed(4));
            if (UV) part.uvs.push(+UV[w * 2].toFixed(5), +(uvFlip ? 1 - UV[w * 2 + 1] : UV[w * 2 + 1]).toFixed(5));
          }
          part.tris.push(ix);
        }
      });
      local.forEach(function (p) { if (p.tris.length) { delete p.pmap; delete p.vmap; parts.push(p); } });
    });
    return parts;
  }

  function sendParts(key, parts) {
    // keep each message reasonably small
    var batches = [], cur = [], size = 0;
    parts.forEach(function (p) {
      var s = p.pts.length + p.tris.length + (p.uvs ? p.uvs.length : 0);
      if (size + s > 600000 && cur.length) { batches.push(cur); cur = []; size = 0; }
      cur.push(p); size += s;
    });
    if (cur.length) batches.push(cur);
    var chain = Promise.resolve();
    batches.forEach(function (b) { chain = chain.then(function () { return call('geom', { key: key, parts: b }); }); });
    return chain;
  }

  function options() {
    return { flat: S.flat, components: S.components, tint: S.tint };
  }

  function exportFile() {
    var u = unitCm() / 2.54; // file units -> inches
    var matIds = {}, mats = [], flips = [];
    function gid(m) {
      if (!m || m.userData.isDefault) return -1;
      if (matIds[m.uuid] === undefined) {
        matIds[m.uuid] = mats.length; mats.push(matExport(m));
        var mp = m.userData.origMap !== undefined ? m.userData.origMap : m.map;
        flips.push(!S.placeholder && !!mp && mp.flipY === false);
      }
      return matIds[m.uuid];
    }
    // small models: build bigger inside a scaled component so SketchUp keeps tiny faces
    var sz = sizeCm(); var maxIn = Math.max(sz.x, sz.y, sz.z) / 2.54;
    var k = maxIn < 2 ? 1000 : (maxIn < 20 ? 100 : 1);
    function hasMesh(o) { var f = false; o.traverse(function (c) { if (c.isMesh) f = true; }); return f; }
    function node(o) {
      o.updateMatrix();
      var m = o.matrix.elements.slice();
      m[12] *= u; m[13] *= u; m[14] *= u;
      var n = { n: o.name || '', m: m, g: null, c: [] };
      if (o.isMesh && S.byKey[o.userData.key]) n.g = o.userData.key;
      o.children.forEach(function (c) { if (hasMesh(c)) n.c.push(node(c)); });
      return n;
    }
    holder.updateMatrixWorld(true);
    var axis = new THREE.Matrix4().makeRotationFromEuler(new THREE.Euler(S.up === 'Y' ? Math.PI / 2 : 0, 0, S.rot * Math.PI / 180));
    var root = { n: S.file.name.replace(/\.[^.]+$/, ''), m: axis.elements.slice(), g: null, c: [node(S.content)] };
    var geomParts = {};
    S.entries.forEach(function (e) {
      var d = e.reduced || e.input;
      geomParts[e.key] = toParts(d, function (g) { return gid(e.mats[g] || e.mats[0]); }, u, function (id) { return id >= 0 && flips[id]; });
    });
    return { meta: { materials: mats, nodes: [root], buildScale: k }, geoms: geomParts, k: k };
  }

  function exportModel() {
    var geomParts = {};
    S.entries.forEach(function (e) {
      if (!e.reduced) return;
      geomParts[e.key] = toParts(e.reduced, function (g) { return e.matIds ? e.matIds[g] : -1; }, 1, null);
    });
    return { meta: {}, geoms: geomParts };
  }

  function finish() {
    var data;
    if (S.mode === 'file') data = exportFile();
    else {
      if (!S.reduced) { toast(t('preview'), true); return; }
      data = exportModel();
    }
    busy(t('sending'), 0.2);
    var keys = Object.keys(data.geoms), i = 0;
    call('begin', data.meta).then(function () {
      function next() {
        if (i >= keys.length) return Promise.resolve();
        var k = keys[i++];
        busy(t('sending'), 0.2 + 0.6 * i / keys.length);
        return sendParts(k, data.geoms[k]).then(next);
      }
      return next();
    }).then(function () {
      return call('finish', { options: options() });
    }).then(function () {
      busy(false);
      call('close');
    }, function () { busy(false); });
  }

  // ------------------------------------------------------------------ panel UI
  function seg(name, items, cur) {
    return '<div class="seg">' + items.map(function (it) {
      return '<button data-' + name + '="' + it[0] + '" class="' + (String(cur) === String(it[0]) ? 'on' : '') + '">' + esc(it[1]) + '</button>';
    }).join('') + '</div>';
  }
  function chk(id, on, label) {
    return '<div class="row"><label class="chk"><input type="checkbox" id="' + id + '"' + (on ? ' checked' : '') + '>' + esc(label) + '</label></div>';
  }

  function renderPanel() {
    var h = '';
    var title = t('t_' + S.mode);
    h += '<h2>' + esc(S.file ? S.file.name : title) + '</h2>' + (S.file ? '<div class="sub">' + esc(title) + ' · ' + S.file.ext.toUpperCase() + ' · ' + (S.file.size / 1048576).toFixed(1) + ' MB</div>' : '<div class="sub"></div>');
    if (S.mode === 'simplify' || S.mode === 'skp') h += '<div class="hint">' + esc(t('simplify_hint')) + '</div>';
    if (!S.webgl) h += '<div class="warn">' + esc(t('no_webgl')) + '</div>';
    if (S.mode === 'file') {
      h += '<div class="sec"><h4>' + icon('cube') + esc(t('units')) + '</h4>' +
        '<div class="row">' + seg('unit', [['auto', t('auto') + ' (' + S.unitGuess + ')'], ['m', 'm'], ['cm', 'cm'], ['mm', 'mm'], ['in', 'in'], ['ft', 'ft']], S.units) + '</div>' +
        '<div class="row"><label class="l">' + esc(t('up')) + '</label>' + seg('up', [['Y', 'Y ↑'], ['Z', 'Z ↑']], S.up) +
        '<button class="btn" data-act="rot">' + esc(t('rot90')) + '</button></div>' +
        '<div class="row"><label class="l">' + esc(t('size')) + '</label><span class="num" id="dims"></span></div></div>';
    }
    h += '<div class="sec"><h4>' + icon('fit') + esc(t('reduction')) + '</h4>' +
      '<div class="row">' + seg('rmode', [['pct', t('percent')], ['tol', t('tolerance')]], S.useTol ? 'tol' : 'pct') + '</div>';
    if (!S.useTol) {
      h += '<div class="row"><span class="big num" id="pctv">' + Math.round(S.ratio * 100) + '%</span><span class="hint" style="margin:0 8px">' + esc(t('keep')) + '</span></div>' +
        '<input type="range" id="pct" min="1" max="100" value="' + Math.round(S.ratio * 100) + '">';
    } else {
      h += '<div class="row"><input class="inp sm" type="number" step="0.05" min="0" id="tol" value="' + S.tolerance + '"> cm</div><div class="hint">' + esc(t('tol_hint')) + '</div>';
    }
    h += chk('o-seams', S.keepSeams, t('keep_seams')) + chk('o-borders', S.keepBorders, t('keep_borders')) +
      '<div class="row"><button class="btn pri" data-act="reduce">' + esc(t('preview')) + '</button><button class="btn" data-act="noreduce">' + esc(t('reset')) + '</button></div></div>';
    h += '<div class="sec"><h4>' + icon('down') + esc(t('fsize')) + '</h4><div id="fsize"></div><div class="hint">' + esc(t('fs_note')) + '</div></div>';
    h += '<div class="sec"><h4>' + icon('gear') + esc(t('options')) + '</h4>' + chk('o-flat', S.flat, t('flat'));
    if (S.mode === 'file') {
      h += chk('o-ph', S.placeholder, t('placeholder')) + chk('o-comp', S.components, t('components')) + chk('o-tint', S.tint, t('tint'));
    }
    h += '</div>';
    if (S.missing.length) h += '<div class="warn">' + esc(t('missing_tex')) + ':<br>' + S.missing.map(esc).join('<br>') + '</div>';
    if (S.k > 1) h += '<div class="hint">' + esc(t('small_fix')) + '</div>';
    $('panel').innerHTML = h;
    var main = S.mode === 'file' ? t('import') : t('apply');
    $('foot').innerHTML = '<button class="btn" data-act="cancel">' + esc(t('cancel')) + '</button><button class="btn pri" data-act="go">' + icon('down') + '<span>' + esc(main) + '</span></button>';
    $('vtools').innerHTML = S.webgl ? '<button class="btn' + (S.wire ? ' on' : '') + '" data-act="wire">' + icon('grid') + '<span>' + esc(t('wire')) + '</span></button>' +
      '<button class="btn' + (S.showTex ? ' on' : '') + '" data-act="tex">' + icon('swatch') + '<span>' + esc(t('tex')) + '</span></button>' +
      '<button class="btn" data-act="fit">' + icon('fit') + '<span>' + esc(t('fit')) + '</span></button>' : '';
    renderStats();
  }

  // ------------------------------------------------------------------ file size estimate
  function fmtMB(b) {
    if (b == null || isNaN(b)) return '–';
    var mb = b / 1048576;
    return (mb < 10 ? mb.toFixed(2) : mb < 100 ? mb.toFixed(1) : Math.round(mb)) + ' MB';
  }
  // ratio: fraction of (unique) triangles kept; pass the slider value while dragging
  function sizeEstimate(ratioOverride) {
    var z = S.size || {}, bpf = z.bytes_per_face || 150;
    var before = 0, after = 0;
    S.entries.forEach(function (e) { before += e.tris; after += e.reduced ? e.reduced.after : e.tris; });
    var r = ratioOverride != null ? ratioOverride : (before ? after / before : 1);
    var out = { model: z.model_size == null ? null : z.model_size };
    if (S.mode === 'file') {
      var tex = S.placeholder ? 20000 : S.texBytes;
      out.source = z.source_size;
      out.add = Math.round(before * r) * bpf * 0.85 + tex; // imported faces are triangles
      out.after = out.model != null ? out.model + out.add : null;
    } else if (S.mode === 'skp') {
      var src = z.source_size || 0;
      var geo = Math.min(src * 0.95, S.selFaces * bpf);
      out.source = src;
      out.add = src - geo + geo * r;
      out.after = out.model != null ? out.model + out.add : null;
    } else {
      out.geomBefore = S.selFaces * bpf;
      out.geomAfter = out.geomBefore * r;
      out.after = out.model != null ? Math.max(out.model - out.geomBefore + out.geomAfter, out.geomAfter) : null;
    }
    return out;
  }
  function sizeHtml(est) {
    var row = function (label, val) { return '<div class="row"><label class="l">' + esc(label) + '</label><span class="num ltr" dir="ltr">' + val + '</span></div>'; };
    var h = row(t('fs_model'), est.model != null ? fmtMB(est.model) : esc(t('fs_unsaved')));
    if (est.source != null) h += row(t('fs_source'), fmtMB(est.source));
    if (est.add != null) h += row(t('fs_add'), '≈ ' + fmtMB(est.add));
    if (est.geomBefore != null) h += row(t('fs_geom'), fmtMB(est.geomBefore) + ' → ≈ ' + fmtMB(est.geomAfter));
    if (est.after != null) h += row(t('fs_after'), '<b>≈ ' + fmtMB(est.after) + '</b>' + (est.model ? ' (' + (est.after >= est.model ? '+' : '−') + fmtMB(Math.abs(est.after - est.model)) + ')' : ''));
    return h;
  }
  function renderSize(ratioOverride) {
    var box = $('fsize');
    if (!box || !S.entries.length) return;
    box.innerHTML = sizeHtml(sizeEstimate(ratioOverride));
  }

  function renderStats() {
    var tt = totals();
    var pct = tt.before ? Math.round(tt.after / tt.before * 100) : 100;
    var meshes = 0; S.entries.forEach(function (e) { meshes += e.meshes.length; });
    var h = '<div class="chip">' + esc(t('faces')) + ': <b class="num">' + fmt(tt.before) + (tt.after !== tt.before ? ' → ' + fmt(tt.after) + ' (' + pct + '%)' : '') + '</b></div>' +
      '<div class="chip">' + esc(t('objects')) + ': <b class="num">' + meshes + '</b></div>';
    if (S.content) {
      var s = sizeCm();
      var dims = s.x.toFixed(1) + ' × ' + s.y.toFixed(1) + ' × ' + s.z.toFixed(1) + ' cm';
      h += '<div class="chip">' + esc(t('size')) + ': <b class="num">' + dims + '</b></div>';
      if ($('dims')) $('dims').textContent = dims;
    }
    if (S.entries.length) {
      var est = sizeEstimate(), txt;
      if (est.model != null) txt = fmtMB(est.model) + ' → ≈ ' + fmtMB(est.after);
      else if (est.geomBefore != null) txt = fmtMB(est.geomBefore) + ' → ≈ ' + fmtMB(est.geomAfter);
      else txt = '+ ≈ ' + fmtMB(est.add);
      h += '<div class="chip">' + esc(t('fsize')) + ': <b class="num ltr" dir="ltr">' + txt + '</b></div>';
    }
    $('ov').innerHTML = h;
    renderSize();
  }

  function saveSettings() {
    var v = {
      import_tolerance: S.tolerance, import_use_tol: S.useTol,
      import_keep_seams: S.keepSeams, import_keep_borders: S.keepBorders, import_flat: S.flat,
      import_components: S.components, import_tint: S.tint
    };
    v[S.ratioKey] = Math.round(S.ratio * 100);
    call('settings', { values: v });
  }

  function bind() {
    document.addEventListener('click', function (e) {
      var b = e.target.closest('button');
      if (!b) return;
      if (b.hasAttribute('data-unit')) { S.units = b.getAttribute('data-unit'); applyHolder(); fitView(); renderPanel(); return; }
      if (b.hasAttribute('data-up')) { S.up = b.getAttribute('data-up'); applyHolder(); fitView(); renderPanel(); return; }
      if (b.hasAttribute('data-rmode')) { S.useTol = b.getAttribute('data-rmode') === 'tol'; renderPanel(); return; }
      var a = b.getAttribute('data-act');
      if (a === 'rot') { S.rot = (S.rot + 90) % 360; applyHolder(); fitView(); renderStats(); }
      if (a === 'reduce') { saveSettings(); runReduction(); }
      if (a === 'noreduce') { S.ratio = 1; S.useTol = false; clearReduction(); renderPanel(); }
      if (a === 'wire') { S.wire = !S.wire; applyLook(); renderPanel(); }
      if (a === 'tex') { S.showTex = !S.showTex; applyLook(); renderPanel(); }
      if (a === 'fit') fitView();
      if (a === 'cancel') call('close');
      if (a === 'go') {
        saveSettings();
        if (reducing) reducing.then(function (ok) { if (ok) finish(); });
        else if (S.mode !== 'file' && !S.reduced) runReduction().then(function (ok) { if (ok) finish(); });
        else finish();
      }
    });
    document.addEventListener('input', function (e) {
      if (e.target.id === 'pct') { S.ratio = +e.target.value / 100; $('pctv').textContent = e.target.value + '%'; renderSize(S.ratio); }
      if (e.target.id === 'tol') S.tolerance = Math.max(0, +e.target.value || 0);
    });
    document.addEventListener('change', function (e) {
      var id = e.target.id, on = e.target.checked;
      if (id === 'pct') runReduction();
      if (id === 'o-seams') { S.keepSeams = on; if (S.reduced || reducing) runReduction(); }
      if (id === 'o-borders') { S.keepBorders = on; if (S.reduced || reducing) runReduction(); }
      if (id === 'o-flat') { S.flat = on; applyLook(); }
      if (id === 'o-ph') { S.placeholder = on; applyLook(); renderStats(); }
      if (id === 'o-comp') S.components = on;
      if (id === 'o-tint') S.tint = on;
    });
  }

  function snapshot() {
    if (!renderer || S.mode !== 'file') return;
    setTimeout(function () {
      try {
        renderer.render(scene, camera);
        var src = renderer.domElement, c = document.createElement('canvas'); c.width = c.height = 256;
        var s = Math.min(src.width, src.height);
        var x = c.getContext('2d');
        x.fillStyle = '#f4f6f5'; x.fillRect(0, 0, 256, 256);
        x.drawImage(src, (src.width - s) / 2, (src.height - s) / 2, s, s, 0, 0, 256, 256);
        call('thumb', { path: S.file.path, png: c.toDataURL('image/png').split(',')[1] });
      } catch (e) { /* ignore */ }
    }, 400);
  }

  // ------------------------------------------------------------------ start
  function start() {
    bind();
    call('init').then(function (info) {
      S.info = info; S.mode = info.mode || 'file'; S.file = info.file || null;
      lang = info.lang === 'en' ? 'en' : 'fa';
      document.documentElement.setAttribute('dir', lang === 'en' ? 'ltr' : 'rtl');
      document.body.className = info.theme === 'dark' ? 'dark' : '';
      var st = info.settings || {};
      S.size = info.size_info || {};
      S.ratioKey = S.mode === 'file' ? 'import_ratio' : 'simplify_ratio';
      S.ratio = (st[S.ratioKey] || { import_ratio: 100, simplify_ratio: 50 }[S.ratioKey]) / 100;
      S.tolerance = st.import_tolerance || 0.5;
      S.useTol = !!st.import_use_tol;
      S.keepSeams = st.import_keep_seams !== false; S.keepBorders = st.import_keep_borders !== false;
      S.flat = !!st.import_flat; S.components = st.import_components !== false; S.tint = !!st.import_tint;
      if (S.file) S.dir = S.file.dir;
      initView();
      renderPanel();
      var load = S.mode === 'file' ? loadFile() : loadModelData().then(function (d) {
        busy(t('parsing'), 0.95);
        return tick().then(function () {
          var root = buildFromModel(d);
          return loadTextures().then(function () { return root; });
        });
      });
      return load.then(function (obj) {
        S.content = obj;
        fillClones(obj);
        if (S.mode === 'file') guessUnits();
        if (holder) holder.add(obj);
        applyHolder();
        collectEntries();
        applyLook();
        fitView();
        busy(false);
        renderPanel();
        snapshot();
        if (S.mode !== 'file' || S.ratio < 0.999) runReduction();
      });
    }).catch(function (err) {
      busy(false);
      toast(t('failed') + ': ' + (err && err.message ? err.message : err), true);
    });
  }

  BI.state = S;
  BI.resolvePath = resolvePath;
  BI.toParts = toParts;
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
