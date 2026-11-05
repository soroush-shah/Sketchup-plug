/* Banian Profile Builder - panel logic.
 * Plain ES2015 (works in every SketchUp HtmlDialog since 2017).
 * Ruby <-> JS: sketchup.cmd(JSON) / BPB.receive(object).
 */
(function () {
  'use strict';

  var UNITS = { mm: 1, cm: 10, m: 1000, in: 25.4 };
  var S = {
    lang: 'fa', units: 'mm', tab: 'member', catalog: [], presets: [], library: { profiles: [], assemblies: [] },
    materials: [], member: null, assembly: null, sel: null, qty: [], similar: false, openRow: -1,
    search: '', preview: {}
  };

  // ---------- helpers ------------------------------------------------------
  function $(id) { return document.getElementById(id); }
  function T(k) { var d = I18N[S.lang] || I18N.en; return d[k] !== undefined ? d[k] : (I18N.en[k] || k); }
  function clone(o) { return JSON.parse(JSON.stringify(o)); }
  function esc(s) {
    return String(s === undefined || s === null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function faDigits(s) {
    return String(s).replace(/[۰-۹]/g, function (d) { return '۰۱۲۳۴۵۶۷۸۹'.indexOf(d); })
      .replace(/[٠-٩]/g, function (d) { return '٠١٢٣٤٥٦٧٨٩'.indexOf(d); }).replace(/[٫,]/g, '.');
  }
  function toUnit(mm) {
    var v = Number(mm || 0) / UNITS[S.units];
    var r = S.units === 'mm' ? 10 : 1000;
    return String(Math.round(v * r) / r);
  }
  function fromUnit(str) {
    var v = parseFloat(faDigits(str));
    return isNaN(v) ? null : v * UNITS[S.units];
  }
  function nf(v, d) {
    var n = Number(v || 0);
    return n.toLocaleString(S.lang === 'fa' ? 'fa-IR' : 'en-US', { maximumFractionDigits: d, minimumFractionDigits: 0 });
  }
  var timers = {};
  function debounce(key, ms, fn) {
    clearTimeout(timers[key]);
    timers[key] = setTimeout(fn, ms);
  }
  function send(msg) {
    if (window.sketchup && window.sketchup.cmd) window.sketchup.cmd(JSON.stringify(msg));
  }
  function toast(text, level) {
    var el = $('toast');
    el.textContent = text;
    el.className = 'toast show ' + (level || '');
    debounce('toast', 3500, function () { el.className = 'toast'; });
  }

  function catalogEntry(id) {
    for (var i = 0; i < S.catalog.length; i++) if (S.catalog[i].id === id) return S.catalog[i];
    return null;
  }
  function customEntry(id) {
    var l = S.library.profiles || [];
    for (var i = 0; i < l.length; i++) if (l[i].id === id) return l[i];
    return null;
  }
  function profileName(id, fallback) {
    var e = catalogEntry(id);
    if (e) return S.lang === 'fa' ? e.fa : e.en;
    var c = customEntry(id);
    return c ? c.name : (fallback || id);
  }
  function paramsFor(spec) {
    var e = catalogEntry(spec.profile);
    if (e) return e.params;
    return [{ key: 'w', en: 'Width', fa: 'عرض' }, { key: 'h', en: 'Height', fa: 'ارتفاع' }];
  }

  // ---------- which spec is being edited ----------------------------------
  function editing() { return S.sel && S.sel.kind === S.tab; }
  function current() { return editing() ? S.sel.spec : S[S.tab]; }

  function changed(opts) {
    opts = opts || {};
    var kind = S.tab, spec = current();
    if (editing()) {
      debounce('upd', 180, function () {
        send({ type: 'update_selected', kind: kind, spec: spec, similar: S.similar && kind === 'member' });
      });
    } else {
      debounce('set', 250, function () { send({ type: 'set_spec', kind: kind, spec: spec }); });
    }
    requestPreview();
    if (opts.render) render();
  }

  function requestPreview() {
    var kind = S.tab, spec = current();
    if (!spec || (kind !== 'member' && kind !== 'assembly')) return;
    debounce('prev', 40, function () { send({ type: 'preview', kind: kind, spec: spec }); });
  }

  // ---------- generic field builders ---------------------------------------
  function lenField(label, value, onset, extra) {
    var id = 'f' + Math.random().toString(36).slice(2, 9);
    setTimeout(function () {
      var el = $(id);
      if (!el) return;
      el.addEventListener('input', function () {
        var v = fromUnit(el.value);
        if (v === null) { el.classList.add('bad'); return; }
        el.classList.remove('bad');
        onset(v);
      });
      el.addEventListener('focus', function () { el.select(); });
    }, 0);
    return '<label class="fld' + (extra || '') + '"><span>' + esc(label) + '</span><div class="inp"><input id="' + id +
      '" inputmode="decimal" value="' + esc(toUnit(value)) + '"><em>' + S.units + '</em></div></label>';
  }
  function bind(id, ev, fn) { setTimeout(function () { var el = $(id); if (el) el.addEventListener(ev, fn); }, 0); }
  var uid = 0;
  function nid() { uid += 1; return 'x' + uid; }

  function materialSelect(value, onset) {
    var id = nid();
    var opts = '<option value="">' + esc(T('none')) + '</option>';
    var list = S.materials.slice();
    ['BPB Wood', 'BPB Metal', 'BPB Glass', 'BPB White', 'BPB Concrete'].forEach(function (m) {
      if (list.indexOf(m) < 0) list.push(m);
    });
    if (value && list.indexOf(value) < 0) list.push(value);
    list.forEach(function (m) {
      opts += '<option' + (m === value ? ' selected' : '') + ' value="' + esc(m) + '">' + esc(m) + '</option>';
    });
    bind(id, 'change', function (e) { onset(e.target.value); });
    return '<label class="fld"><span>' + esc(T('material')) + '</span><select id="' + id + '">' + opts + '</select></label>';
  }

  function anchorGrid(value, onset) {
    var id = nid();
    var h = '<div class="anchor" id="' + id + '">';
    ['tl', 'tc', 'tr', 'ml', 'mc', 'mr', 'bl', 'bc', 'br'].forEach(function (a) {
      h += '<button data-a="' + a + '" title="' + esc(T('anchors')[a]) + '" class="' + (a === value ? 'on' : '') + '"></button>';
    });
    h += '</div>';
    bind(id, 'click', function (e) {
      var a = e.target.getAttribute('data-a');
      if (a) onset(a);
    });
    return h;
  }

  function rotationButtons(value, onset) {
    var id = nid();
    var h = '<div class="seg" id="' + id + '">';
    [0, 90, 180, 270].forEach(function (r) {
      h += '<button data-r="' + r + '" class="' + (Number(value || 0) === r ? 'on' : '') + '">' + r + '°</button>';
    });
    h += '</div>';
    bind(id, 'click', function (e) {
      var r = e.target.getAttribute('data-r');
      if (r !== null) onset(Number(r));
    });
    return h;
  }

  function check(label, value, onset) {
    var id = nid();
    bind(id, 'change', function (e) { onset(e.target.checked); });
    return '<label class="chk"><input type="checkbox" id="' + id + '"' + (value ? ' checked' : '') + '><span>' + esc(label) + '</span></label>';
  }

  // ---------- SVG -----------------------------------------------------------
  function loopsPath(loops, sx, sy, k) {
    var d = '';
    loops.forEach(function (l) {
      l.forEach(function (p, i) {
        d += (i ? 'L' : 'M') + ((p[0] - sx) * k).toFixed(2) + ' ' + ((sy - p[1]) * k).toFixed(2);
      });
      d += 'Z';
    });
    return d;
  }
  function bboxOf(list, withOrigin) {
    var b = withOrigin ? [0, 0, 0, 0] : [Infinity, Infinity, -Infinity, -Infinity];
    list.forEach(function (loops) {
      loops.forEach(function (l) {
        l.forEach(function (p) {
          b[0] = Math.min(b[0], p[0]); b[1] = Math.min(b[1], p[1]);
          b[2] = Math.max(b[2], p[0]); b[3] = Math.max(b[3], p[1]);
        });
      });
    });
    return b;
  }
  function thumbSVG(loops) {
    var b = bboxOf([loops], false);
    var w = b[2] - b[0] || 1, h = b[3] - b[1] || 1, k = 40 / Math.max(w, h);
    var ox = (48 - w * k) / 2, oy = (48 - h * k) / 2;
    return '<svg viewBox="0 0 48 48"><g transform="translate(' + ox.toFixed(1) + ' ' + oy.toFixed(1) + ')"><path fill-rule="evenodd" d="' +
      loopsPath(loops, b[0], b[3], k) + '"/></g></svg>';
  }
  function previewSVG(data) {
    if (!data || !data.parts || !data.parts.length) return '<div class="pv-empty">…</div>';
    var all = data.parts.map(function (p) { return p.loops; });
    var b = bboxOf(all, true);
    var W = 320, H = 220, pad = 26;
    var w = b[2] - b[0] || 1, h = b[3] - b[1] || 1;
    var k = Math.min((W - 2 * pad) / w, (H - 2 * pad) / h);
    var ox = (W - w * k) / 2, oy = (H - h * k) / 2;
    var g = '';
    data.parts.forEach(function (p) {
      var cls = 'pv-' + p.type + (p.hidden ? ' pv-hidden' : '');
      g += '<path class="' + cls + '" fill-rule="evenodd" d="' + loopsPath(p.loops, b[0], b[3], k) + '"/>';
    });
    var px = (0 - b[0]) * k, py = (b[3] - 0) * k;
    g += '<line class="pv-axis" x1="' + (px - 12) + '" y1="' + py + '" x2="' + (px + 12) + '" y2="' + py + '"/>';
    g += '<line class="pv-axis" x1="' + px + '" y1="' + (py - 12) + '" x2="' + px + '" y2="' + (py + 12) + '"/>';
    g += '<circle class="pv-dot" cx="' + px + '" cy="' + py + '" r="4.5"/>';
    var txt = '<text class="pv-txt" x="' + (px + 8) + '" y="' + (py + 14) + '">' + esc(T('path_point')) + '</text>';
    var dim = '<text class="pv-dim" x="' + (W - 6) + '" y="' + (H - 6) + '" text-anchor="end">' +
      esc(toUnit(w) + ' × ' + toUnit(h) + ' ' + S.units) + '</text>' +
      '<text class="pv-dim" x="6" y="' + (H - 6) + '">→ ' + esc(T('outside')) + '</text>';
    return '<svg class="pv" viewBox="0 0 ' + W + ' ' + H + '"><g transform="translate(' + ox.toFixed(1) + ' ' + oy.toFixed(1) + ')">' +
      g + txt + '</g>' + dim + '</svg>';
  }

  // ---------- header / tabs / banner ---------------------------------------
  function renderChrome() {
    document.documentElement.lang = S.lang;
    document.documentElement.dir = S.lang === 'fa' ? 'rtl' : 'ltr';
    document.querySelectorAll('[data-i18n]').forEach(function (el) { el.textContent = T(el.getAttribute('data-i18n')); });
    $('lang').textContent = T('lang_btn');
    var u = '';
    Object.keys(UNITS).forEach(function (k) { u += '<option value="' + k + '"' + (k === S.units ? ' selected' : '') + '>' + k + '</option>'; });
    $('units').innerHTML = u;
    var tabs = '';
    ['member', 'assembly', 'qty', 'guide'].forEach(function (t) {
      tabs += '<button data-t="' + t + '" class="' + (S.tab === t ? 'on' : '') + '">' + esc(T('tab_' + t)) + '</button>';
    });
    $('tabs').innerHTML = tabs;
    renderBanner();
  }

  function renderBanner() {
    var el = $('banner');
    if (S.tab !== 'member' && S.tab !== 'assembly') { el.className = 'banner hide'; return; }
    if (editing()) {
      el.className = 'banner edit';
      var h = '<div>' + esc(T('editing').replace('{n}', S.lang === 'fa' ? nf(S.sel.count, 0) : S.sel.count)
        .replace('{k}', T('k_' + S.sel.kind))) + '</div><div class="row-btns">';
      if (S.sel.kind === 'member') h += '<button data-c="rotate">' + esc(T('rotate90')) + '</button>';
      h += '<button data-c="flip">' + esc(T('flip')) + '</button>';
      if (!S.sel.closed) h += '<button data-c="extend">' + esc(T('extend')) + '</button>';
      h += '</div>';
      if (S.sel.kind === 'member') {
        h += '<label class="chk"><input type="checkbox" id="similar"' + (S.similar ? ' checked' : '') + '><span>' + esc(T('similar')) + '</span></label>';
      }
      el.innerHTML = h;
      var sim = $('similar');
      if (sim) sim.addEventListener('change', function () { S.similar = sim.checked; });
    } else if (S.sel) {
      el.className = 'banner info';
      el.innerHTML = esc(T('other_kind').replace('{k}', T('k_' + S.sel.kind)));
    } else {
      el.className = 'banner';
      el.innerHTML = esc(T('new_mode'));
    }
  }

  function actions(kind) {
    var h = '<div class="actions">';
    h += '<button class="primary" data-c="draw">✏️ ' + esc(T('draw')) + '</button>';
    h += '<button class="primary alt" data-c="build_selection">⚡ ' + esc(T('build')) + '</button>';
    h += '</div>';
    return h;
  }

  // ---------- profile tab ---------------------------------------------------
  function renderMember() {
    var spec = current();
    var h = '';
    h += '<section class="card"><input class="search" id="search" placeholder="' + esc(T('search')) + '" value="' + esc(S.search) + '">';
    var cats = ['basic', 'steel', 'trim', 'custom'];
    var q = S.search.trim().toLowerCase();
    cats.forEach(function (c) {
      var items = [];
      if (c === 'custom') {
        (S.library.profiles || []).forEach(function (p) { items.push({ id: p.id, name: p.name, loops: p.loops, custom: true }); });
      } else {
        S.catalog.forEach(function (e) { if (e.category === c) items.push({ id: e.id, name: S.lang === 'fa' ? e.fa : e.en, alt: e.en + ' ' + e.fa, loops: e.thumb }); });
      }
      if (q) items = items.filter(function (it) { return (it.name + ' ' + (it.alt || '')).toLowerCase().indexOf(q) >= 0; });
      if (!items.length) return;
      h += '<div class="cat">' + esc(T('cat_' + c)) + '</div><div class="grid">';
      items.forEach(function (it) {
        h += '<button class="pcard' + (spec.profile === it.id ? ' on' : '') + '" data-p="' + esc(it.id) + '" title="' + esc(it.name) + '">' +
          thumbSVG(it.loops) + '<span>' + esc(it.name) + '</span>' +
          (it.custom ? '<i class="del" data-del="' + esc(it.id) + '">×</i>' : '') + '</button>';
      });
      h += '</div>';
    });
    h += '</section>';

    h += '<section class="card"><h4>' + esc(T('size')) + ' — ' + esc(profileName(spec.profile, spec.custom_name)) + '</h4><div class="fields">';
    paramsFor(spec).forEach(function (p) {
      var val = spec.params && spec.params[p.key] !== undefined ? spec.params[p.key] : p['default'];
      h += lenField(S.lang === 'fa' ? p.fa : p.en, val, function (v) { spec.params = spec.params || {}; spec.params[p.key] = v; changed(); });
    });
    h += '</div></section>';

    h += '<section class="card"><h4>' + esc(T('position')) + '</h4><div class="pos">';
    h += anchorGrid(spec.anchor || 'mc', function (a) { spec.anchor = a; changed({ render: true }); });
    h += '<div class="pos-r"><div class="lbl">' + esc(T('rotation')) + '</div>' +
      rotationButtons(spec.rotation, function (r) { spec.rotation = r; changed({ render: true }); }) +
      check(T('flip'), spec.flip, function (v) { spec.flip = v; changed(); }) + '</div></div>';
    h += '<div class="fields">' +
      lenField(T('offset_u'), spec.offset_u || 0, function (v) { spec.offset_u = v; changed(); }) +
      lenField(T('offset_v'), spec.offset_v || 0, function (v) { spec.offset_v = v; changed(); }) + '</div>';
    h += materialSelect(spec.material || '', function (m) { spec.material = m; changed(); });
    h += '</section>';

    h += '<section class="card"><h4>' + esc(T('preview')) + '</h4><div id="pv">' + previewSVG(S.preview.member) + '</div></section>';
    h += actions('member');
    h += '<div class="actions sub"><button data-c="save_face">' + esc(T('save_face')) + '</button></div>';
    $('main').innerHTML = h;

    bind('search', 'input', function (e) {
      S.search = e.target.value;
      var pos = e.target.selectionStart;
      renderMember();
      var s = $('search'); s.focus(); try { s.setSelectionRange(pos, pos); } catch (x) { /* ignore */ }
    });
  }

  function chooseProfile(id) {
    var spec = current();
    var e = catalogEntry(id);
    spec.profile = id;
    var params = {};
    if (e) {
      e.params.forEach(function (p) { params[p.key] = p['default']; });
      delete spec.custom_loops; delete spec.custom_name;
    } else {
      var c = customEntry(id);
      if (!c) return;
      var b = bboxOf([c.loops], false);
      params = { w: Math.round((b[2] - b[0]) * 100) / 100, h: Math.round((b[3] - b[1]) * 100) / 100 };
      spec.custom_loops = c.loops; spec.custom_name = c.name;
    }
    spec.params = params;
    changed({ render: true });
  }

  // ---------- assembly tab --------------------------------------------------
  function presetEntry(id) {
    for (var i = 0; i < S.presets.length; i++) if (S.presets[i].id === id) return S.presets[i];
    return null;
  }

  function renderAssembly() {
    var spec = current();
    var h = '<section class="card"><h4>' + esc(T('preset')) + '</h4><select id="preset">';
    S.presets.forEach(function (p) {
      h += '<option value="' + esc(p.id) + '"' + (spec.preset === p.id ? ' selected' : '') + '>' + esc(S.lang === 'fa' ? p.fa : p.en) + '</option>';
    });
    var user = S.library.assemblies || [];
    if (user.length) {
      h += '<optgroup label="' + esc(T('my_assemblies')) + '">';
      user.forEach(function (a) { h += '<option value="' + esc(a.id) + '"' + (spec.preset === a.id ? ' selected' : '') + '>' + esc(a.name) + '</option>'; });
      h += '</optgroup>';
    }
    h += '<option value="custom"' + (spec.preset === 'custom' ? ' selected' : '') + '>' + esc(T('preset_custom')) + '</option></select>';
    var pe = presetEntry(spec.preset);
    if (pe) {
      h += '<div class="fields">';
      pe.params.forEach(function (p) {
        var v = spec.preset_params && spec.preset_params[p.key] !== undefined ? spec.preset_params[p.key] : p['default'];
        h += lenField(S.lang === 'fa' ? p.fa : p.en, v, function (val) {
          spec.preset_params = spec.preset_params || {};
          spec.preset_params[p.key] = val;
          debounce('preset', 120, function () { send({ type: 'preset_rows', preset: spec.preset, params: spec.preset_params }); });
        });
      });
      h += '</div>';
    }
    h += check(T('flip_all'), spec.flip, function (v) { spec.flip = v; changed(); });
    h += '</section>';

    h += '<section class="card"><h4>' + esc(T('preview')) + '</h4><div id="pv">' + previewSVG(S.preview.assembly) + '</div></section>';

    // parts
    h += '<section class="card"><h4>' + esc(T('parts')) + '</h4><div class="rows">';
    (spec.rows || []).forEach(function (r, i) { h += rowHTML(spec, r, i); });
    h += '</div><div class="row-btns"><button data-c="add_layer">' + esc(T('add_layer')) + '</button><button data-c="add_repeat">' +
      esc(T('add_repeat')) + '</button></div></section>';

    // openings
    h += '<section class="card"><h4>' + esc(T('openings')) + '</h4>';
    (spec.openings || []).forEach(function (o, i) {
      h += '<div class="opening"><div class="fields">' +
        lenField(T('at'), o.at, function (v) { o.at = v; changed(); }) +
        lenField(T('width'), o.width, function (v) { o.width = v; changed(); }) +
        lenField(T('sill'), o.sill, function (v) { o.sill = v; changed(); }) +
        lenField(T('head'), o.head, function (v) { o.head = v; changed(); }) + '</div>' +
        check(T('jambs'), o.jambs, function (v) { o.jambs = v; changed(); }) +
        '<button class="link danger" data-c="del_opening" data-i="' + i + '">' + esc(T('remove')) + '</button></div>';
    });
    h += '<div class="row-btns"><button data-c="add_door">' + esc(T('add_door')) + '</button><button data-c="add_window">' +
      esc(T('add_window')) + '</button><button data-c="add_gate">' + esc(T('add_gate')) + '</button></div></section>';

    h += actions('assembly');
    h += '<div class="actions sub"><button data-c="save_assembly">' + esc(T('save_assembly')) + '</button></div>';
    $('main').innerHTML = h;

    bind('preset', 'change', function (e) {
      var id = e.target.value;
      var pe2 = presetEntry(id);
      spec.preset = id;
      if (pe2) {
        spec.preset_params = {};
        pe2.params.forEach(function (p) { spec.preset_params[p.key] = p['default']; });
        send({ type: 'preset_rows', preset: id, params: spec.preset_params });
      } else {
        var ua = null;
        (S.library.assemblies || []).forEach(function (a) { if (a.id === id) ua = a; });
        if (ua) { spec.rows = clone(ua.rows); spec.openings = clone(ua.openings || []); }
        changed({ render: true });
      }
      renderAssembly();
    });
  }

  function rowSummary(r) {
    var s = profileName(r.profile, r.name) + ' ';
    var e = catalogEntry(r.profile);
    if (e) s += e.params.map(function (p) { return toUnit(r.params && r.params[p.key] !== undefined ? r.params[p.key] : p['default']); }).join('×');
    if (r.type === 'repeat') s += ' @' + toUnit(r.spacing);
    return s;
  }

  function rowHTML(spec, r, i) {
    var open = S.openRow === i;
    var h = '<div class="arow' + (open ? ' open' : '') + (r.visible === false ? ' off' : '') + '">';
    h += '<div class="arow-h" data-c="toggle_row" data-i="' + i + '"><span class="eye" data-c="eye" data-i="' + i + '">' + (r.visible === false ? '◌' : '●') + '</span>' +
      '<b>' + esc(r.name || '') + '</b><span class="badge ' + r.type + '">' + esc(T('t_' + r.type)) + '</span><span class="sum">' + esc(rowSummary(r)) + '</span></div>';
    if (open) {
      var edit = function () { spec.preset = 'custom'; changed(); };
      h += '<div class="arow-b"><div class="fields">';
      var nameId = nid();
      bind(nameId, 'input', function (e) { r.name = e.target.value; edit(); });
      h += '<label class="fld"><span>' + esc(T('name')) + '</span><input id="' + nameId + '" value="' + esc(r.name) + '"></label>';
      var pid = nid();
      var opts = '';
      S.catalog.forEach(function (e) { opts += '<option value="' + e.id + '"' + (r.profile === e.id ? ' selected' : '') + '>' + esc(S.lang === 'fa' ? e.fa : e.en) + '</option>'; });
      (S.library.profiles || []).forEach(function (p) { opts += '<option value="' + esc(p.id) + '"' + (r.profile === p.id ? ' selected' : '') + '>' + esc(p.name) + '</option>'; });
      bind(pid, 'change', function (e) {
        var id = e.target.value, ce = catalogEntry(id);
        r.profile = id; r.params = {};
        if (ce) { ce.params.forEach(function (p) { r.params[p.key] = p['default']; }); delete r.custom_loops; }
        else {
          var c = customEntry(id);
          if (c) { var b = bboxOf([c.loops], false); r.params = { w: b[2] - b[0], h: b[3] - b[1] }; r.custom_loops = c.loops; }
        }
        spec.preset = 'custom'; changed({ render: true });
      });
      h += '<label class="fld"><span>' + esc(T('profile')) + '</span><select id="' + pid + '">' + opts + '</select></label>';
      paramsFor(r).forEach(function (p) {
        var v = r.params && r.params[p.key] !== undefined ? r.params[p.key] : p['default'];
        h += lenField(S.lang === 'fa' ? p.fa : p.en, v, function (val) { r.params = r.params || {}; r.params[p.key] = val; edit(); });
      });
      h += lenField(T('offset_u'), r.offset_u || 0, function (v) { r.offset_u = v; edit(); });
      if (r.type === 'repeat') {
        h += lenField(T('v0'), r.v0 || 0, function (v) { r.v0 = v; edit(); });
        h += lenField(T('length'), r.length || 0, function (v) { r.length = v; edit(); });
        h += lenField(T('spacing'), r.spacing || 400, function (v) { r.spacing = v; edit(); });
        h += lenField(T('setback_start'), r.setback_start || 0, function (v) { r.setback_start = v; edit(); });
        h += lenField(T('setback_end'), r.setback_end || 0, function (v) { r.setback_end = v; edit(); });
      } else {
        h += lenField(T('offset_v'), r.offset_v || 0, function (v) { r.offset_v = v; edit(); });
      }
      h += '</div>';
      if (r.type === 'repeat') {
        var mid = nid();
        bind(mid, 'change', function (e) { r.mode = e.target.value; edit(); });
        h += '<label class="fld"><span>' + esc(T('mode')) + '</span><select id="' + mid + '"><option value="even"' + (r.mode !== 'fixed' ? ' selected' : '') + '>' +
          esc(T('mode_even')) + '</option><option value="fixed"' + (r.mode === 'fixed' ? ' selected' : '') + '>' + esc(T('mode_fixed')) + '</option></select></label>';
        h += check(T('at_corners'), r.at_corners, function (v) { r.at_corners = v; edit(); });
        h += check(T('jambs'), r.jambs, function (v) { r.jambs = v; edit(); });
      }
      h += '<div class="pos">' + anchorGrid(r.anchor || (r.type === 'repeat' ? 'mc' : 'bc'), function (a) { r.anchor = a; spec.preset = 'custom'; changed({ render: true }); }) +
        '<div class="pos-r"><div class="lbl">' + esc(T('rotation')) + '</div>' +
        rotationButtons(r.rotation, function (v) { r.rotation = v; spec.preset = 'custom'; changed({ render: true }); }) +
        check(T('flip'), r.flip, function (v) { r.flip = v; edit(); }) + '</div></div>';
      h += materialSelect(r.material || '', function (m) { r.material = m; edit(); });
      h += '<div class="row-btns"><button data-c="row_up" data-i="' + i + '">↑ ' + esc(T('up')) + '</button><button data-c="row_down" data-i="' + i + '">↓ ' +
        esc(T('down')) + '</button><button data-c="row_dup" data-i="' + i + '">' + esc(T('duplicate')) + '</button><button class="danger" data-c="row_del" data-i="' + i + '">' +
        esc(T('remove')) + '</button></div></div>';
    }
    h += '</div>';
    return h;
  }

  // ---------- quantities ----------------------------------------------------
  function renderQty() {
    var h = '<section class="card"><div class="row-btns"><button data-c="qty_refresh">⟳ ' + esc(T('refresh')) + '</button><button data-c="qty_export">⬇ ' +
      esc(T('q_export')) + '</button></div>';
    if (!S.qty.length) {
      h += '<p class="muted">' + esc(T('q_empty')) + '</p></section>';
      $('main').innerHTML = h;
      return;
    }
    h += '<div class="tbl-wrap"><table class="qty"><thead><tr><th>' + esc(T('q_item')) + '</th><th>' + esc(T('q_size')) + '</th><th>' + esc(T('q_count')) +
      '</th><th>' + esc(T('q_length')) + '</th><th>' + esc(T('q_volume')) + '</th><th>' + esc(T('q_price')) + '</th><th>' + esc(T('q_cost')) + '</th></tr></thead><tbody>';
    var total = 0;
    S.qty.forEach(function (r, i) {
      var m = r.length_mm / 1000, cost = m * (r.price || 0);
      total += cost;
      h += '<tr><td><a data-c="qty_select" data-i="' + i + '">' + esc(r.name ? r.name + ' — ' : '') + esc(profileName(r.profile)) + '</a></td><td>' + esc(r.size) +
        '</td><td>' + nf(r.count, 0) + '</td><td>' + nf(m, 2) + '</td><td>' + nf(r.volume_mm3 / 1e9, 4) + '</td><td><input class="price" data-i="' + i +
        '" inputmode="decimal" value="' + (r.price || '') + '"></td><td class="cost" id="cost' + i + '">' + nf(cost, 0) + '</td></tr>';
    });
    h += '</tbody><tfoot><tr><td colspan="6">' + esc(T('q_total')) + '</td><td id="qtotal">' + nf(total, 0) + '</td></tr></tfoot></table></div>';
    h += '<p class="muted small">' + esc(T('q_hint')) + '</p></section>';
    $('main').innerHTML = h;
    document.querySelectorAll('input.price').forEach(function (el) {
      el.addEventListener('input', function () {
        var i = Number(el.getAttribute('data-i')), v = parseFloat(faDigits(el.value)) || 0;
        S.qty[i].price = v;
        var t = 0;
        S.qty.forEach(function (r, j) {
          var c = r.length_mm / 1000 * (r.price || 0);
          t += c;
          if (j === i) $('cost' + j).textContent = nf(c, 0);
        });
        $('qtotal').textContent = nf(t, 0);
        debounce('price' + i, 400, function () { send({ type: 'set_price', key: S.qty[i].key, price: v }); });
      });
    });
  }

  function exportQty() {
    var headers = ['Item', 'Name', 'Size (mm)', 'Pieces', 'Length (m)', 'Volume (m3)', 'Material', 'Price per m', 'Cost'];
    var rows = S.qty.map(function (r) {
      var m = r.length_mm / 1000;
      return [profileName(r.profile), r.name || '', r.size, r.count, m.toFixed(3), (r.volume_mm3 / 1e9).toFixed(5), r.material || '', r.price || 0, (m * (r.price || 0)).toFixed(2)];
    });
    send({ type: 'export_csv', headers: headers, rows: rows });
  }

  function renderGuide() {
    $('main').innerHTML = '<section class="card guide">' + T('guide_html') + '</section>';
  }

  function render() {
    renderChrome();
    if (!S.member) { $('main').innerHTML = '<div class="pv-empty">…</div>'; return; }
    if (S.tab === 'member') renderMember();
    else if (S.tab === 'assembly') renderAssembly();
    else if (S.tab === 'qty') renderQty();
    else renderGuide();
  }

  // ---------- click delegation ---------------------------------------------
  document.addEventListener('click', function (e) {
    var t = e.target.closest ? e.target : null;
    if (!t) return;
    var tab = t.closest('#tabs button');
    if (tab) {
      S.tab = tab.getAttribute('data-t');
      if (S.tab === 'qty') send({ type: 'quantities' });
      if (S.tab === 'member' || S.tab === 'assembly') send({ type: 'set_spec', kind: S.tab, spec: S[S.tab] });
      render();
      requestPreview();
      return;
    }
    var del = t.closest('[data-del]');
    if (del) {
      e.stopPropagation();
      if (window.confirm(T('del_confirm'))) send({ type: 'remove_library', id: del.getAttribute('data-del') });
      return;
    }
    var pc = t.closest('[data-p]');
    if (pc) { chooseProfile(pc.getAttribute('data-p')); return; }
    var b = t.closest('[data-c]');
    if (!b) return;
    var c = b.getAttribute('data-c'), i = Number(b.getAttribute('data-i'));
    var spec = current();
    switch (c) {
      case 'draw': case 'build_selection':
        send({ type: c, kind: S.tab, spec: S[S.tab] });
        break;
      case 'rotate': case 'flip': case 'extend': case 'save_face':
        send({ type: c });
        break;
      case 'save_assembly': send({ type: 'save_assembly', spec: spec }); break;
      case 'eye':
        e.stopPropagation();
        spec.rows[i].visible = spec.rows[i].visible === false;
        changed({ render: true });
        break;
      case 'toggle_row': S.openRow = S.openRow === i ? -1 : i; renderAssembly(); break;
      case 'row_up': case 'row_down': {
        var j = c === 'row_up' ? i - 1 : i + 1;
        if (j < 0 || j >= spec.rows.length) break;
        var tmp = spec.rows[i]; spec.rows[i] = spec.rows[j]; spec.rows[j] = tmp;
        S.openRow = j; spec.preset = 'custom'; changed({ render: true });
        break;
      }
      case 'row_dup': spec.rows.splice(i + 1, 0, clone(spec.rows[i])); S.openRow = i + 1; spec.preset = 'custom'; changed({ render: true }); break;
      case 'row_del': spec.rows.splice(i, 1); S.openRow = -1; spec.preset = 'custom'; changed({ render: true }); break;
      case 'add_layer':
        spec.rows = spec.rows || [];
        spec.rows.push({ type: 'layer', name: 'Part ' + (spec.rows.length + 1), profile: 'rect', params: { w: 89, h: 38 }, anchor: 'bc', offset_u: 0, offset_v: 0, rotation: 0, flip: false, material: '', visible: true });
        S.openRow = spec.rows.length - 1; spec.preset = 'custom'; changed({ render: true });
        break;
      case 'add_repeat':
        spec.rows = spec.rows || [];
        spec.rows.push({ type: 'repeat', name: 'Piece ' + (spec.rows.length + 1), profile: 'rect', params: { w: 89, h: 38 }, anchor: 'mc', offset_u: 0, rotation: 0, flip: false, v0: 0, length: 1000, spacing: 600, setback_start: 0, setback_end: 0, mode: 'even', at_corners: true, jambs: false, material: '', visible: true });
        S.openRow = spec.rows.length - 1; spec.preset = 'custom'; changed({ render: true });
        break;
      case 'add_door': case 'add_window': case 'add_gate': {
        spec.openings = spec.openings || [];
        var o = { at: 500, width: 900, sill: 0, head: 2100, jambs: true };
        if (c === 'add_window') o = { at: 500, width: 1200, sill: 900, head: 2100, jambs: true };
        if (c === 'add_gate') o = { at: 500, width: 1000, sill: 0, head: 0, jambs: true };
        spec.openings.push(o);
        changed({ render: true });
        break;
      }
      case 'del_opening': spec.openings.splice(i, 1); changed({ render: true }); break;
      case 'qty_refresh': send({ type: 'quantities' }); break;
      case 'qty_export': exportQty(); break;
      case 'qty_select': send({ type: 'select_key', key: S.qty[i].key }); break;
    }
  });

  $('lang').addEventListener('click', function () {
    S.lang = S.lang === 'fa' ? 'en' : 'fa';
    send({ type: 'settings', lang: S.lang });
    render();
  });
  $('units').addEventListener('change', function (e) {
    S.units = e.target.value;
    send({ type: 'settings', units: S.units });
    render();
  });
  document.addEventListener('focusin', function (e) {
    if (e.target && e.target.tagName === 'SELECT' && e.target.closest('.fld') && e.target.innerHTML.indexOf('BPB Wood') >= 0) send({ type: 'materials' });
  });

  // ---------- messages from Ruby -------------------------------------------
  window.BPB = {
    receive: function (m) {
      switch (m.type) {
        case 'init':
          S.lang = m.lang || 'fa'; S.units = UNITS[m.units] ? m.units : 'mm';
          S.catalog = m.catalog; S.presets = m.presets; S.library = m.library || S.library;
          S.materials = m.materials || []; S.member = m.member; S.assembly = m.assembly;
          if (m.mode === 'assembly') S.tab = 'assembly';
          render();
          requestPreview();
          break;
        case 'selection': {
          var before = S.sel ? S.sel.kind : null;
          S.sel = m.item ? { kind: m.item.kind, spec: m.item.spec, count: m.item.count, closed: m.item.closed } : null;
          if (S.sel && (S.tab === 'member' || S.tab === 'assembly' || S.tab === 'guide') && S.tab !== S.sel.kind) S.tab = S.sel.kind;
          S.openRow = -1;
          if (S.tab === 'member' || S.tab === 'assembly' || before) render();
          requestPreview();
          break;
        }
        case 'preview':
          S.preview[m.kind] = m.data;
          if (m.kind === S.tab && $('pv')) $('pv').innerHTML = previewSVG(m.data);
          break;
        case 'preset_rows': {
          var spec = current();
          spec.rows = m.rows;
          changed();
          if (S.tab === 'assembly') {
            var rows = document.querySelector('.rows');
            if (rows) {
              var h = '';
              spec.rows.forEach(function (r, i) { h += rowHTML(spec, r, i); });
              rows.innerHTML = h;
            }
          }
          break;
        }
        case 'library': S.library = m.library; if (S.tab === 'member' || S.tab === 'assembly') render(); break;
        case 'use_spec': S[m.kind] = m.spec; S.tab = m.kind; render(); requestPreview(); break;
        case 'materials': S.materials = m.materials || []; break;
        case 'quantities': S.qty = m.rows || []; if (S.tab === 'qty') renderQty(); break;
        case 'tab': S.tab = m.tab; if (m.tab === 'qty') send({ type: 'quantities' }); render(); break;
        case 'toast': toast(m.text, m.level); break;
      }
    }
  };

  render();
  send({ type: 'ready' });
})();
