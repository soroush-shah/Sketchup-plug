/* Banian Floor Studio - dialog logic. ES2015 subset (works in SketchUp 2017+). */
(function () {
  'use strict';

  var DEF = {
    mode: '3d', pattern: 'grid', lang: 'en', units: 'mm',
    length: 600, width: 600, gap: 3, offset: 0.5, wood_min: 600, wood_max: 1800, length_step: 0, stagger: 200,
    chevron_angle: 45, basket_n: 3, small: 300, jitter: 0.8, tilt: 4,
    angle: 0, anchor: 'corner', anchor_pt: null, anchor_center: false, align: 'edge', offset_x: 0, offset_y: 0, flip: false,
    thickness: 10, grout_depth: 2, profile: 'chamfer', profile_size: 1.5,
    materials: [], weights: [], mat_mode: 'random', shades: 1, shade_amount: 0.08,
    grout_mat: '', grout_color: '#8a8580', tex_random: true, tex_variants: 6, tex_rot: '180',
    imp_angle: 0, imp_height: 0, min_piece: 0, seed: 1, paint: false, paint_grout: false, keep_face: true, tex_ppm: 2,
    per: {}
  };
  var PATTERNS = ['grid', 'brick', 'wood', 'herringbone', 'chevron', 'basket', 'hexagon', 'hopscotch', 'voronoi', 'siding'];
  var SIZE_KEYS = ['length', 'width', 'small', 'gap', 'wood_min', 'wood_max', 'length_step', 'stagger', 'offset',
                   'chevron_angle', 'basket_n', 'jitter', 'tilt', 'thickness', 'profile', 'profile_size'];
  var PD = {
    grid: { length: 600, width: 600, gap: 3 },
    brick: { length: 600, width: 300, gap: 3, offset: 0.5 },
    wood: { width: 190, wood_min: 600, wood_max: 1800, length_step: 0, stagger: 200, gap: 1, thickness: 14, profile: 'chamfer', profile_size: 1 },
    herringbone: { length: 600, width: 100, gap: 1, thickness: 14, profile: 'chamfer', profile_size: 1 },
    chevron: { length: 600, width: 100, gap: 1, chevron_angle: 45, thickness: 14, profile: 'chamfer', profile_size: 1 },
    basket: { length: 300, basket_n: 3, gap: 2 },
    hexagon: { length: 200, gap: 3 },
    hopscotch: { length: 600, small: 300, gap: 3 },
    voronoi: { length: 500, gap: 15, jitter: 0.8, thickness: 30, profile: 'round', profile_size: 6 },
    siding: { length: 3000, width: 150, gap: 0, offset: 0.3333333333, tilt: 4, thickness: 18, profile: 'square' }
  };
  var UNIT = { mm: 1, cm: 10, m: 1000, 'in': 25.4 };
  var DEC = { mm: 1, cm: 2, m: 4, 'in': 3 };
  var LEN_LABEL = { hexagon: 'size_hex', voronoi: 'size_stone', hopscotch: 'size_large', basket: 'size_block' };

  var S = clone(DEF);
  var SRC = { kind: 'none', count: 0 };
  var MATS = [];
  var PREV = null;
  var busy = false;
  var tPrev = 0, tSave = 0, tToast = 0;
  var VIEW = null, DRAG = null;

  function $(s) { return document.querySelector(s); }
  function $$(s) { return Array.prototype.slice.call(document.querySelectorAll(s)); }
  function clone(o) { return JSON.parse(JSON.stringify(o)); }
  function merge(a, b) { var o = clone(a); if (b) Object.keys(b).forEach(function (k) { o[k] = b[k]; }); return o; }
  function T(k, vars) {
    var s = (I18N[S.lang] && I18N[S.lang][k]) || I18N.en[k] || k;
    if (vars) Object.keys(vars).forEach(function (v) { s = s.replace('{' + v + '}', vars[v]); });
    return s;
  }

  function call(name, arg) {
    if (window.sketchup && typeof window.sketchup[name] === 'function') window.sketchup[name](arg);
    else if (window.MOCK && window.MOCK[name]) window.MOCK[name](arg);
  }

  // ---------------- pattern icons ----------------
  function poly(pts) { return '<polygon points="' + pts.map(function (p) { return p[0].toFixed(1) + ',' + p[1].toFixed(1); }).join(' ') + '"/>'; }
  function rect(x, y, w, h) { return [[x, y], [x + w, y], [x + w, y + h], [x, y + h]]; }
  function rot(p, a, c) { var s = Math.sin(a), k = Math.cos(a); var x = p[0] - c[0], y = p[1] - c[1]; return [c[0] + x * k - y * s, c[1] + x * s + y * k]; }
  function iconShapes(name) {
    var out = [], i, j, g = 1.6;
    if (name === 'grid') { for (i = 0; i < 3; i++) for (j = 0; j < 3; j++) out.push(rect(2 + i * 12.4, 2 + j * 12.4, 10.8, 10.8)); }
    else if (name === 'brick' || name === 'siding') {
      var h = name === 'siding' ? 6.4 : 8.4;
      for (j = 0; j < 6; j++) for (i = -1; i < 3; i++) out.push(rect(i * 18 + (j % 2) * 9, 1 + j * (h + g), 18 - g, h));
    } else if (name === 'wood') {
      var L = [[14, 22, 9], [8, 19, 18], [20, 12, 13], [11, 25, 9], [17, 10, 18]];
      for (j = 0; j < 5; j++) { var x = -2; for (i = 0; i < 3; i++) { out.push(rect(x, 1 + j * 8, L[j][i] - g, 6.4)); x += L[j][i]; } }
    } else if (name === 'herringbone') {
      var l = 15, w = 5, c = [20, 20];
      for (var a = -6; a < 8; a++) for (var b = -3; b < 4; b++) {
        var ox = a * w + b * l, oy = a * w - b * l;
        out.push(rect(ox, oy, l - g, w - g).map(function (p) { return rot([p[0] - 10, p[1] - 10], -Math.PI / 4, [0, 0]); }));
        out.push(rect(ox + l, oy + w - l, w - g, l - g).map(function (p) { return rot([p[0] - 10, p[1] - 10], -Math.PI / 4, [0, 0]); }));
      }
      out = out.map(function (pp) { return pp.map(function (p) { return [p[0] + c[0], p[1] + c[1]]; }); });
    } else if (name === 'chevron') {
      var cw = 10, hh = 7;
      for (i = 0; i < 4; i++) for (j = -2; j < 7; j++) {
        var x0 = i * (cw + 0.8), y0 = j * (hh + g), up = i % 2 === 0;
        out.push(up ? [[x0, y0 + cw], [x0 + cw, y0], [x0 + cw, y0 + hh], [x0, y0 + cw + hh]] : [[x0, y0], [x0 + cw, y0 + cw], [x0 + cw, y0 + cw + hh], [x0, y0 + hh]]);
      }
    } else if (name === 'basket') {
      var B = 12.6, n = 3, sw = (B - 2 * 1.2) / 3;
      for (i = 0; i < 3; i++) for (j = 0; j < 3; j++) for (var s = 0; s < n; s++) {
        var bx = 1 + i * (B + 1.2), by = 1 + j * (B + 1.2);
        out.push((i + j) % 2 === 0 ? rect(bx, by + s * (sw + 1.2), B, sw) : rect(bx + s * (sw + 1.2), by, sw, B));
      }
    } else if (name === 'hexagon') {
      var F = 12, R = F / Math.sqrt(3), Fp = F + g, Rp = Fp / Math.sqrt(3);
      for (i = -1; i < 5; i++) for (j = -1; j < 5; j++) {
        var cx = i * 1.5 * Rp, cy = j * Fp + (i % 2 ? Fp / 2 : 0), hp = [];
        for (var k = 0; k < 6; k++) hp.push([cx + R * Math.cos(k * Math.PI / 3), cy + R * Math.sin(k * Math.PI / 3)]);
        out.push(hp);
      }
    } else if (name === 'hopscotch') {
      var A = 13, Bs = 6, ap = A + g, bp = Bs + g;
      for (i = -3; i < 5; i++) for (j = -3; j < 5; j++) {
        var px = i * ap - j * bp, py = i * bp + j * ap;
        out.push(rect(px, py, A, A)); out.push(rect(px + ap, py, Bs, Bs));
      }
    } else if (name === 'voronoi') {
      var P = [[6, 7], [19, 4], [33, 8], [9, 20], [22, 18], [35, 22], [5, 34], [18, 32], [31, 35], [27, 27], [14, 12]];
      P.forEach(function (c) {
        var pg = [[c[0] - 30, c[1] - 30], [c[0] + 30, c[1] - 30], [c[0] + 30, c[1] + 30], [c[0] - 30, c[1] + 30]];
        P.forEach(function (q) {
          if (q === c) return;
          var nx = q[0] - c[0], ny = q[1] - c[1], len = Math.sqrt(nx * nx + ny * ny); nx /= len; ny /= len;
          var m = ((c[0] + q[0]) / 2) * nx + ((c[1] + q[1]) / 2) * ny - 0.9;
          var res = [];
          for (var t = 0; t < pg.length; t++) {
            var cur = pg[t], prv = pg[(t + pg.length - 1) % pg.length];
            var dc = cur[0] * nx + cur[1] * ny - m, dp = prv[0] * nx + prv[1] * ny - m;
            if (dc <= 0) { if (dp > 0) { var f = dp / (dp - dc); res.push([prv[0] + (cur[0] - prv[0]) * f, prv[1] + (cur[1] - prv[1]) * f]); } res.push(cur); }
            else if (dp <= 0) { var f2 = dp / (dp - dc); res.push([prv[0] + (cur[0] - prv[0]) * f2, prv[1] + (cur[1] - prv[1]) * f2]); }
          }
          pg = res;
        });
        out.push(pg);
      });
    }
    return out;
  }
  function iconSVG(name) {
    var id = 'clip_' + name;
    return '<svg viewBox="0 0 40 40"><defs><clipPath id="' + id + '"><rect x="1" y="1" width="38" height="38" rx="5"/></clipPath></defs>' +
      '<g clip-path="url(#' + id + ')" fill="currentColor" fill-opacity=".85">' + iconShapes(name).map(poly).join('') + '</g></svg>';
  }

  function buildPatterns() {
    var box = $('#patterns');
    box.innerHTML = PATTERNS.map(function (p) {
      return '<div class="pat" data-pat="' + p + '">' + iconSVG(p) + '<span data-t="pat_' + p + '"></span></div>';
    }).join('');
    $$('.pat').forEach(function (el) {
      el.addEventListener('click', function () { setPattern(el.getAttribute('data-pat')); });
    });
  }

  function setPattern(p) {
    if (p === S.pattern) return;
    var cur = {};
    SIZE_KEYS.forEach(function (k) { cur[k] = S[k]; });
    S.per[S.pattern] = cur;
    var next = S.per[p] || PD[p] || {};
    Object.keys(next).forEach(function (k) { S[k] = next[k]; });
    S.pattern = p;
    render();
    changed();
  }

  // ---------------- fields ----------------
  function fmt(v, kind) {
    if (kind === 'len') {
      var d = DEC[S.units];
      var x = v / UNIT[S.units];
      return String(Math.round(x * Math.pow(10, d)) / Math.pow(10, d));
    }
    return String(v);
  }

  function readField(el) {
    var k = el.getAttribute('data-k'), kind = el.getAttribute('data-kind');
    if (kind === 'bool') { S[k] = el.checked; return true; }
    if (kind === 'str') { S[k] = el.value; return true; }
    var v = parseFloat(String(el.value).replace(',', '.').replace(/[۰-۹]/g, function (d) { return '۰۱۲۳۴۵۶۷۸۹'.indexOf(d); }));
    if (isNaN(v)) return false;
    if (kind === 'len') v = v * UNIT[S.units];
    if (kind === 'int') v = Math.round(v);
    if (k === 'basket_n') v = Math.max(1, Math.min(12, v));
    if (k === 'shades') v = Math.max(1, Math.min(8, v));
    if ((k === 'length' || k === 'width' || k === 'small' || k === 'wood_min' || k === 'wood_max') && v <= 0) return false;
    S[k] = v;
    return true;
  }

  function bindFields() {
    $$('[data-k]').forEach(function (el) {
      var ev = (el.tagName === 'SELECT' || el.type === 'checkbox' || el.type === 'color') ? 'change' : 'input';
      el.addEventListener(ev, function () { if (readField(el)) { if (el.tagName === 'SELECT' || el.type === 'checkbox') render(); changed(); } });
      if (ev === 'input') el.addEventListener('blur', function () { renderFields(); });
    });
  }

  function renderFields() {
    $$('[data-k]').forEach(function (el) {
      if (document.activeElement === el && el.type !== 'range') return;
      var k = el.getAttribute('data-k'), kind = el.getAttribute('data-kind');
      if (kind === 'bool') el.checked = !!S[k];
      else if (el.tagName === 'SELECT' && k === 'offset') {
        var best = null, bd = 9;
        Array.prototype.forEach.call(el.options, function (o) { var d = Math.abs(parseFloat(o.value) - S.offset); if (d < bd) { bd = d; best = o.value; } });
        el.value = best;
      } else el.value = fmt(S[k], kind);
    });
    $$('.u').forEach(function (el) { el.textContent = S.units; });
  }

  function vis() {
    $$('[data-p]').forEach(function (el) { el.classList.toggle('hide', el.getAttribute('data-p').split(' ').indexOf(S.pattern) < 0); });
    $$('[data-anchor]').forEach(function (el) { el.classList.toggle('hide', S.anchor !== el.getAttribute('data-anchor')); });
    $$('[data-m]').forEach(function (el) {
      var ok = el.getAttribute('data-m').split(' ').indexOf(S.mode) >= 0;
      if (el.hasAttribute('data-p') && el.getAttribute('data-p').split(' ').indexOf(S.pattern) < 0) ok = false;
      el.classList.toggle('hide', !ok);
    });
  }

  function texts() {
    document.documentElement.lang = S.lang;
    document.documentElement.dir = S.lang === 'fa' ? 'rtl' : 'ltr';
    $('#lang').textContent = S.lang === 'fa' ? 'EN' : 'فا';
    $$('[data-t]').forEach(function (el) { el.textContent = T(el.getAttribute('data-t')); });
    $$('[data-tl]').forEach(function (el) {
      var k = el.getAttribute('data-tl');
      el.textContent = T(k === 'length' ? (LEN_LABEL[S.pattern] || 'length') : k);
    });
    $('#mode_hint').textContent = T('hint_' + S.mode);
  }

  function render() {
    texts();
    $$('#modes button').forEach(function (b) { b.classList.toggle('on', b.getAttribute('data-mode') === S.mode); });
    $$('.pat').forEach(function (b) { b.classList.toggle('on', b.getAttribute('data-pat') === S.pattern); });
    $('#units').value = S.units;
    renderFields();
    vis();
    renderMats();
    renderSource();
    renderStats();
    applyLabel();
  }

  function applyLabel() {
    var b = $('#apply');
    b.disabled = busy;
    if (busy) { b.textContent = T('working'); return; }
    b.textContent = (SRC.kind === 'group' && S.mode === '3d') ? T('apply_update') : T('apply_' + S.mode);
  }

  function renderSource() {
    var s = SRC.kind === 'group' ? T('src_group') : SRC.kind === 'face' ? T('src_face', { n: SRC.count }) : T('src_none');
    if (PREV && PREV.curved && SRC.kind !== 'none') s += ' · ' + T('src_curved');
    $('#src').textContent = s;
  }

  function renderStats() {
    var el = $('#stats');
    if (!PREV) { el.textContent = ''; return; }
    var parts = [T('st_full') + ': ' + PREV.full, T('st_cut') + ': ' + PREV.cut, T('st_area') + ': ' + PREV.area + ' m²'];
    el.innerHTML = parts.join(' · ') + (PREV.dense ? '<br>' + T('st_dense') : '') +
      (PREV.overlap ? '<br><b>' + T('warn_overlap') + '</b>' : '');
  }

  // ---------------- materials ----------------
  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }

  function renderMats() {
    var box = $('#matlist');
    if (!MATS.length) { box.innerHTML = '<div class="empty">' + T('no_mats') + '</div>'; }
    else {
      box.innerHTML = MATS.map(function (m, i) {
        var idx = S.materials.indexOf(m.name), on = idx >= 0;
        return '<div class="mat' + (on ? ' on' : '') + '" data-i="' + i + '"><span class="sw" style="background:' + m.color + '"></span>' +
          '<span class="nm">' + esc(m.label) + '</span>' + (m.textured ? '<span class="tx">' + m.tw + '×' + m.th + '</span>' : '') +
          (on ? '<input class="w" value="' + (S.weights[idx] == null ? 1 : S.weights[idx]) + '" title="weight">' : '') + '</div>';
      }).join('');
      $$('.mat').forEach(function (el) {
        el.addEventListener('click', function (e) {
          if (e.target.classList.contains('w')) return;
          var m = MATS[+el.getAttribute('data-i')], idx = S.materials.indexOf(m.name);
          if (idx >= 0) { S.materials.splice(idx, 1); S.weights.splice(idx, 1); }
          else { S.materials.push(m.name); S.weights.push(1); }
          renderMats(); changed();
        });
        var w = el.querySelector('.w');
        if (w) w.addEventListener('input', function () {
          var m = MATS[+el.getAttribute('data-i')], idx = S.materials.indexOf(m.name), v = parseFloat(w.value);
          if (idx >= 0 && !isNaN(v) && v >= 0) { S.weights[idx] = v; changed(); }
        });
      });
    }
    var gs = $('.matsel');
    var cur = S.grout_mat;
    gs.innerHTML = '<option value="">' + T('grout_custom') + '</option>' + MATS.map(function (m) {
      return '<option value="' + esc(m.name) + '">' + esc(m.label) + '</option>';
    }).join('');
    gs.value = cur;
    if (gs.value !== cur) { gs.value = ''; S.grout_mat = ''; }
  }

  // ---------------- preview ----------------
  function cssVar(n) { return getComputedStyle(document.documentElement).getPropertyValue(n).trim(); }

  function draw() {
    var cv = $('#cv'), r = cv.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
    cv.width = Math.max(1, Math.round(r.width * dpr)); cv.height = Math.max(1, Math.round(r.height * dpr));
    var c = cv.getContext('2d');
    c.setTransform(dpr, 0, 0, dpr, 0, 0);
    c.clearRect(0, 0, r.width, r.height);
    if (!PREV) return;
    var o = PREV.region.outer, minx = 1e18, miny = 1e18, maxx = -1e18, maxy = -1e18;
    o.forEach(function (p) { minx = Math.min(minx, p[0]); maxx = Math.max(maxx, p[0]); miny = Math.min(miny, p[1]); maxy = Math.max(maxy, p[1]); });
    var pad = 14, bw = maxx - minx || 1, bh = maxy - miny || 1;
    var s = Math.min((r.width - 2 * pad) / bw, (r.height - 2 * pad - 30) / bh);
    var ox = (r.width - bw * s) / 2, oy = 14 + (r.height - 30 - bh * s) / 2;
    function X(x) { return ox + (x - minx) * s; }
    function Y(y) { return oy + (maxy - y) * s; }
    function loop(pts) { c.moveTo(X(pts[0][0]), Y(pts[0][1])); for (var i = 1; i < pts.length; i++) c.lineTo(X(pts[i][0]), Y(pts[i][1])); c.closePath(); }
    function regionPath() { c.beginPath(); loop(o); PREV.region.holes.forEach(loop); }
    var paint = S.mode !== 'divide' || S.paint;
    var gcol = (S.mode !== 'divide' || S.paint_grout) ? PREV.grout : '#ffffff';
    regionPath(); c.fillStyle = gcol; c.fill('evenodd');
    c.save(); regionPath(); c.clip('evenodd');
    var thin = (S.gap * s) < 0.8;
    var line = cssVar('--text') || '#222';
    PREV.tiles.forEach(function (t) {
      c.beginPath(); c.moveTo(X(t[2]), Y(t[3]));
      for (var i = 4; i < t.length; i += 2) c.lineTo(X(t[i]), Y(t[i + 1]));
      c.closePath();
      c.fillStyle = paint ? (PREV.palette[t[1]] || '#ddd') : '#f4f4f2';
      c.globalAlpha = t[0] === 1 ? 0.82 : 1;
      c.fill();
      c.globalAlpha = 1;
      if (thin || !paint) { c.strokeStyle = 'rgba(0,0,0,.28)'; c.lineWidth = 0.6; c.stroke(); }
    });
    c.restore();
    regionPath(); c.strokeStyle = line; c.lineWidth = 1.2; c.stroke();
    VIEW = { s: s, ox: ox, oy: oy, minx: minx, maxy: maxy };
    var mk = DRAG || PREV.marker;
    if (mk) {
      var mx = X(mk[0]), my = Y(mk[1]), acc = cssVar('--accent') || '#0f766e';
      c.lineWidth = 3; c.strokeStyle = '#fff';
      c.beginPath(); c.arc(mx, my, 6, 0, Math.PI * 2); c.stroke();
      c.lineWidth = 1.6; c.strokeStyle = acc;
      c.beginPath(); c.arc(mx, my, 6, 0, Math.PI * 2); c.stroke();
      c.beginPath(); c.moveTo(mx - 10, my); c.lineTo(mx + 10, my); c.moveTo(mx, my - 10); c.lineTo(mx, my + 10); c.stroke();
    }
  }

  // canvas px -> local mm, snapping to region corners
  function canvasToLocal(e) {
    if (!VIEW || !PREV) return null;
    var r = $('#cv').getBoundingClientRect(), px = e.clientX - r.left, py = e.clientY - r.top;
    var best = null, bd = 9;
    [PREV.region.outer].concat(PREV.region.holes).forEach(function (lp) {
      lp.forEach(function (q) {
        var qx = VIEW.ox + (q[0] - VIEW.minx) * VIEW.s, qy = VIEW.oy + (VIEW.maxy - q[1]) * VIEW.s;
        var d = Math.sqrt((qx - px) * (qx - px) + (qy - py) * (qy - py));
        if (d < bd) { bd = d; best = [q[0], q[1]]; }
      });
    });
    if (best) return best;
    return [VIEW.minx + (px - VIEW.ox) / VIEW.s, VIEW.maxy - (py - VIEW.oy) / VIEW.s];
  }

  function bindCanvas() {
    var cv = $('#cv');
    cv.addEventListener('mousedown', function (e) { var p = canvasToLocal(e); if (!p) return; DRAG = p; draw(); });
    window.addEventListener('mousemove', function (e) { if (!DRAG) return; var p = canvasToLocal(e); if (p) { DRAG = p; draw(); } });
    window.addEventListener('mouseup', function () {
      if (!DRAG) return;
      var p = DRAG; DRAG = null;
      if (PREV) PREV.marker = p;
      draw();
      call('set_anchor_local', JSON.stringify({ x: p[0], y: p[1], state: S }));
    });
  }

  function changed() {
    clearTimeout(tPrev);
    tPrev = setTimeout(function () { call('preview', JSON.stringify(S)); }, 110);
    clearTimeout(tSave);
    tSave = setTimeout(function () { call('save_state', JSON.stringify(S)); }, 800);
  }

  function toast(msg, err) {
    var el = $('#toast');
    el.textContent = msg; el.classList.toggle('err', !!err); el.classList.add('show');
    clearTimeout(tToast);
    tToast = setTimeout(function () { el.classList.remove('show'); }, err ? 4200 : 2600);
  }

  // ---------------- texture rendering ----------------
  function renderTexture(d) {
    var ppm = Math.max(0.2, Math.min(10, +S.tex_ppm || 2));
    var k = ppm, W = d.w, H = d.h;
    var maxSide = 4096;
    if (Math.max(W, H) * k > maxSide) k = maxSide / Math.max(W, H);
    var pw = Math.max(8, Math.round(W * k)), ph = Math.max(8, Math.round(H * k));
    var kx = pw / W, ky = ph / H;
    var cv = document.createElement('canvas'); cv.width = pw; cv.height = ph;
    var c = cv.getContext('2d');
    c.fillStyle = d.grout; c.fillRect(0, 0, pw, ph);
    d.tiles.forEach(function (t) {
      c.beginPath(); c.moveTo(t[1] * kx, (H - t[2]) * ky);
      for (var i = 3; i < t.length; i += 2) c.lineTo(t[i] * kx, (H - t[i + 1]) * ky);
      c.closePath(); c.fillStyle = d.palette[t[0]] || '#ddd'; c.fill();
    });
    if (!d.seamless) toast(T('seamless_no'));
    call('apply_texture', JSON.stringify({ state: S, png: cv.toDataURL('image/png'), w: W, h: H }));
  }

  // ---------------- messages from Ruby ----------------
  var FS = window.FS = {};
  FS.recv = function (m) {
    switch (m.type) {
      case 'init':
        S = merge(DEF, m.state || {});
        if (!m.state && m.units) S.units = m.units;
        if (!S.per) S.per = {};
        if (m.mode && m.mode !== 'edit') S.mode = m.mode;
        MATS = m.materials || [];
        render(); changed();
        break;
      case 'mode':
        if (m.mode && m.mode !== 'edit') { S.mode = m.mode; render(); changed(); }
        break;
      case 'materials':
        MATS = m.list || []; renderMats();
        break;
      case 'source':
        var wasGroup = SRC.kind === 'group';
        SRC = { kind: m.kind, count: m.count || 0 };
        if (m.kind === 'group' && m.params) {
          var keep = { lang: S.lang, units: S.units, per: S.per };
          S = merge(merge(DEF, m.params), keep);
          S.mode = '3d';
          render();
        } else { renderSource(); applyLabel(); if (wasGroup) render(); }
        changed();
        break;
      case 'preview':
        PREV = m; draw(); renderStats(); renderSource();
        break;
      case 'anchor':
        S.anchor = 'custom'; S.anchor_pt = m.pt; S.offset_x = 0; S.offset_y = 0;
        render(); changed(); toast(T('anchor_set'));
        break;
      case 'texture_data':
        renderTexture(m);
        break;
      case 'done':
        busy = false; applyLabel();
        toast(m.texture ? T('done_tex') : T('done', { t: m.time, f: m.full, c: m.cut }));
        break;
      case 'error':
        busy = false; applyLabel();
        toast(T('err_' + m.code, { d: m.detail || '' }), true);
        break;
    }
  };

  // ---------------- wiring ----------------
  function init() {
    buildPatterns();
    bindFields();
    $$('#modes button').forEach(function (b) {
      b.addEventListener('click', function () { S.mode = b.getAttribute('data-mode'); render(); changed(); });
    });
    $('#lang').addEventListener('click', function () { S.lang = S.lang === 'fa' ? 'en' : 'fa'; render(); changed(); draw(); });
    $('#units').addEventListener('change', function () { S.units = $('#units').value; renderFields(); changed(); });
    $$('#angle_chips button').forEach(function (b) {
      b.addEventListener('click', function () { S.angle = +b.getAttribute('data-a'); renderFields(); changed(); });
    });
    $('#dice').addEventListener('click', function () { S.seed = 1 + Math.floor(Math.random() * 99999); renderFields(); changed(); });
    bindCanvas();
    $('#pick_pt').addEventListener('click', function () { toast(T('pick_now')); call('pick_point', ''); });
    $('#mat_refresh').addEventListener('click', function () { call('materials', ''); });
    $('#reset').addEventListener('click', function () {
      var keep = { lang: S.lang, units: S.units, mode: S.mode };
      S = merge(DEF, keep); S.per = {}; render(); changed();
    });
    $('#apply').addEventListener('click', function () {
      if (busy) return;
      busy = true; applyLabel();
      setTimeout(function () { call('apply', JSON.stringify(S)); }, 20);
    });
    window.addEventListener('resize', function () { draw(); });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && e.target.tagName === 'INPUT') { e.target.blur(); }
      if (e.key === 'Escape') call('close', '');
    });
    render();
    call('ready', '');
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
