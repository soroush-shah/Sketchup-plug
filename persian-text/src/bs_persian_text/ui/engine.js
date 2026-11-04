/*
 * Persian Text engine
 * Shapes text (HarfBuzz WASM, or opentype.js as a fallback), applies BiDi
 * ordering, flattens glyph outlines, merges them with Clipper and returns
 * polygons (outer ring + holes) ready to be turned into SketchUp faces.
 *
 * Written in plain ES5 so it parses in the old Chromium shipped with
 * SketchUp 2017/2018 (which has no WebAssembly; the opentype.js path is used
 * there).
 */
(function (root) {
  'use strict';

  var ClipperLib = root.ClipperLib;
  var CS = 10000; // Clipper integer scale (units per em)

  // ---------------------------------------------------------------------------
  // Small helpers
  // ---------------------------------------------------------------------------
  function b64ToBytes(b64) {
    var bin = root.atob(b64);
    var len = bin.length;
    var out = new Uint8Array(len);
    for (var i = 0; i < len; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  function objKeys(o) { var r = []; for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) r.push(k); return r; }

  // ---------------------------------------------------------------------------
  // Minimal HarfBuzz wrapper (for harfbuzzjs 0.3.x hb.wasm, no imports).
  // Heap views are re-created on every access because malloc may grow memory.
  // ---------------------------------------------------------------------------
  function HB(instance) {
    var ex = instance.exports;
    if (ex._initialize) ex._initialize();
    function u8() { return new Uint8Array(ex.memory.buffer); }
    function u32() { return new Uint32Array(ex.memory.buffer); }
    function i32() { return new Int32Array(ex.memory.buffer); }
    function f32() { return new Float32Array(ex.memory.buffer); }
    var dec = root.TextDecoder ? new root.TextDecoder('utf8') : null;

    function tag(s) {
      return ((s.charCodeAt(0) & 0xFF) << 24 | (s.charCodeAt(1) & 0xFF) << 16 |
              (s.charCodeAt(2) & 0xFF) << 8 | (s.charCodeAt(3) & 0xFF)) >>> 0;
    }
    function untag(t) {
      return String.fromCharCode((t >>> 24) & 0xFF, (t >>> 16) & 0xFF, (t >>> 8) & 0xFF, t & 0xFF);
    }
    function decode(ptr, len) {
      var bytes = u8().subarray(ptr, ptr + len);
      if (dec) return dec.decode(bytes);
      var s = ''; for (var i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
      return s;
    }
    function ascii(str) {
      var p = ex.malloc(str.length + 1); var h = u8();
      for (var i = 0; i < str.length; i++) h[p + i] = str.charCodeAt(i) & 0x7F;
      h[p + str.length] = 0;
      return p;
    }

    var PATH_SIZE = 1 << 18;
    var pathBuf = ex.malloc(PATH_SIZE);

    function Font(bytes, index) {
      var blobPtr = ex.malloc(bytes.byteLength);
      u8().set(bytes, blobPtr);
      this.blob = ex.hb_blob_create(blobPtr, bytes.byteLength, 2, blobPtr, ex.free_ptr());
      this.face = ex.hb_face_create(this.blob, index || 0);
      this.upem = ex.hb_face_get_upem(this.face);
      this.font = ex.hb_font_create(this.face);
      this.axes = this._axes();
    }
    Font.prototype._axes = function () {
      var axis = ex.malloc(64 * 32), c = ex.malloc(4);
      u32()[c / 4] = 64;
      ex.hb_ot_var_get_axis_infos(this.face, 0, c, axis);
      var n = u32()[c / 4], res = {};
      var U = u32(), F = f32();
      for (var i = 0; i < n; i++) {
        res[untag(U[axis / 4 + i * 8 + 1])] = { min: F[axis / 4 + i * 8 + 4], def: F[axis / 4 + i * 8 + 5], max: F[axis / 4 + i * 8 + 6] };
      }
      ex.free(c); ex.free(axis);
      return res;
    };
    Font.prototype.setVariations = function (vars) {
      var keys = objKeys(vars || {});
      var p = ex.malloc(8 * Math.max(1, keys.length));
      for (var i = 0; i < keys.length; i++) {
        u32()[p / 4 + i * 2] = tag(keys[i]);
        f32()[p / 4 + i * 2 + 1] = +vars[keys[i]];
      }
      ex.hb_font_set_variations(this.font, p, keys.length);
      ex.free(p);
    };
    Font.prototype.glyphSvg = function (gid) {
      var n = ex.hbjs_glyph_svg(this.font, gid, pathBuf, PATH_SIZE);
      return n > 0 ? decode(pathBuf, n) : '';
    };
    // Returns glyphs in visual order: [{g, cl, ax, dx, dy}]
    Font.prototype.shape = function (text, rtl, lang) {
      var buf = ex.hb_buffer_create();
      var n = text.length;
      var sp = ex.malloc(n * 2 + 2);
      var w = new Uint16Array(ex.memory.buffer, sp, n);
      for (var i = 0; i < n; i++) w[i] = text.charCodeAt(i);
      ex.hb_buffer_add_utf16(buf, sp, n, 0, n);
      ex.free(sp);
      ex.hb_buffer_guess_segment_properties(buf);
      ex.hb_buffer_set_direction(buf, rtl ? 5 : 4);
      if (rtl) {
        var s = ascii('Arab'); ex.hb_buffer_set_script(buf, ex.hb_script_from_string(s, -1)); ex.free(s);
      }
      if (lang) {
        var l = ascii(lang); ex.hb_buffer_set_language(buf, ex.hb_language_from_string(l, -1)); ex.free(l);
      }
      ex.hb_shape(this.font, buf, 0, 0);
      var len = ex.hb_buffer_get_length(buf);
      var ip = ex.hb_buffer_get_glyph_infos(buf, 0) / 4;
      var pp = ex.hb_buffer_get_glyph_positions(buf, 0) / 4;
      var U = u32(), I = i32(), out = [];
      for (var k = 0; k < len; k++) {
        out.push({ g: U[ip + k * 5], cl: U[ip + k * 5 + 2], ax: I[pp + k * 5], dx: I[pp + k * 5 + 2], dy: I[pp + k * 5 + 3] });
      }
      ex.hb_buffer_destroy(buf);
      return out;
    };
    // Outline as list of contours, each a list of commands in font units (y up)
    Font.prototype.glyphCommands = function (gid) {
      var svg = this.glyphSvg(gid);
      var cmds = [];
      var re = /([MLQCZ])([^MLQCZ]*)/g, m;
      while ((m = re.exec(svg))) {
        var nums = m[2].match(/-?[\d.]+(?:e-?\d+)?/gi) || [];
        cmds.push({ t: m[1], v: nums.map(Number) });
      }
      return cmds;
    };
    Font.prototype.destroy = function () {
      ex.hb_font_destroy(this.font); ex.hb_face_destroy(this.face); ex.hb_blob_destroy(this.blob);
    };
    return { Font: Font };
  }

  // ---------------------------------------------------------------------------
  // opentype.js fallback font (no WASM)
  // ---------------------------------------------------------------------------
  var MIRROR = { '(': ')', ')': '(', '[': ']', ']': '[', '{': '}', '}': '{', '<': '>', '>': '<', '\u00AB': '\u00BB', '\u00BB': '\u00AB' };

  function OTFont(bytes) {
    var ab = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    this.ot = root.opentype.parse(ab);
    this.upem = this.ot.unitsPerEm;
    this.axes = {};
  }
  OTFont.prototype.setVariations = function () {};
  OTFont.prototype.shape = function (text, rtl) {
    var ot = this.ot, out = [], k, g;
    if (!rtl) {
      var glyphs = ot.stringToGlyphs(text);
      for (k = 0; k < glyphs.length; k++) {
        g = glyphs[k];
        var ax = g.advanceWidth || 0;
        if (k < glyphs.length - 1) ax += ot.getKerningValue(g, glyphs[k + 1]);
        out.push({ g: g.index, cl: -1, ax: ax, dx: 0, dy: 0, ch: g.unicode });
      }
      return out;
    }
    // RTL: shape each Arabic-script word on its own (opentype.js returns a
    // single word in visual order), then lay the tokens out right-to-left.
    // ZWNJ/ZWJ split words and are dropped (zero width).
    var tokens = text.match(/[\u0610-\u061A\u0620-\u065F\u066E-\u06D3\u06D5-\u06EF\u06FA-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]+|[^\u0610-\u061A\u0620-\u065F\u066E-\u06D3\u06D5-\u06EF\u06FA-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]/g) || [];
    for (var t = tokens.length - 1; t >= 0; t--) {
      var tok = tokens[t];
      if (tok === '\u200C' || tok === '\u200D') continue;
      if (tok.length === 1 && MIRROR[tok]) tok = MIRROR[tok];
      var gs = ot.stringToGlyphs(tok);
      for (k = 0; k < gs.length; k++) {
        g = gs[k];
        out.push({ g: g.index, cl: -1, ax: g.advanceWidth || 0, dx: 0, dy: 0, ch: tok.length === 1 ? tok.charCodeAt(0) : g.unicode });
      }
    }
    return out;
  };
  OTFont.prototype.glyphCommands = function (gid) {
    var g = this.ot.glyphs.get(gid);
    var cmds = [], pc = (g && g.path && g.path.commands) || [];
    for (var i = 0; i < pc.length; i++) {
      var c = pc[i];
      if (c.type === 'M' || c.type === 'L') cmds.push({ t: c.type, v: [c.x, c.y] });
      else if (c.type === 'Q') cmds.push({ t: 'Q', v: [c.x1, c.y1, c.x, c.y] });
      else if (c.type === 'C') cmds.push({ t: 'C', v: [c.x1, c.y1, c.x2, c.y2, c.x, c.y] });
      else if (c.type === 'Z') cmds.push({ t: 'Z', v: [] });
    }
    return cmds;
  };
  OTFont.prototype.destroy = function () {};

  // ---------------------------------------------------------------------------
  // BiDi (simplified UBA: strong R / L, numbers, neutrals)
  // ---------------------------------------------------------------------------
  function charClass(c) {
    var code = c.charCodeAt(0);
    if ((code >= 0x30 && code <= 0x39) || (code >= 0x660 && code <= 0x669) || (code >= 0x6F0 && code <= 0x6F9)) return 'N';
    if ((code >= 0x0590 && code <= 0x08FF) || (code >= 0xFB1D && code <= 0xFDFF) || (code >= 0xFE70 && code <= 0xFEFF)) return 'R';
    if (code === 0x200C || code === 0x200D) return 'J'; // ZWNJ/ZWJ: stick to the surrounding run
    if ((code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A) || (code >= 0xC0 && code <= 0x2AF && code !== 0xD7 && code !== 0xF7) ||
        (code >= 0x370 && code <= 0x58F) || (code >= 0x900 && code < 0x2000) || (code >= 0x2C00 && code < 0xFB1D) || code >= 0x10000) return 'L';
    return 'O'; // neutral: spaces, punctuation, symbols
  }

  function firstStrong(text) {
    for (var i = 0; i < text.length; i++) {
      var k = charClass(text[i]);
      if (k === 'R') return 'rtl';
      if (k === 'L') return 'ltr';
    }
    return null;
  }

  // Split a line into runs [{text, level}] in visual order.
  function bidiRuns(line, baseRtl) {
    var n = line.length, cls = [], i, j;
    for (i = 0; i < n; i++) cls.push(charClass(line[i]));
    // number separators between digits become part of the number
    for (i = 1; i < n - 1; i++) {
      if (cls[i] === 'O' && cls[i - 1] === 'N' && cls[i + 1] === 'N' && /[.,\/:\u066B\u066C\u060C-]/.test(line[i])) cls[i] = 'N';
    }
    // ZWNJ/ZWJ take the class of the previous strong letter
    for (i = 0; i < n; i++) if (cls[i] === 'J') cls[i] = (i > 0 && cls[i - 1] !== 'O') ? cls[i - 1] : (baseRtl ? 'R' : 'L');
    // strong value used for neutral resolution (numbers act like R in RTL context)
    function strong(k) { return k === 'N' ? (baseRtl ? 'R' : 'L') : k; }
    var res = cls.slice();
    i = 0;
    while (i < n) {
      if (cls[i] !== 'O') { i++; continue; }
      j = i; while (j < n && cls[j] === 'O') j++;
      var prev = i > 0 ? strong(cls[i - 1]) : (baseRtl ? 'R' : 'L');
      var next = j < n ? strong(cls[j]) : (baseRtl ? 'R' : 'L');
      var d = (prev === next) ? prev : (baseRtl ? 'R' : 'L');
      for (var k = i; k < j; k++) res[k] = d;
      i = j;
    }
    // levels
    var levels = [];
    for (i = 0; i < n; i++) {
      var c = res[i];
      if (baseRtl) levels.push(c === 'R' ? 1 : 2);
      else {
        if (c === 'R') levels.push(1);
        else if (c === 'N') {
          // number after RTL text is embedded in that RTL run
          var p = i - 1; while (p >= 0 && (res[p] === 'N' || res[p] === 'O')) p--;
          levels.push(p >= 0 && res[p] === 'R' ? 2 : 0);
        } else levels.push(0);
      }
    }
    // group into runs of equal level
    var runs = [];
    i = 0;
    while (i < n) {
      j = i; while (j < n && levels[j] === levels[i]) j++;
      runs.push({ text: line.substring(i, j), level: levels[i] });
      i = j;
    }
    // L2: reverse sequences of runs from highest level down to lowest odd level
    var maxL = 0, minOdd = 99;
    for (i = 0; i < runs.length; i++) {
      maxL = Math.max(maxL, runs[i].level);
      if (runs[i].level % 2 === 1) minOdd = Math.min(minOdd, runs[i].level);
    }
    for (var L = maxL; L >= minOdd && L > 0; L--) {
      i = 0;
      while (i < runs.length) {
        if (runs[i].level < L) { i++; continue; }
        j = i; while (j < runs.length && runs[j].level >= L) j++;
        var seg = runs.slice(i, j).reverse();
        for (var s = 0; s < seg.length; s++) runs[i + s] = seg[s];
        i = j;
      }
    }
    return runs;
  }

  // ---------------------------------------------------------------------------
  // Outline flattening
  // ---------------------------------------------------------------------------
  function flatten(cmds, tol) {
    var contours = [], cur = null, x = 0, y = 0;
    function steps(d) { var n = Math.ceil(Math.sqrt(d / tol)); return Math.max(1, Math.min(64, n)); }
    for (var i = 0; i < cmds.length; i++) {
      var c = cmds[i], v = c.v, k, t, n, mt;
      if (c.t === 'M') {
        if (cur && cur.length > 2) contours.push(cur);
        cur = [[v[0], v[1]]]; x = v[0]; y = v[1];
      } else if (c.t === 'L') {
        if (!cur) cur = [[x, y]];
        cur.push([v[0], v[1]]); x = v[0]; y = v[1];
      } else if (c.t === 'Q') {
        if (!cur) cur = [[x, y]];
        var dqx = x - 2 * v[0] + v[2], dqy = y - 2 * v[1] + v[3];
        n = steps(Math.sqrt(dqx * dqx + dqy * dqy) / 4);
        for (k = 1; k <= n; k++) {
          t = k / n; mt = 1 - t;
          cur.push([mt * mt * x + 2 * mt * t * v[0] + t * t * v[2], mt * mt * y + 2 * mt * t * v[1] + t * t * v[3]]);
        }
        x = v[2]; y = v[3];
      } else if (c.t === 'C') {
        if (!cur) cur = [[x, y]];
        var ax = x - 2 * v[0] + v[2], ay = y - 2 * v[1] + v[3];
        var bx = v[0] - 2 * v[2] + v[4], by = v[1] - 2 * v[3] + v[5];
        n = steps(0.75 * Math.max(Math.sqrt(ax * ax + ay * ay), Math.sqrt(bx * bx + by * by)));
        for (k = 1; k <= n; k++) {
          t = k / n; mt = 1 - t;
          cur.push([
            mt * mt * mt * x + 3 * mt * mt * t * v[0] + 3 * mt * t * t * v[2] + t * t * t * v[4],
            mt * mt * mt * y + 3 * mt * mt * t * v[1] + 3 * mt * t * t * v[3] + t * t * t * v[5]
          ]);
        }
        x = v[4]; y = v[5];
      } else if (c.t === 'Z') {
        if (cur && cur.length > 2) contours.push(cur);
        cur = null;
      }
    }
    if (cur && cur.length > 2) contours.push(cur);
    return contours;
  }

  // ---------------------------------------------------------------------------
  // Engine
  // ---------------------------------------------------------------------------
  var hb = null;
  var backend = null;

  var Engine = {
    backend: function () { return backend; },

    init: function (wasmB64) {
      if (typeof root.WebAssembly === 'object' && wasmB64) {
        var bytes = b64ToBytes(wasmB64);
        return root.WebAssembly.instantiate(bytes, {}).then(function (res) {
          hb = HB(res.instance); backend = 'harfbuzz';
          return backend;
        }, function (err) {
          if (root.opentype) { backend = 'opentype'; return backend; }
          throw err;
        });
      }
      backend = root.opentype ? 'opentype' : null;
      return backend ? Promise.resolve(backend) : Promise.reject(new Error('No text engine available'));
    },

    // bytes: Uint8Array
    loadFont: function (bytes, index) {
      var f;
      if (backend === 'harfbuzz') f = new hb.Font(bytes, index || 0);
      else {
        if (index) throw new Error('TTC collections need SketchUp 2019 or newer');
        f = new OTFont(bytes);
      }
      f.cache = {};
      f.varKey = '';
      return f;
    },

    /*
     * opts:
     *  text, baseDir ('auto'|'rtl'|'ltr'), align ('right'|'center'|'left'),
     *  lineSpacing (x em), wordSpacing (em), letterSpacing (em, latin only),
     *  variations {}, persianDigits, slant (deg), bold (em), quality,
     *  heightIn, heightMode ('em'|'ink'), arcIn (inches, 0 = flat), minSegIn
     * returns { polys: [{o:[[x,y]..], h:[[[x,y]..]..]}], bbox, width, height, glyphCount }
     */
    layout: function (font, opts) {
      var upem = font.upem;
      var text = String(opts.text || '').replace(/\r\n?/g, '\n');
      if (opts.persianDigits) text = text.replace(/[0-9]/g, function (d) { return String.fromCharCode(0x6F0 + (+d)); });
      var lines = text.split('\n');
      var baseDir = opts.baseDir || 'auto';
      var baseRtl = baseDir === 'rtl' || (baseDir === 'auto' && firstStrong(text) !== 'ltr');

      var varKey = JSON.stringify(opts.variations || {});
      if (varKey !== font.varKey) { font.setVariations(opts.variations || {}); font.cache = {}; font.varKey = varKey; }

      var tolEm = { low: 0.006, medium: 0.0025, high: 0.001 }[opts.quality || 'medium'] || 0.0025;
      var tol = tolEm * upem;
      var lineH = (opts.lineSpacing || 1.5) * upem;
      var wordSp = (opts.wordSpacing || 0) * upem;
      var letSp = (opts.letterSpacing || 0) * upem;

      // 1. shape lines into positioned glyphs
      var shaped = [], maxW = 0, glyphCount = 0, missing = [];
      for (var li = 0; li < lines.length; li++) {
        var lineRtl = baseDir === 'auto' ? (firstStrong(lines[li]) ? firstStrong(lines[li]) === 'rtl' : baseRtl) : baseRtl;
        var runs = lines[li].length ? bidiRuns(lines[li], lineRtl) : [];
        var x = 0, glyphs = [];
        for (var r = 0; r < runs.length; r++) {
          var run = runs[r], rtl = run.level % 2 === 1;
          var gl = font.shape(run.text, rtl, rtl ? 'fa' : null);
          for (var gi = 0; gi < gl.length; gi++) {
            var g = gl[gi];
            var ch = g.cl >= 0 ? run.text.charAt(g.cl) : (g.ch ? String.fromCharCode(g.ch) : '');
            if (g.g === 0 && ch !== '\u200C' && ch !== '\u200D') missing.push(ch);
            glyphs.push({ g: g.g, x: x + g.dx, y: g.dy });
            x += g.ax;
            if (ch === ' ' || ch === '\u00A0') x += wordSp;
            else if (!rtl && letSp) x += letSp;
          }
        }
        glyphCount += glyphs.length;
        shaped.push({ glyphs: glyphs, width: x });
        if (x > maxW) maxW = x;
      }

      // 2. outlines -> clipper paths (em * CS)
      var slant = Math.tan((opts.slant || 0) * Math.PI / 180);
      var paths = [];
      var align = opts.align || 'right';
      for (li = 0; li < shaped.length; li++) {
        var L = shaped[li];
        var off = align === 'right' ? maxW - L.width : (align === 'center' ? (maxW - L.width) / 2 : 0);
        var baseY = -li * lineH;
        for (gi = 0; gi < L.glyphs.length; gi++) {
          var G = L.glyphs[gi];
          var contours = font.cache[G.g];
          if (!contours) { contours = flatten(font.glyphCommands(G.g), tol); font.cache[G.g] = contours; }
          for (var ci = 0; ci < contours.length; ci++) {
            var cpts = contours[ci], path = [];
            for (var pi = 0; pi < cpts.length; pi++) {
              var px = cpts[pi][0] + G.x + off, py = cpts[pi][1] + G.y + baseY;
              px += py * slant;
              path.push({ X: Math.round(px / upem * CS), Y: Math.round(py / upem * CS) });
            }
            paths.push(path);
          }
        }
      }

      // 3. union (non-zero) + optional bold offset
      var C = ClipperLib;
      var tree = new C.PolyTree();
      if (paths.length) {
        var solutionPaths;
        var clip = new C.Clipper();
        clip.StrictlySimple = true;
        clip.AddPaths(paths, C.PolyType.ptSubject, true);
        if (opts.bold) {
          solutionPaths = new C.Paths();
          clip.Execute(C.ClipType.ctUnion, solutionPaths, C.PolyFillType.pftNonZero, C.PolyFillType.pftNonZero);
          var co = new C.ClipperOffset(2, tolEm * CS);
          co.AddPaths(solutionPaths, C.JoinType.jtRound, C.EndType.etClosedPolygon);
          var offPaths = new C.Paths();
          co.Execute(offPaths, opts.bold * CS);
          clip = new C.Clipper();
          clip.StrictlySimple = true;
          clip.AddPaths(offPaths, C.PolyType.ptSubject, true);
        }
        clip.Execute(C.ClipType.ctUnion, tree, C.PolyFillType.pftNonZero, C.PolyFillType.pftNonZero);
      }

      // 4. collect polygons (outer + holes), DFS so islands come after parents
      var polys = [];
      function walk(node) {
        var kids = node.Childs();
        for (var i = 0; i < kids.length; i++) {
          var outer = kids[i];
          if (outer.IsOpen) continue;
          var holes = [];
          var hk = outer.Childs();
          for (var j = 0; j < hk.length; j++) holes.push(hk[j].Contour());
          polys.push({ o: outer.Contour(), h: holes });
          for (j = 0; j < hk.length; j++) walk(hk[j]);
        }
      }
      walk(tree);

      // 5. bbox in em
      var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
      function grow(ring) {
        for (var i = 0; i < ring.length; i++) {
          var p = ring[i];
          if (p.X < minX) minX = p.X; if (p.X > maxX) maxX = p.X;
          if (p.Y < minY) minY = p.Y; if (p.Y > maxY) maxY = p.Y;
        }
      }
      for (var q = 0; q < polys.length; q++) grow(polys[q].o);
      if (!polys.length) return { polys: [], bbox: [0, 0, 0, 0], width: 0, height: 0, glyphCount: glyphCount, missing: missing };

      // 6. scale to inches
      var heightIn = opts.heightIn || 1;
      var inkH = (maxY - minY) / CS;
      var s = (opts.heightMode === 'ink' && inkH > 0) ? heightIn / inkH : heightIn; // inches per em
      var k2 = s / CS;
      var cx = (minX + maxX) / 2 * k2;
      var R = opts.arcIn || 0;
      var minSeg = opts.minSegIn || 0.002;

      function transformRing(ring) {
        var out = [], i, p, px, py;
        var pts = [];
        for (i = 0; i < ring.length; i++) pts.push([ring[i].X * k2, ring[i].Y * k2]);
        if (R) {
          // densify so bending stays smooth
          var maxLen = Math.abs(R) * 0.02, dense = [];
          for (i = 0; i < pts.length; i++) {
            var a = pts[i], b = pts[(i + 1) % pts.length];
            dense.push(a);
            var dl = Math.sqrt((b[0] - a[0]) * (b[0] - a[0]) + (b[1] - a[1]) * (b[1] - a[1]));
            var n = Math.floor(dl / maxLen);
            for (var t = 1; t <= n; t++) dense.push([a[0] + (b[0] - a[0]) * t / (n + 1), a[1] + (b[1] - a[1]) * t / (n + 1)]);
          }
          pts = [];
          for (i = 0; i < dense.length; i++) {
            px = dense[i][0]; py = dense[i][1];
            var th = (px - cx) / R, rr = R + py;
            pts.push([cx + rr * Math.sin(th), -R + rr * Math.cos(th)]);
          }
        }
        for (i = 0; i < pts.length; i++) {
          p = pts[i];
          if (out.length) {
            var l = out[out.length - 1];
            if (Math.abs(p[0] - l[0]) < minSeg && Math.abs(p[1] - l[1]) < minSeg &&
                (p[0] - l[0]) * (p[0] - l[0]) + (p[1] - l[1]) * (p[1] - l[1]) < minSeg * minSeg) continue;
          }
          out.push(p);
        }
        while (out.length > 2) {
          var f = out[0], e = out[out.length - 1];
          if ((f[0] - e[0]) * (f[0] - e[0]) + (f[1] - e[1]) * (f[1] - e[1]) < minSeg * minSeg) out.pop(); else break;
        }
        return out.length >= 3 ? out : null;
      }

      var result = [];
      var bx0 = Infinity, by0 = Infinity, bx1 = -Infinity, by1 = -Infinity;
      for (q = 0; q < polys.length; q++) {
        var o = transformRing(polys[q].o);
        if (!o) continue;
        var hs = [];
        for (var h = 0; h < polys[q].h.length; h++) { var hr = transformRing(polys[q].h[h]); if (hr) hs.push(hr); }
        for (var z = 0; z < o.length; z++) {
          var P = o[z];
          if (P[0] < bx0) bx0 = P[0]; if (P[0] > bx1) bx1 = P[0];
          if (P[1] < by0) by0 = P[1]; if (P[1] > by1) by1 = P[1];
        }
        result.push({ o: o, h: hs });
      }
      if (!result.length) return { polys: [], bbox: [0, 0, 0, 0], width: 0, height: 0, glyphCount: glyphCount, missing: missing };

      // 7. anchor: bottom of bbox at y=0; x by alignment
      var ox = align === 'right' ? bx1 : (align === 'center' ? (bx0 + bx1) / 2 : bx0);
      var oy = by0;
      function shift(ring) {
        for (var i = 0; i < ring.length; i++) {
          ring[i][0] = Math.round((ring[i][0] - ox) * 1e5) / 1e5;
          ring[i][1] = Math.round((ring[i][1] - oy) * 1e5) / 1e5;
        }
      }
      for (q = 0; q < result.length; q++) {
        shift(result[q].o);
        for (h = 0; h < result[q].h.length; h++) shift(result[q].h[h]);
      }
      return {
        polys: result,
        bbox: [bx0 - ox, by0 - oy, bx1 - ox, by1 - oy],
        width: bx1 - bx0,
        height: by1 - by0,
        glyphCount: glyphCount,
        missing: missing
      };
    },

    _bidiRuns: bidiRuns
  };

  root.PTEngine = Engine;
  if (typeof module !== 'undefined' && module.exports) module.exports = Engine;
})(typeof window !== 'undefined' ? window : global);
