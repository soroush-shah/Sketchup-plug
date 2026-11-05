/* Persian Text dialog logic (ES5, runs in SketchUp's HtmlDialog). */
(function () {
  'use strict';

  var $ = function (id) { return document.getElementById(id); };
  var PT = window.PT = {};

  // ---------------------------------------------------------------------------
  // Ruby bridge (messages are chunked; replies come back via PT.onReply)
  // ---------------------------------------------------------------------------
  var CHUNK = 200000;
  var msgSeq = 1, reqSeq = 1, pending = {}, fontBufs = {};

  function send(action, data, req) {
    var s = JSON.stringify({ action: action, data: data || {}, req: req || 0 });
    if (!window.sketchup || !window.sketchup.msg) { if (window.PT_MOCK) window.PT_MOCK(action, data, req); return; }
    var id = 'm' + (msgSeq++);
    var n = Math.max(1, Math.ceil(s.length / CHUNK));
    for (var i = 0; i < n; i++) window.sketchup.msg(id, i, n, s.substr(i * CHUNK, CHUNK));
  }
  function call(action, data) {
    return new Promise(function (resolve) {
      var req = reqSeq++;
      pending[req] = resolve;
      send(action, data, req);
    });
  }
  PT.onReply = function (o) { var r = pending[o.req]; if (r) { delete pending[o.req]; r(o.data); } };
  PT.fontBegin = function (req, n) { fontBufs[req] = new Array(n); };
  PT.fontChunk = function (req, i, data) { if (fontBufs[req]) fontBufs[req][i] = data; };
  PT.fontEnd = function (req) { var b = fontBufs[req]; delete fontBufs[req]; PT.onReply({ req: req, data: { b64: b ? b.join('') : '' } }); };
  PT.onError = function (o) { setStatus(o.message, 'error'); };

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------
  var S = {
    ready: false,
    mode: 'create',
    units: 3,
    fonts: [],          // flat list of faces
    families: [],       // [{name, faces:[...], fa}]
    familyName: null,
    face: null,         // selected face entry
    font: null,         // loaded engine font
    fontKey: '',
    fontCache: {},      // key -> engine font
    fontOrder: [],
    lengths: {},        // string -> inches | 'error'
    variations: {},
    result: null,
    align: 'right',
    filled: true,
    materials: [],
    pendingParams: null
  };

  var UNIT = { 0: [1, '"'], 1: [12, "'"], 2: [1 / 25.4, 'mm'], 3: [1 / 2.54, 'cm'], 4: [1 / 0.0254, 'm'], 5: [36, 'yd'] };

  function setStatus(msg, cls) {
    var el = $('status');
    el.textContent = msg || '';
    el.className = 'status' + (cls ? ' ' + cls : '');
  }

  function fmtLen(inches) {
    var u = UNIT[S.units] || UNIT[3];
    var v = inches / u[0];
    var d = Math.abs(v) >= 100 ? 0 : (Math.abs(v) >= 10 ? 1 : 2);
    return v.toFixed(d) + ' ' + u[1];
  }

  // ---------------------------------------------------------------------------
  // Fonts
  // ---------------------------------------------------------------------------
  function faceKey(f) { return f.path + '|' + (f.index || 0); }

  function groupFamilies(list) {
    var map = {}, fams = [];
    list.forEach(function (f) {
      var k = f.family;
      if (!map[k]) { map[k] = { name: k, faces: [], fa: false }; fams.push(map[k]); }
      map[k].faces.push(f);
      if (f.fa) map[k].fa = true;
    });
    fams.sort(function (a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1; });
    fams.forEach(function (fam) {
      fam.faces.sort(function (a, b) { return (a.weight - b.weight) || ((a.italic ? 1 : 0) - (b.italic ? 1 : 0)); });
    });
    return fams;
  }

  function sampleText() {
    var t = ($('text').value || '').split('\n')[0].trim();
    return t ? t.substr(0, 30) : 'متن نمونه فارسی';
  }

  // Virtualised font list: only the rows in view are in the DOM, so the
  // browser only has to load the handful of fonts used by visible samples.
  var ROW = 32;
  var view = { list: [], a: -1, b: -1, sample: null };

  function renderFontList() {
    var q = $('fontSearch').value.trim().toLowerCase();
    var only = $('onlyPersian').checked;
    var list = [];
    for (var i = 0; i < S.families.length; i++) {
      var fam = S.families[i];
      if (only && !fam.fa) continue;
      if (q && fam.name.toLowerCase().indexOf(q) < 0) continue;
      list.push(i);
    }
    view.list = list;
    $('fontInner').style.height = (list.length * ROW) + 'px';
    $('fontCount').textContent = S.fonts.length ? list.length + ' / ' + S.families.length : '';
    drawRows(true);
  }

  function scrollToSelected() {
    var box = $('fontList');
    for (var k = 0; k < view.list.length; k++) {
      if (S.families[view.list[k]].name === S.familyName) {
        var top = k * ROW;
        if (top < box.scrollTop || top + ROW > box.scrollTop + box.clientHeight) box.scrollTop = Math.max(0, top - box.clientHeight / 2);
        break;
      }
    }
    drawRows(true);
  }

  function drawRows(force) {
    var box = $('fontList'), inner = $('fontInner');
    var n = view.list.length;
    if (!n) {
      inner.innerHTML = '<div class="empty">' + (S.fonts.length ? 'فونتی پیدا نشد / No fonts found' : 'در حال خواندن فونت‌ها… / Loading fonts…') + '</div>';
      view.a = view.b = -1;
      return;
    }
    var h = box.clientHeight || 190;
    var a = Math.max(0, Math.floor(box.scrollTop / ROW) - 2);
    var b = Math.min(n, Math.ceil((box.scrollTop + h) / ROW) + 2);
    var showS = $('showSamples').checked;
    var sample = showS ? escapeHtml(sampleText()) : '';
    if (!force && a === view.a && b === view.b && sample === view.sample) return;
    view.a = a; view.b = b; view.sample = sample;
    var html = [];
    for (var k = a; k < b; k++) {
      var i = view.list[k], fam = S.families[i];
      var sel = fam.name === S.familyName ? ' sel' : '';
      html.push('<div class="font-item' + sel + '" data-i="' + i + '" style="top:' + (k * ROW) + 'px">' +
        '<span class="fname">' + escapeHtml(fam.name) + (fam.faces.length > 1 ? ' <span class="tag">(' + fam.faces.length + ')</span>' : '') + '</span>' +
        (showS ? '<span class="fsample" style="font-family:\'' + escapeAttr(fam.name) + '\', serif">' + sample + '</span>' : '') + '</div>');
    }
    inner.innerHTML = html.join('');
  }

  function escapeHtml(s) { return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
  function escapeAttr(s) { return String(s).replace(/['"\\<>]/g, ''); }

  function findFamily(name) {
    for (var i = 0; i < S.families.length; i++) if (S.families[i].name === name) return S.families[i];
    return null;
  }

  function selectFamily(name, styleHint) {
    var fam = findFamily(name);
    if (!fam) return;
    S.familyName = name;
    var sel = $('fontStyle');
    sel.innerHTML = '';
    var pick = 0;
    fam.faces.forEach(function (f, i) {
      var o = document.createElement('option');
      o.value = i;
      o.textContent = f.style + (f.variable ? ' (متغیر)' : '') + (f.custom ? ' *' : '');
      sel.appendChild(o);
      if (styleHint ? (f.style === styleHint || faceKey(f) === styleHint) : /^(regular|normal|book|roman)$/i.test(f.style)) pick = i;
    });
    sel.value = pick;
    $('text').style.fontFamily = "'" + escapeAttr(name) + "', Tahoma";
    drawRows(true);
    selectFace(fam.faces[pick]);
  }

  function selectFace(face) {
    S.face = face;
    S.variations = {};
    schedule();
  }

  function loadFace(face) {
    var key = faceKey(face);
    if (S.fontCache[key]) return Promise.resolve(S.fontCache[key]);
    setStatus('در حال بارگذاری فونت / Loading font: ' + face.family + '…');
    return call('getFont', { path: face.path }).then(function (res) {
      if (!res || res.error || !res.b64) throw new Error((res && res.error) || 'خواندن فونت ممکن نشد / Could not read font');
      var bin = atob(res.b64), bytes = new Uint8Array(bin.length);
      for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      var f = PTEngine.loadFont(bytes, face.index || 0);
      S.fontCache[key] = f;
      S.fontOrder.push(key);
      while (S.fontOrder.length > 4) {
        var old = S.fontOrder.shift();
        if (old !== key && S.fontCache[old]) { try { S.fontCache[old].destroy(); } catch (e) { /* ignore */ } delete S.fontCache[old]; }
      }
      setStatus('');
      return f;
    });
  }

  function renderAxes(font) {
    var box = $('axes');
    var axes = font.axes || {};
    var names = { wght: 'وزن / Weight', wdth: 'عرض / Width', slnt: 'شیب / Slant', ital: 'ایتالیک / Italic', opsz: 'اندازه‌ی اپتیکال / Optical size' };
    var keys = Object.keys(axes);
    var sig = keys.join(',') + '|' + S.fontKey;
    if (box._sig === sig) return;
    box._sig = sig;
    box.innerHTML = '';
    keys.forEach(function (k) {
      var a = axes[k];
      var v = S.variations[k] != null ? S.variations[k] : a.def;
      var lab = document.createElement('label');
      lab.innerHTML = (names[k] || k) + ' <output>' + Math.round(v) + '</output>';
      var inp = document.createElement('input');
      inp.type = 'range'; inp.min = a.min; inp.max = a.max; inp.step = (a.max - a.min) > 20 ? 1 : 0.1; inp.value = v;
      inp.addEventListener('input', function () {
        S.variations[k] = +inp.value;
        lab.querySelector('output').textContent = Math.round(+inp.value);
        schedule();
      });
      lab.appendChild(inp);
      box.appendChild(lab);
    });
  }

  // ---------------------------------------------------------------------------
  // Lengths (parsed by SketchUp so any unit format works: 30cm, 1m, 12", 2')
  // ---------------------------------------------------------------------------
  function localLength(s) {
    var m = String(s).trim().replace(/[۰-۹]/g, function (d) { return d.charCodeAt(0) - 0x6F0; }).match(/^(-?[\d.]+)\s*(mm|cm|m|"|in|'|ft)?$/);
    if (!m) return 'error';
    var v = parseFloat(m[1]), u = m[2];
    var f = { mm: 1 / 25.4, cm: 1 / 2.54, m: 1 / 0.0254, '"': 1, 'in': 1, "'": 12, ft: 12 }[u] || (UNIT[S.units] || UNIT[3])[0];
    return v * f;
  }

  function ensureLengths(strs) {
    var need = {}, any = false;
    strs.forEach(function (s) { if (!(s in S.lengths)) { need[s] = s; any = true; } });
    if (!any) return Promise.resolve();
    if (!window.sketchup) { Object.keys(need).forEach(function (s) { S.lengths[s] = localLength(s); }); return Promise.resolve(); }
    return call('lengths', need).then(function (res) {
      Object.keys(need).forEach(function (s) { S.lengths[s] = res[s] == null ? 0 : res[s]; });
    });
  }

  function lengthOf(id) {
    var s = $(id).value.trim() || '0';
    var v = S.lengths[s];
    $(id).classList.toggle('invalid', v === 'error');
    return (typeof v === 'number') ? v : null;
  }

  // ---------------------------------------------------------------------------
  // Params
  // ---------------------------------------------------------------------------
  function collectParams() {
    var f = S.face || {};
    return {
      text: $('text').value,
      fontPath: f.path || '',
      fontIndex: f.index || 0,
      family: f.family || '',
      style: f.style || '',
      variations: S.variations,
      height: $('height').value.trim(),
      heightMode: $('heightMode').value,
      align: S.align,
      baseDir: $('baseDir').value,
      lineSpacing: +$('lineSpacing').value,
      wordSpacing: +$('wordSpacing').value,
      letterSpacing: +$('letterSpacing').value,
      persianDigits: $('persianDigits').checked,
      bold: +$('bold').value,
      slant: +$('slant').value,
      arc: $('arc').value.trim() || '0',
      quality: $('quality').value,
      filled: S.filled,
      extrude: $('extrude').value.trim() || '0',
      zOffset: $('zOffset').value.trim() || '0',
      smooth: $('smooth').checked,
      material: $('material').value === '__color' ? $('color').value : $('material').value,
      keepOpen: $('keepOpen').checked
    };
  }

  function applyParams(p) {
    if (!p) return;
    if (p.text != null) $('text').value = p.text;
    var setv = function (id, v) { if (v != null && $(id)) $(id).value = v; };
    setv('height', p.height); setv('heightMode', p.heightMode); setv('baseDir', p.baseDir);
    setv('lineSpacing', p.lineSpacing); setv('wordSpacing', p.wordSpacing); setv('letterSpacing', p.letterSpacing);
    setv('bold', p.bold); setv('slant', p.slant); setv('arc', p.arc); setv('quality', p.quality);
    setv('extrude', p.extrude); setv('zOffset', p.zOffset);
    if (p.persianDigits != null) $('persianDigits').checked = !!p.persianDigits;
    if (p.smooth != null) $('smooth').checked = !!p.smooth;
    if (p.keepOpen != null) $('keepOpen').checked = !!p.keepOpen;
    if (p.align) setSeg('alignSeg', p.align);
    if (p.filled != null) setSeg('filledSeg', p.filled ? '1' : '0');
    setMaterial(p.material);
    updateOutputs();
    if (p.family || p.fontPath) {
      if (S.families.length) selectFontFromParams(p);
      else S.pendingParams = p;
    }
    if (p.variations) S.variations = JSON.parse(JSON.stringify(p.variations));
  }

  function selectFontFromParams(p) {
    var byPath = null, fam = null;
    S.fonts.forEach(function (f) {
      if (f.path && p.fontPath && f.path.toLowerCase() === p.fontPath.toLowerCase() && (f.index || 0) === (p.fontIndex || 0)) byPath = f;
    });
    if (byPath) { selectFamily(byPath.family, faceKey(byPath)); }
    else if ((fam = findFamily(p.family))) { selectFamily(fam.name, p.style); setStatus('فایل فونت قبلی پیدا نشد؛ از فونت هم‌نام استفاده شد. / Original font file not found; using the same family.', 'warn'); }
    else { setStatus('فونت «' + p.family + '» نصب نیست. یک فونت دیگر انتخاب کنید. / Font "' + p.family + '" is not installed; pick another font.', 'warn'); }
    var vars = p.variations ? JSON.parse(JSON.stringify(p.variations)) : {};
    S.variations = vars;
    $('axes')._sig = null;
  }

  function setMaterial(spec) {
    var sel = $('material');
    if (spec && /^#[0-9a-f]{6}$/i.test(spec)) { sel.value = '__color'; $('color').value = spec; }
    else if (spec) {
      var found = false;
      for (var i = 0; i < sel.options.length; i++) if (sel.options[i].value === spec) found = true;
      sel.value = found ? spec : '';
    } else sel.value = '';
  }

  function renderMaterials(list) {
    S.materials = list || [];
    var sel = $('material'), cur = sel.value;
    var html = '<option value="">بدون متریال / Default</option><option value="__color">رنگ دلخواه / Custom color ←</option>';
    S.materials.forEach(function (m) {
      html += '<option value="' + escapeHtml(m.name) + '">' + escapeHtml(m.display || m.name) + '</option>';
    });
    sel.innerHTML = html;
    sel.value = cur || '';
  }

  // ---------------------------------------------------------------------------
  // Update pipeline
  // ---------------------------------------------------------------------------
  var timer = null, running = false, again = false, lastSig = '';
  function schedule(delay) {
    if (timer) clearTimeout(timer);
    timer = setTimeout(update, delay == null ? 200 : delay);
  }

  // Loads the font and parses lengths; resolves with the inputs for layout.
  function prepare() {
    var p = collectParams();
    var face = S.face;
    var lens = [p.height || '0', p.arc, p.extrude, p.zOffset];
    return loadFace(face).then(function (font) {
      S.font = font; S.fontKey = faceKey(face);
      renderAxes(font);
      return ensureLengths(lens);
    }).then(function () {
      var h = lengthOf('height'); var arc = lengthOf('arc'); lengthOf('extrude'); lengthOf('zOffset');
      if (!h || h <= 0) { $('height').classList.add('invalid'); throw new Error('ارتفاع معتبر نیست / Invalid height'); }
      return { p: p, h: h, arc: arc || 0 };
    });
  }

  function runLayout(x, quality) {
    var p = x.p;
    return PTEngine.layout(S.font, {
      text: p.text, baseDir: p.baseDir, align: p.align,
      lineSpacing: p.lineSpacing, wordSpacing: p.wordSpacing / 100, letterSpacing: p.letterSpacing / 100,
      variations: S.variations, persianDigits: p.persianDigits,
      slant: p.slant, bold: p.bold / 100, quality: quality,
      heightIn: x.h, heightMode: p.heightMode, arcIn: x.arc, minSegIn: 0.0015
    });
  }

  function update() {
    timer = null;
    if (!S.ready || !S.face) return;
    if (running) { again = true; return; }
    running = true;
    prepare().then(function (x) {
      $('btnBuild').disabled = !x.p.text.trim();
      if (!$('livePreview').checked) {
        $('preview').innerHTML = '<div class="empty">پیش‌نمایش خاموش است / Preview is off</div>';
        $('dims').textContent = '';
        lastSig = '';
        return;
      }
      // skip work when nothing that affects the shape has changed
      var sig = JSON.stringify([x.p, x.h, x.arc, S.fontKey, S.variations]);
      if (sig === lastSig) return;
      lastSig = sig;
      // preview never needs more than medium quality; "Create" redoes it at full quality
      var res = runLayout(x, x.p.quality === 'high' ? 'medium' : x.p.quality);
      renderPreview(res);
      if (res.missing && res.missing.length) {
        var uniq = res.missing.filter(function (c, i, a) { return a.indexOf(c) === i; }).join(' ');
        setStatus('این فونت برخی از حروف را ندارد / This font is missing: ' + uniq, 'warn');
      } else if ($('status').className.indexOf('error') >= 0 || /Loading|Invalid/.test($('status').textContent)) setStatus('');
    }).catch(function (e) {
      setStatus(e && e.message ? e.message : String(e), 'error');
      $('btnBuild').disabled = true;
    }).then(function () {
      running = false;
      if (again) { again = false; schedule(0); }
    });
  }

  function renderPreview(res) {
    var box = $('preview');
    if (!res || !res.polys.length) { box.innerHTML = '<div class="empty">متنی برای نمایش نیست / Nothing to preview</div>'; $('dims').textContent = ''; return; }
    var b = res.bbox, w = b[2] - b[0], h = b[3] - b[1];
    var pad = Math.max(w, h) * 0.06;
    var d = [];
    function ring(r) {
      var s = 'M';
      for (var i = 0; i < r.length; i++) s += (i ? 'L' : '') + r[i][0].toFixed(4) + ' ' + (-r[i][1]).toFixed(4);
      return s + 'Z';
    }
    res.polys.forEach(function (p) { d.push(ring(p.o)); p.h.forEach(function (hh) { d.push(ring(hh)); }); });
    var fill = S.filled ? (materialColor() || '#1d232b') : 'none';
    var stroke = S.filled ? 'none' : '#1d232b';
    var mk = Math.max(w, h) * 0.02;
    box.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="' + (b[0] - pad) + ' ' + (-b[3] - pad) + ' ' + (w + 2 * pad) + ' ' + (h + 2 * pad) + '" preserveAspectRatio="xMidYMid meet">' +
      '<path d="' + d.join('') + '" fill="' + fill + '" fill-rule="evenodd" stroke="' + stroke + '" stroke-width="' + (Math.max(w, h) / 700) + '" vector-effect="non-scaling-stroke"/>' +
      '<g stroke="#e53935" stroke-width="' + (mk / 5) + '"><line x1="' + (-mk) + '" y1="0" x2="' + mk + '" y2="0"/><line x1="0" y1="' + (-mk) + '" x2="0" y2="' + mk + '"/></g>' +
      '</svg>';
    $('dims').textContent = 'W ' + fmtLen(w) + '  ×  H ' + fmtLen(h);
  }

  function materialColor() {
    var v = $('material').value;
    if (v === '__color') return $('color').value;
    for (var i = 0; i < S.materials.length; i++) if (S.materials[i].name === v) return S.materials[i].color;
    return null;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  function build() {
    if (!S.ready || !S.face || $('btnBuild').disabled) return;
    $('btnBuild').disabled = true;
    prepare().then(function (x) {
      var res = runLayout(x, x.p.quality);
      if (!res.polys.length) throw new Error('متنی برای ساخت نیست / Nothing to create');
      x.p.heightIn = x.h;
      send('build', { params: x.p, polys: res.polys, editAll: $('editAll').checked });
    }).catch(function (e) {
      setStatus(e && e.message ? e.message : String(e), 'error');
    }).then(function () { $('btnBuild').disabled = false; });
  }

  // ---------------------------------------------------------------------------
  // Messages from Ruby
  // ---------------------------------------------------------------------------
  function showUnits() {
    var u = (UNIT[S.units] || UNIT[3])[1];
    var els = document.querySelectorAll('.unit');
    for (var i = 0; i < els.length; i++) els[i].textContent = u;
    $('unitHint').innerHTML = 'اعداد بدون واحد = واحد مدل (' + u + ')؛ می‌توانید 5mm ،2m یا "3 هم بنویسید.' +
      '<br><span class="en">Plain numbers use the model unit (' + u + '). You can also type 5mm, 2m or 3".</span>';
  }

  PT.onInit = function (o) {
    S.units = o.units;
    showUnits();
    renderMaterials(o.materials);
    if (o.settings && Object.keys(o.settings).length) {
      var st = JSON.parse(JSON.stringify(o.settings));
      delete st.text;
      applyParams(st);
    } else {
      $('height').value = { 0: '12', 1: '1', 2: '300', 3: '30', 4: '0.3', 5: '0.33' }[o.units] || '30';
    }
  };

  PT.onFonts = function (o) {
    S.fonts = o.fonts || [];
    S.families = groupFamilies(S.fonts);
    if (S.pendingParams) { var p = S.pendingParams; S.pendingParams = null; selectFontFromParams(p); }
    else if (o.select) selectFamily(o.select.family, faceKey(o.select));
    else if (!S.familyName || !findFamily(S.familyName)) {
      var pref = ['Vazirmatn', 'B Nazanin', 'Tahoma', 'Arial', 'Segoe UI'];
      var fam = null;
      for (var i = 0; i < pref.length && !fam; i++) fam = findFamily(pref[i]);
      if (!fam) for (i = 0; i < S.families.length && !fam; i++) if (S.families[i].fa) fam = S.families[i];
      if (fam) selectFamily(fam.name);
    }
    renderFontList();
    scrollToSelected();
    if (/Rescan|بازخوانی/.test($('status').textContent)) setStatus('');
  };

  PT.onMode = function (o) {
    S.mode = o.mode;
    if (o.materials) renderMaterials(o.materials);
    var edit = o.mode === 'edit';
    $('modeTitle').innerHTML = edit ? 'ویرایش متن فارسی <span class="en">Edit Persian Text</span>' : 'متن فارسی جدید <span class="en">New Persian Text</span>';
    $('btnBuild').innerHTML = edit ? 'اعمال تغییرات <span class="en">Apply</span>' : 'ساخت و قرار دادن <span class="en">Create &amp; place</span>';
    $('editAllWrap').hidden = !(edit && o.shared);
    if (edit && o.params) applyParams(o.params);
    schedule();
  };

  // ---------------------------------------------------------------------------
  // UI wiring
  // ---------------------------------------------------------------------------
  function setSeg(id, v) {
    var btns = $(id).querySelectorAll('button');
    for (var i = 0; i < btns.length; i++) btns[i].classList.toggle('on', btns[i].getAttribute('data-v') === String(v));
    if (id === 'alignSeg') S.align = v;
    if (id === 'filledSeg') S.filled = String(v) === '1';
  }

  function updateOutputs() {
    $('lineSpacingOut').textContent = (+$('lineSpacing').value).toFixed(2) + '×';
    $('wordSpacingOut').textContent = $('wordSpacing').value + '%';
    $('letterSpacingOut').textContent = $('letterSpacing').value + '%';
    $('boldOut').textContent = $('bold').value + '%';
    $('slantOut').textContent = $('slant').value + '°';
  }

  function wire() {
    ['text', 'height', 'arc', 'extrude', 'zOffset'].forEach(function (id) {
      $(id).addEventListener('input', schedule);
    });
    $('text').addEventListener('input', function () { clearTimeout(wire._t); wire._t = setTimeout(function () { drawRows(false); }, 400); });
    var rafPending = false;
    $('fontList').addEventListener('scroll', function () {
      if (rafPending) return;
      rafPending = true;
      (window.requestAnimationFrame || setTimeout)(function () { rafPending = false; drawRows(false); });
    });
    $('showSamples').addEventListener('change', function () { drawRows(true); });
    $('livePreview').addEventListener('change', function () { schedule(0); });
    ['heightMode', 'baseDir', 'quality', 'persianDigits', 'smooth', 'material', 'color'].forEach(function (id) {
      $(id).addEventListener('change', schedule);
    });
    $('color').addEventListener('input', function () { $('material').value = '__color'; schedule(); });
    ['lineSpacing', 'wordSpacing', 'letterSpacing', 'bold', 'slant'].forEach(function (id) {
      $(id).addEventListener('input', function () { updateOutputs(); schedule(); });
    });
    ['alignSeg', 'filledSeg'].forEach(function (id) {
      $(id).addEventListener('click', function (e) {
        var v = e.target.getAttribute && e.target.getAttribute('data-v');
        if (v != null) { e.preventDefault(); setSeg(id, v); schedule(); }
      });
    });
    $('fontSearch').addEventListener('input', renderFontList);
    $('onlyPersian').addEventListener('change', renderFontList);
    $('fontList').addEventListener('click', function (e) {
      var el = e.target;
      while (el && el !== this && !el.getAttribute('data-i')) el = el.parentNode;
      if (!el || el === this) return;
      this._userScrolled = true;
      selectFamily(S.families[+el.getAttribute('data-i')].name);
    });
    $('fontStyle').addEventListener('change', function () {
      var fam = findFamily(S.familyName);
      if (fam) selectFace(fam.faces[+this.value]);
    });
    $('btnRescan').addEventListener('click', function () { setStatus('در حال بازخوانی فونت‌ها… / Rescanning fonts…'); send('rescanFonts'); });
    $('btnBrowse').addEventListener('click', function () { send('browseFont'); });
    $('btnPick').addEventListener('click', function () { send('pickSelection'); });
    $('btnCancel').addEventListener('click', function () { send('close'); });
    $('btnBuild').addEventListener('click', build);
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); build(); }
      if (e.key === 'Escape') send('close');
    });
    setSeg('alignSeg', 'right');
    setSeg('filledSeg', '1');
    updateOutputs();
  }

  // opentype.js is only needed when WebAssembly is missing (SketchUp 2017/2018)
  function loadFallback() {
    if (typeof window.WebAssembly === 'object' || window.opentype) return Promise.resolve();
    return new Promise(function (resolve) {
      var s = document.createElement('script');
      s.src = 'lib/opentype.min.js';
      s.onload = s.onerror = function () { resolve(); };
      document.body.appendChild(s);
    });
  }

  function start() {
    wire();
    showUnits();
    loadFallback().then(function () {
      return PTEngine.init(window.PT_HB_WASM_B64);
    }).then(function (backend) {
      var b = $('backend');
      if (backend === 'harfbuzz') { b.textContent = 'HarfBuzz'; b.className = 'badge ok'; }
      else { b.textContent = 'Compatibility engine (old SketchUp)'; b.className = 'badge warn'; }
      S.ready = true;
      send('ready');
    }).catch(function (e) {
      setStatus('موتور متن بارگذاری نشد / Text engine failed to load: ' + (e && e.message), 'error');
    });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
