/* Banian Browser UI.
 * Plain ES5 + arrow-free style so it runs in every SketchUp HtmlDialog (2017+).
 */
(function () {
  'use strict';

  var BB = window.BB = {};
  var S = BB.state = {
    view: 'models',
    settings: {},
    info: {},
    roots: [],
    indexes: {},
    trees: {},
    items: [],
    byPath: {},
    folder: { models: null, materials: null },
    search: '',
    matFilter: 'all',
    thumbs: {},
    requested: {},
    picked: null,
    scanning: {},
    list: [],
    rendered: 0,
    cardEls: {},
    mosEls: {},
    replaceArmed: false,
    modelMats: [],
    expanded: {},
    sideOpen: true
  };
  var PAGE = 180;

  // ---------------------------------------------------------------- bridge
  var seq = 0;
  var pending = {};
  BB.call = function (cmd, args) {
    return new Promise(function (resolve, reject) {
      var id = ++seq;
      pending[id] = { resolve: resolve, reject: reject };
      var msg = JSON.stringify({ id: id, cmd: cmd, args: args || {} });
      if (window.sketchup && window.sketchup.bb_call) {
        window.sketchup.bb_call(msg);
      } else {
        delete pending[id];
        reject(new Error('SketchUp bridge not available'));
      }
    });
  };
  BB.reply = function (id, res) {
    var p = pending[id];
    if (!p) return;
    delete pending[id];
    if (res && res.ok) {
      p.resolve(res.data);
    } else {
      var msg = (res && res.error) || 'error';
      toast(msg, true);
      p.reject(new Error(msg));
    }
  };
  var handlers = {};
  BB.on = function (ev, fn) { (handlers[ev] = handlers[ev] || []).push(fn); };
  BB.emit = function (ev, data) {
    (handlers[ev] || []).forEach(function (fn) {
      try { fn(data); } catch (e) { if (window.console) console.error(e); }
    });
  };
  function call(cmd, args) {
    return BB.call(cmd, args).catch(function () { return null; });
  }

  // ---------------------------------------------------------------- helpers
  function $(id) { return document.getElementById(id); }
  function t(key) { return window.BBI18n.t(S.settings.language || 'fa', key); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function icon(name, cls) { return '<svg class="i ' + (cls || '') + '"><use xlink:href="#i-' + name + '"/></svg>'; }
  function basename(p) { var s = p.split('/'); return s[s.length - 1]; }
  function dirname(p) { var i = p.lastIndexOf('/'); return i > 0 ? p.slice(0, i) : p; }
  function stripExt(n) { return n.replace(/\.[^.]+$/, ''); }
  function extOf(p) { var m = /\.([^.\/]+)$/.exec(p); return m ? m[1].toLowerCase() : ''; }
  function kindOfExt(e) {
    if (e === 'skp') return 'model';
    if (e === 'skm') return 'material';
    if (['jpg', 'jpeg', 'png', 'bmp', 'gif', 'tif', 'tiff', 'tga', 'webp'].indexOf(e) >= 0) return 'texture';
    if (MESH_EXTS.indexOf(e) >= 0) return 'mesh';
    return null;
  }
  function fmtSize(b) {
    if (!b && b !== 0) return '';
    if (b < 1024) return b + ' B';
    if (b < 1048576) return (b / 1024).toFixed(0) + ' KB';
    return (b / 1048576).toFixed(1) + ' MB';
  }
  function fmtDate(sec) {
    if (!sec) return '';
    var d = new Date(sec * 1000);
    return d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2);
  }
  function suYear(v) { return v >= 13 ? 2000 + v : v; }
  function isMatView() { return S.view === 'materials'; }
  var MESH_EXTS = ['glb', 'gltf', 'fbx', 'obj', 'dae', '3ds', 'stl', 'ply', 'wrl', 'vrml', 'usdz'];
  function isModelKind(it) { return it.k === 'model' || it.k === 'mesh'; }
  function catOf(it) { return isModelKind(it) ? 'model' : 'mat'; }
  function viewCat() { return S.view === 'models' ? 'model' : 'mat'; }
  function rootVisible(r, cat) { return r.type === 'both' || (cat === 'model' ? r.type === 'models' : r.type === 'materials'); }
  function favSet() {
    var o = {};
    (S.settings.favorites || []).forEach(function (p) { o[p] = true; });
    return o;
  }
  function store(k, v) { try { window.localStorage.setItem('bb_' + k, JSON.stringify(v)); } catch (e) { /* ignore */ } }
  function load(k, d) {
    try { var v = window.localStorage.getItem('bb_' + k); return v ? JSON.parse(v) : d; } catch (e) { return d; }
  }
  function saveSettings(values) {
    Object.keys(values).forEach(function (k) { S.settings[k] = values[k]; });
    return call('settings', { values: values });
  }

  var toastTimer = null;
  function toast(msg, err) {
    var box = $('toast');
    var d = document.createElement('div');
    d.className = 't' + (err ? ' err' : '');
    d.textContent = msg;
    box.appendChild(d);
    setTimeout(function () { if (d.parentNode) d.parentNode.removeChild(d); }, err ? 4200 : 2200);
  }
  BB.toast = toast;

  // ---------------------------------------------------------------- modal
  function modal(title, body, opts) {
    opts = opts || {};
    return new Promise(function (resolve) {
      var m = $('modal');
      m.innerHTML = '<div class="box"><h4>' + esc(title) + '</h4>' + (body || '') +
        '<div class="acts"><button class="btn" data-a="no">' + esc(t('cancel')) + '</button>' +
        '<button class="btn ' + (opts.danger ? 'danger' : 'pri') + '" data-a="ok">' + esc(opts.ok || t('ok')) + '</button></div></div>';
      m.classList.remove('hidden');
      var inp = m.querySelector('input');
      if (inp) { inp.focus(); inp.select(); }
      function done(ok) {
        m.classList.add('hidden');
        var v = inp ? inp.value : true;
        m.innerHTML = '';
        resolve(ok ? v : null);
      }
      m.onclick = function (e) {
        var a = e.target.getAttribute('data-a');
        if (a === 'ok') done(true);
        else if (a === 'no' || e.target === m) done(false);
      };
      m.onkeydown = function (e) {
        if (e.keyCode === 13) done(true);
        if (e.keyCode === 27) done(false);
      };
      if (!inp) m.querySelector('[data-a="ok"]').focus();
    });
  }
  function prompt2(title, value) {
    return modal(title, '<input class="inp" value="' + esc(value || '') + '">');
  }
  function confirm2(title, text, danger) {
    return modal(title, '<p>' + esc(text) + '</p>', { danger: danger, ok: danger ? t('delete') : t('ok') });
  }

  // ---------------------------------------------------------------- context menu
  function showMenu(e, items) {
    e.preventDefault();
    var m = $('ctx');
    var html = '';
    items.forEach(function (it, i) {
      if (!it) return;
      if (it.sep) { html += '<div class="ms"></div>'; return; }
      if (it.head) { html += '<div class="mh">' + esc(it.head) + '</div>'; return; }
      html += '<div class="mi' + (it.danger ? ' danger' : '') + (it.disabled ? ' dis' : '') + '" data-i="' + i + '">' +
        icon(it.icon || 'caret') + '<span>' + esc(it.label) + '</span></div>';
    });
    m.innerHTML = html;
    m.classList.remove('hidden');
    var w = m.offsetWidth;
    var h = m.offsetHeight;
    var x = Math.min(e.clientX, window.innerWidth - w - 6);
    var y = Math.min(e.clientY, window.innerHeight - h - 6);
    m.style.left = Math.max(4, x) + 'px';
    m.style.top = Math.max(4, y) + 'px';
    m.onclick = function (ev) {
      var el = ev.target.closest('.mi');
      if (!el) return;
      hideMenu();
      var it = items[+el.getAttribute('data-i')];
      if (it && it.action) it.action();
    };
  }
  function hideMenu() { $('ctx').classList.add('hidden'); }

  // ---------------------------------------------------------------- data
  function relFolder(it) {
    var r = it.r || '';
    var f = it.f || '';
    return f.length > r.length ? f.slice(r.length + 1) : '';
  }

  function rebuild() {
    S.items = [];
    S.byPath = {};
    S.trees = {};
    S.roots = S.settings.roots || [];
    S.roots.forEach(function (root) {
      var idx = S.indexes[root.path];
      var nodes = {};
      var top = { p: root.path, n: root.name || basename(root.path), d: null, kids: [], cnt: { model: 0, mat: 0 }, smp: { model: [], mat: [] }, root: root };
      nodes[root.path] = top;
      if (idx) {
        (idx.folders || []).forEach(function (f) {
          nodes[f.p] = { p: f.p, n: f.n, d: f.d, kids: [], cnt: { model: 0, mat: 0 }, smp: { model: [], mat: [] } };
        });
        (idx.folders || []).forEach(function (f) {
          var parent = nodes[f.d];
          if (parent) parent.kids.push(nodes[f.p]);
        });
        (idx.items || []).forEach(function (it) {
          it.r = root.path;
          it.rt = root.type;
          it.q = (it.n + ' ' + relFolder(it)).toLowerCase();
          S.items.push(it);
          S.byPath[it.p] = it;
          var c = catOf(it);
          var node = nodes[it.f];
          var guard = 0;
          while (node && guard++ < 64) {
            node.cnt[c]++;
            if (node.smp[c].length < 4) node.smp[c].push(it.p);
            node = node.d ? nodes[node.d] : null;
          }
        });
      }
      Object.keys(nodes).forEach(function (k) {
        nodes[k].kids.sort(function (a, b) { return a.n.localeCompare(b.n, undefined, { numeric: true, sensitivity: 'base' }); });
      });
      top.missing = idx && idx.exists === false;
      top.pending = !idx || idx.pending;
      S.trees[root.path] = { top: top, nodes: nodes };
    });
  }

  function stubItem(p) {
    var e = extOf(p);
    return { p: p, n: stripExt(basename(p)), e: e, k: kindOfExt(e) || 'model', f: dirname(p), stub: true, q: basename(p).toLowerCase() };
  }

  function currentList() {
    var list, folderMode = false, folder = null;
    var view = S.view;
    if (view === 'models' || view === 'materials') {
      var cat = viewCat();
      folder = S.folder[view];
      // folder mode: a folder shows its sub-folders as cards plus only its own files;
      // a search (or the flat mode) lists everything inside instead
      folderMode = !S.search.trim() && S.settings.folder_view !== 'flat';
      var visibleRoots = {}, nVisible = 0, onlyRoot = null;
      S.roots.forEach(function (r) { if (rootVisible(r, cat)) { visibleRoots[r.path] = true; nVisible++; onlyRoot = r.path; } });
      // a single library: "All libraries" opens straight into its folders
      if (folderMode && !folder && nVisible === 1) folder = onlyRoot;
      list = S.items.filter(function (it) {
        if (catOf(it) !== cat || !visibleRoots[it.r]) return false;
        if (folderMode) {
          if (!folder || it.f !== folder) return false;
        } else if (folder) {
          if (!(it.f === folder || it.f.indexOf(folder + '/') === 0)) return false;
        }
        if (cat === 'mat' && S.matFilter !== 'all') {
          if (S.matFilter === 'skm' && it.k !== 'material') return false;
          if (S.matFilter === 'img' && it.k !== 'texture') return false;
        }
        return true;
      });
    } else if (view === 'favorites') {
      list = (S.settings.favorites || []).map(function (p) { return S.byPath[p] || stubItem(p); });
    } else if (view === 'recent') {
      list = (S.settings.recent || []).map(function (p) { return S.byPath[p] || stubItem(p); });
    } else {
      list = [];
    }
    var q = S.search.trim().toLowerCase();
    if (q) {
      var words = q.split(/\s+/);
      list = list.filter(function (it) {
        var hay = it.q || (it.n || '').toLowerCase();
        for (var i = 0; i < words.length; i++) if (hay.indexOf(words[i]) < 0) return false;
        return true;
      });
    }
    if (view !== 'recent') sortList(list);
    if (folderMode) list = folderEntries(viewCat(), folder).concat(list);
    return list;
  }

  // Sub-folders of the open folder (or the libraries themselves at the top level).
  function folderEntries(cat, folder) {
    var nodes;
    if (folder) {
      var n = findNode(folder);
      nodes = n ? n.kids : [];
    } else {
      nodes = [];
      S.roots.forEach(function (r) { if (rootVisible(r, cat) && S.trees[r.path]) nodes.push(S.trees[r.path].top); });
    }
    return nodes.filter(function (n) { return n.cnt[cat] > 0; }).map(function (n) {
      return { dir: true, p: n.p, n: n.root ? (n.root.name || n.n) : n.n, node: n };
    });
  }

  function sortList(list) {
    var sort = S.settings.sort || 'name_asc';
    var usage = S.settings.usage || {};
    var byName = function (a, b) { return a.n.localeCompare(b.n, undefined, { numeric: true, sensitivity: 'base' }); };
    var f = {
      name_asc: byName,
      name_desc: function (a, b) { return byName(b, a); },
      date_desc: function (a, b) { return (b.m || 0) - (a.m || 0); },
      date_asc: function (a, b) { return (a.m || 0) - (b.m || 0); },
      size_desc: function (a, b) { return (b.s || 0) - (a.s || 0); },
      size_asc: function (a, b) { return (a.s || 0) - (b.s || 0); },
      used_desc: function (a, b) { return (usage[b.p] || 0) - (usage[a.p] || 0) || byName(a, b); }
    }[sort] || byName;
    list.sort(f);
  }

  // ---------------------------------------------------------------- thumbnails
  var thumbQueue = [];
  var thumbTimer = null;
  function wantThumb(p) {
    if (S.thumbs[p] !== undefined || S.requested[p]) return;
    S.requested[p] = true;
    thumbQueue.push(p);
    if (!thumbTimer) {
      thumbTimer = setTimeout(function () {
        thumbTimer = null;
        var batch = thumbQueue.splice(0, thumbQueue.length);
        if (batch.length) call('thumbs', { paths: batch });
      }, 40);
    }
  }
  BB.on('thumbs', function (map) {
    Object.keys(map).forEach(function (p) {
      S.thumbs[p] = map[p] || null;
      var el = S.cardEls[p];
      if (el) setCardThumb(el, S.byPath[p] || stubItem(p));
      (S.mosEls[p] || []).forEach(function (cell) { setMosaic(cell, map[p]); });
    });
  });

  var observer = null;
  if (window.IntersectionObserver) {
    observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) {
          var p = en.target.getAttribute('data-p');
          observer.unobserve(en.target);
          wantThumb(p);
        }
      });
    }, { root: $('content'), rootMargin: '300px' });
  }

  function phHtml(it) {
    var ic = isModelKind(it) ? 'cube' : 'swatch';
    return '<div class="ph">' + icon(ic) + '<span>' + esc((it.e || '').toUpperCase()) + '</span></div>';
  }

  // The image is shown only once it is completely loaded and decoded, so a card
  // never shows half a picture; the placeholder stays until then.
  function setCardThumb(card, it) {
    var th = card.querySelector('.th');
    var url = S.thumbs[it.p];
    if (url) {
      var img = th.querySelector('img');
      if (img && img.getAttribute('data-src') === url) return;
      var next = document.createElement('img');
      next.setAttribute('decoding', 'async');
      next.setAttribute('data-src', url);
      next.className = 'ld';
      next.onload = function () {
        if (!next.parentNode) return;
        Array.prototype.forEach.call(th.querySelectorAll('.ph, img'), function (x) { if (x !== next) th.removeChild(x); });
        next.className = '';
        maybeShrink(it.p, next, url);
      };
      next.onerror = function () { if (next.parentNode) next.parentNode.removeChild(next); if (!th.querySelector('.ph, img')) th.innerHTML = phHtml(it); };
      if (!th.querySelector('.ph, img')) th.innerHTML = phHtml(it);
      th.appendChild(next);
      next.src = url;
    } else if (!th.querySelector('.ph')) {
      th.innerHTML = phHtml(it);
    }
  }

  // Big preview images (large textures, big sidecar images) are slow to decode every
  // time: make a small copy once, in the background, one image at a time.
  var shrinkQueue = [], shrinking = false, shrinkSeen = {};
  var SHRINK_MAX = 360;
  function isSmallUrl(u) { return /\.s\.(jpg|png)(\?|$)/.test(u); }
  function maybeShrink(p, img, url) {
    if (shrinkSeen[p] || isSmallUrl(url) || !/^file:/.test(url)) return;
    if (Math.max(img.naturalWidth, img.naturalHeight) <= SHRINK_MAX * 1.6) return;
    shrinkSeen[p] = true;
    shrinkQueue.push({ p: p, img: img, url: url });
    if (!shrinking) setTimeout(nextShrink, 400);
  }
  function fileOfUrl(u) {
    var s = u.replace(/^file:\/\/\/?/, '').replace(/\?.*$/, '');
    try { s = decodeURIComponent(s); } catch (e) { /* keep */ }
    return /^[A-Za-z]:/.test(s) ? s : '/' + s.replace(/^\/+/, '');
  }
  function scaled(img) {
    var w = img.naturalWidth, h = img.naturalHeight, k = SHRINK_MAX / Math.max(w, h);
    var c = document.createElement('canvas');
    c.width = Math.max(1, Math.round(w * k)); c.height = Math.max(1, Math.round(h * k));
    var x = c.getContext('2d');
    x.imageSmoothingQuality = 'high';
    x.drawImage(img, 0, 0, c.width, c.height);
    return c;
  }
  function encode(c, png) {
    return png ? c.toDataURL('image/png').split(',')[1] : c.toDataURL('image/jpeg', 0.86).split(',')[1];
  }
  function nextShrink() {
    var job = shrinkQueue.shift();
    if (!job) { shrinking = false; return; }
    shrinking = true;
    var png = /\.png(\?|$)/i.test(job.url);
    var done = function () { setTimeout(nextShrink, 150); };
    var save = function (data) {
      if (!data) { done(); return; }
      call('save_thumb', { path: job.p, data: data, ext: png ? '.png' : '.jpg' }).then(function (u) {
        if (u) S.thumbs[job.p] = u; // used next time; the visible picture stays as it is
        done();
      }, done);
    };
    try {
      save(encode(scaled(job.img), png));
    } catch (e) {
      // file images can make the canvas "tainted": read the bytes through Ruby instead
      var src = fileOfUrl(job.url);
      call('read_b64', { path: src, max: 16 * 1048576 }).then(function (b64) {
        if (!b64) { done(); return; }
        var im = new Image();
        im.onload = function () { try { save(encode(scaled(im), png)); } catch (e2) { done(); } };
        im.onerror = done;
        im.src = 'data:image/' + (png ? 'png' : 'jpeg') + ';base64,' + b64;
      }, done);
    }
  }

  // ---------------------------------------------------------------- rendering: shell
  var VIEWS = [
    ['models', 'cube'], ['materials', 'swatch'], ['favorites', 'star'], ['recent', 'clock'],
    ['inmodel', 'layers'], ['tools', 'tools']
  ];

  function renderRail() {
    var h = '<div class="logo" title="Banian Browser">B</div>';
    VIEWS.forEach(function (v) {
      h += '<button data-v="' + v[0] + '" class="' + (S.view === v[0] ? 'on' : '') + '" title="' + esc(t('v_' + v[0])) + '">' +
        icon(v[1]) + '<span>' + esc(t('v_' + v[0])) + '</span></button>';
    });
    h += '<div class="spacer"></div><button data-v="settings" class="' + (S.view === 'settings' ? 'on' : '') + '">' +
      icon('gear') + '<span>' + esc(t('v_settings')) + '</span></button>';
    $('rail').innerHTML = h;
  }

  function setView(v) {
    if (v !== S.view) S.search = '';
    S.view = v;
    store('view', v);
    call('page', { page: v });
    S.replaceArmed = S.replaceArmed && (v === 'materials' || v === 'inmodel' || v === 'favorites' || v === 'recent');
    renderAll();
    if (v === 'inmodel') loadModelMats();
    if (v === 'tools') { call('picked').then(function (p) { S.picked = p; renderContent(); renderStatus(); }); loadTarget(); }
  }

  function hasTree() { return S.view === 'models' || S.view === 'materials'; }

  function renderAll() {
    document.documentElement.setAttribute('dir', S.settings.language === 'en' ? 'ltr' : 'rtl');
    document.documentElement.setAttribute('lang', S.settings.language === 'en' ? 'en' : 'fa');
    document.body.className = S.settings.theme === 'dark' ? 'dark' : '';
    renderRail();
    $('side').className = hasTree() ? (S.sideOpen ? '' : 'collapsed') : 'hidden';
    renderSideHead();
    renderTree();
    renderTopbar();
    renderPins();
    renderContent();
    renderStatus();
  }

  function renderSideHead() {
    if (!hasTree()) return;
    $('side-head').innerHTML = '<span class="ttl">' + esc(t('libraries')) + '</span>' +
      '<button class="btn icon" data-act="rescan" title="' + esc(t('rescan')) + '">' + icon('refresh') + '</button>' +
      '<button class="btn icon" data-act="add-root" title="' + esc(t('add_library')) + '" style="margin:0 4px">' + icon('plus') + '</button>';
  }

  // ---------------------------------------------------------------- tree
  function renderTree() {
    if (!hasTree()) return;
    var cat = viewCat();
    var roots = S.roots.filter(function (r) { return rootVisible(r, cat); });
    var tree = $('tree');
    if (!roots.length) {
      tree.innerHTML = '<div class="side-empty">' + esc(t(cat === 'model' ? 'no_model_lib' : 'no_mat_lib')) + '</div>';
      return;
    }
    var sel = S.folder[S.view];
    var total = 0;
    roots.forEach(function (r) { total += S.trees[r.path] ? S.trees[r.path].top.cnt[cat] : 0; });
    var h = '<div class="node all' + (sel ? '' : ' on') + '" data-p=""><span class="car">' + icon('layers', 'fi') + '</span>' +
      '<span class="nm">' + esc(t('all_libraries')) + '</span><span class="ct">' + total + '</span></div>';
    roots.forEach(function (r) {
      var tr = S.trees[r.path];
      if (tr) h += nodeHtml(tr.top, 0, cat, sel);
    });
    tree.innerHTML = h;
  }

  function nodeHtml(node, depth, cat, sel) {
    var isRoot = depth === 0;
    var kids = node.kids.filter(function (k) { return k.cnt[cat] > 0; });
    var open = S.expanded[node.p] !== undefined ? S.expanded[node.p] : isRoot;
    var cls = 'node' + (isRoot ? ' root' : '') + (sel === node.p ? ' on' : '') + (open && kids.length ? ' open' : '');
    var label = esc(node.n);
    var extra = '';
    if (isRoot) {
      if (S.scanning[node.p]) extra += '<span class="rt">' + esc(t('scanning')) + '</span>';
      else if (node.missing) extra += '<span class="rt" style="color:var(--danger)">' + esc(t('missing')) + '</span>';
    }
    // roots are quiet section headers; folders are plain text rows with an indent
    var pad = isRoot ? 2 : 2 + (depth - 1) * 16;
    var h = '<div class="' + cls + '" data-p="' + esc(node.p) + '" style="-webkit-padding-start:' + pad + 'px;padding-inline-start:' + pad + 'px">' +
      '<span class="car" data-t="1">' + (kids.length ? icon('caret') : '<i class="dot"></i>') + '</span>' +
      '<span class="nm" title="' + esc(node.p) + '">' + label + '</span>' + extra +
      '<span class="ct">' + node.cnt[cat] + '</span></div>';
    if (open) kids.forEach(function (k) { h += nodeHtml(k, depth + 1, cat, sel); });
    return h;
  }

  function findNode(p) {
    for (var i = 0; i < S.roots.length; i++) {
      var tr = S.trees[S.roots[i].path];
      if (tr && tr.nodes[p]) return tr.nodes[p];
    }
    return null;
  }

  function rootOf(p) {
    var best = null;
    S.roots.forEach(function (r) {
      if ((p === r.path || p.indexOf(r.path + '/') === 0) && (!best || r.path.length > best.path.length)) best = r;
    });
    return best;
  }

  function openFolder(p) {
    S.search = '';
    var q = $('q');
    if (q) q.value = '';
    selectFolder(p);
    renderPins();
  }

  function selectFolder(p) {
    S.folder[S.view] = p || null;
    if (p) {
      S.expanded[p] = true;
      // expand ancestors
      var n = findNode(p);
      var guard = 0;
      while (n && n.d && guard++ < 64) {
        S.expanded[n.d] = true;
        n = findNode(n.d);
      }
    }
    store('folder', S.folder);
    store('expanded', S.expanded);
    renderTree();
    renderContent();
  }

  // ---------------------------------------------------------------- top bar
  function renderTopbar() {
    var v = S.view;
    var bar = $('topbar');
    if (v === 'tools' || v === 'settings') {
      bar.innerHTML = '<b style="font-size:15px;padding:4px">' + esc(t('v_' + v)) + '</b>';
      return;
    }
    var h = '';
    if (hasTree()) h += '<button class="btn icon" data-act="toggle-side" title="' + esc(t('folders')) + '">' + icon('menu') + '</button>';
    h += '<div class="search">' + icon('search') + '<input id="q" placeholder="' + esc(t('search_ph')) + '" value="' + esc(S.search) + '">' +
      '<button class="clr' + (S.search ? '' : ' hidden') + '" data-act="clear-search">' + icon('x') + '</button></div>';
    if (v === 'models') {
      h += '<div class="seg" title="' + esc(t('place_mode')) + '">';
      [['normal', 'pm_normal'], ['fit3', 'pm_fit3'], ['fit2', 'pm_fit2'], ['surface', 'pm_surface']].forEach(function (m) {
        h += '<button data-pm="' + m[0] + '" class="' + ((S.settings.place_mode || 'normal') === m[0] ? 'on' : '') + '" title="' + esc(t(m[1] + '_tip')) + '">' + esc(t(m[1])) + '</button>';
      });
      h += '</div>';
    }
    if (v === 'materials') {
      h += '<div class="seg">';
      [['all', 'mf_all'], ['skm', 'mf_skm'], ['img', 'mf_img']].forEach(function (m) {
        h += '<button data-mf="' + m[0] + '" class="' + (S.matFilter === m[0] ? 'on' : '') + '">' + esc(t(m[1])) + '</button>';
      });
      h += '</div>';
    }
    if (v !== 'inmodel') {
      h += '<select id="sort" title="' + esc(t('sort')) + '">';
      ['name_asc', 'name_desc', 'date_desc', 'date_asc', 'size_desc', 'size_asc', 'used_desc'].forEach(function (k) {
        h += '<option value="' + k + '"' + ((S.settings.sort || 'name_asc') === k ? ' selected' : '') + '>' + esc(t('s_' + k)) + '</option>';
      });
      h += '</select>';
    }
    if (hasTree()) {
      h += '<button class="btn icon' + (S.settings.folder_view === 'flat' ? ' on' : '') + '" data-act="folder-view" title="' + esc(t('recursive_tip')) + '">' + icon('sub') + '</button>';
    }
    if (v !== 'inmodel') {
      h += '<button class="btn icon' + (S.settings.show_info ? ' on' : '') + '" data-act="toggle-info" title="' + esc(t('info_tip')) + '">' + icon('info') + '</button>';
    }
    if (v === 'inmodel') {
      h += '<button class="btn" data-act="mm-refresh">' + icon('refresh') + '<span>' + esc(t('refresh')) + '</span></button>';
    }
    h += '<span class="size">' + icon('fit') + '<input type="range" id="csize" min="90" max="280" step="10" value="' + (S.settings.card_size || 150) + '"></span>';
    bar.innerHTML = h;
  }

  // ---------------------------------------------------------------- pinned folders
  function pinList(view) {
    var map = S.settings.pinned || {};
    return (map[view || S.view] || []).slice();
  }
  function isPinned(p, view) { return pinList(view).indexOf(p) >= 0; }

  function renderPins() {
    var bar = $('pins');
    var list = hasTree() ? pinList() : [];
    if (!list.length) { bar.className = 'hidden'; bar.innerHTML = ''; return; }
    var cat = viewCat();
    var sel = S.folder[S.view];
    var h = '<span class="pin-ic" title="' + esc(t('pinned_tip')) + '">' + icon('pin') + '</span>';
    list.forEach(function (p) {
      var node = findNode(p);
      var name = node ? (node.root ? (node.root.name || node.n) : node.n) : basename(p);
      h += '<button class="chip' + (sel === p ? ' on' : '') + (node ? '' : ' gone') + '" data-pin="' + esc(p) + '" title="' + esc(p) + '">' +
        icon('folder') + '<span>' + esc(name) + '</span>' + (node ? '<i>' + node.cnt[cat] + '</i>' : '') + '</button>';
    });
    bar.className = '';
    bar.innerHTML = h;
  }

  function togglePin(p) {
    call('pin', { view: S.view, path: p }).then(function (map) {
      if (!map) return;
      S.settings.pinned = map;
      renderPins(); renderCrumbs(S.list ? S.list.length : 0);
      toast(isPinned(p) ? t('pin') : t('unpin'));
    });
  }

  function pinMenu(e, p) {
    var list = pinList();
    var i = list.indexOf(p);
    showMenu(e, [
      { head: basename(p) },
      { label: t('move_left'), icon: 'caret', disabled: i <= 0, action: function () { movePin(p, -1); } },
      { label: t('move_right'), icon: 'caret', disabled: i >= list.length - 1, action: function () { movePin(p, 1); } },
      { label: t('show_in_folder'), icon: 'folder', action: function () { call('reveal', { path: p }); } },
      { sep: true },
      { label: t('unpin'), icon: 'x', action: function () { togglePin(p); } }
    ]);
  }

  function movePin(p, d) {
    call('pin_move', { view: S.view, path: p, delta: d }).then(function (map) {
      if (map) { S.settings.pinned = map; renderPins(); }
    });
  }

  // ---------------------------------------------------------------- crumbs
  function renderCrumbs(count) {
    var c = $('crumbs');
    var v = S.view;
    if (!(hasTree() || v === 'favorites' || v === 'recent' || v === 'inmodel')) { c.className = 'hidden'; return; }
    c.className = '';
    var h = '';
    if (hasTree()) {
      var folder = S.folder[v];
      h += '<span class="cr" data-p="">' + esc(t('all_libraries')) + '</span>';
      if (folder) {
        var root = rootOf(folder);
        if (root) {
          var parts = [root.path];
          var rest = folder.slice(root.path.length + 1);
          var acc = root.path;
          if (rest) rest.split('/').forEach(function (s) { acc += '/' + s; parts.push(acc); });
          parts.forEach(function (p, i) {
            h += '<span class="sep">›</span><span class="cr" data-p="' + esc(p) + '">' + esc(i === 0 ? (root.name || basename(root.path)) : basename(p)) + '</span>';
          });
        }
      }
    } else {
      h += '<b>' + esc(t('v_' + v)) + '</b>';
    }
    h += '<span class="grow"></span><span class="cnt">' + count + ' ' + esc(t('items')) + '</span>';
    if (hasTree() && S.folder[v]) {
      var pinned = isPinned(S.folder[v]);
      h += '<button class="btn' + (pinned ? ' on' : '') + '" data-act="pin-here" title="' + esc(t(pinned ? 'unpin' : 'pin')) + '">' + icon('pin') + '</button>';
      h += '<button class="btn" data-act="mkdir" title="' + esc(t('new_folder')) + '">' + icon('folder-plus') + '</button>';
      if (v === 'models') h += '<button class="btn" data-act="save-sel-here" title="' + esc(t('save_sel_here_tip')) + '">' + icon('save') + '<span>' + esc(t('save_sel_here')) + '</span></button>';
      if (v === 'materials') h += '<button class="btn" data-act="import-mat-folder" title="' + esc(t('import_folder_mats')) + '">' + icon('plus') + '</button>';
      if (v === 'materials') h += '<button class="btn" data-act="save-mat-here" title="' + esc(t('save_mat_here_tip')) + '">' + icon('save') + '<span>' + esc(t('save_mat_here')) + '</span></button>';
    }
    if (v === 'inmodel') {
      h += '<button class="btn" data-act="mm-purge">' + esc(t('purge_unused')) + '</button>';
    }
    if (v === 'materials' || v === 'inmodel') {
      h += '<button class="btn" data-act="import-mat-file">' + icon('plus') + '<span>' + esc(t('import_mat_file')) + '</span></button>';
    }
    if (v === 'models') {
      h += '<button class="btn" data-act="import-browse">' + icon('cube') + '<span>' + esc(t('import_model')) + '</span></button>';
    }
    c.innerHTML = h;
  }

  // ---------------------------------------------------------------- content
  function renderContent() {
    var v = S.view;
    var box = $('content');
    S.cardEls = {};
    S.mosEls = {};
    if (observer) observer.disconnect();
    if (v === 'tools') { renderCrumbs(0); box.innerHTML = toolsHtml(); return; }
    if (v === 'settings') { renderCrumbs(0); box.innerHTML = settingsHtml(); return; }
    if (v === 'inmodel') { renderModelMats(); return; }
    S.list = currentList();
    renderCrumbs(S.list.length);
    box.scrollTop = 0;
    if (!S.list.length) {
      box.innerHTML = emptyHtml();
      return;
    }
    box.innerHTML = '<div class="grid" id="grid"></div>';
    S.rendered = 0;
    renderMore();
  }

  function emptyHtml() {
    var v = S.view;
    if (hasTree()) {
      var cat = viewCat();
      var any = S.roots.some(function (r) { return rootVisible(r, cat); });
      if (!any) {
        var type = cat === 'model' ? 'models' : 'materials';
        return '<div class="empty">' + esc(t(cat === 'model' ? 'no_model_lib' : 'no_mat_lib')) + '<br>' +
          '<button class="btn pri" data-act="add-root" data-type="' + type + '">' + icon('folder-plus') + '<span>' + esc(t('add_library')) + '</span></button></div>';
      }
      if (S.search) return '<div class="empty">' + esc(t('no_results')) + '</div>';
      return '<div class="empty">' + esc(t('folder_empty')) + '</div>';
    }
    if (v === 'favorites') return '<div class="empty">' + esc(t('no_favorites')) + '</div>';
    if (v === 'recent') return '<div class="empty">' + esc(t('no_recent')) + '</div>';
    return '<div class="empty">' + esc(t('no_results')) + '</div>';
  }

  function cardSize() { return +(S.settings.card_size || 150); }

  function renderMore() {
    var grid = $('grid');
    if (!grid) return;
    var start = S.rendered;
    var end = Math.min(S.list.length, start + PAGE);
    var size = cardSize();
    var favs = favSet();
    var frag = document.createDocumentFragment();
    for (var i = start; i < end; i++) {
      var it = S.list[i];
      if (it.dir) { frag.appendChild(folderCard(it, i, size)); continue; }
      var card = document.createElement('div');
      card.className = 'card' + (isModelKind(it) ? '' : ' mat');
      card.setAttribute('data-i', i);
      card.setAttribute('data-p', it.p);
      card.setAttribute('draggable', 'true');
      card.style.width = size + 'px';
      var tip = it.n + '.' + it.e + '\n' + (it.f || '') + (it.s ? '\n' + fmtSize(it.s) + '  ·  ' + fmtDate(it.m) : '');
      if (it.v) tip += '\nSketchUp ' + suYear(it.v);
      card.title = tip;
      var ver = '';
      if (it.k === 'model' && it.v) {
        ver = '<span class="ver' + (it.v > S.info.su ? ' new' : '') + '">' + suYear(it.v) + '</span>';
      } else if (it.k === 'mesh') {
        ver = '<span class="ver">' + esc(it.e.toUpperCase()) + '</span>';
      }
      var info = !!S.settings.show_info;
      var showExt = (S.settings.show_ext || info) ? '<span class="ext">.' + esc(it.e) + '</span>' : '';
      if (info) card.className += ' info';
      card.innerHTML = '<div class="th" style="height:' + size + 'px"></div>' + ver +
        '<button class="fav' + (favs[it.p] ? ' on' : '') + '" data-act="fav" title="' + esc(t('favorite')) + '">' + icon('star') + '</button>' +
        '<div class="cap">' + esc(it.n) + showExt + '</div>' + (info ? '<div class="meta">' + metaHtml(it) + '</div>' : '');
      setCardThumb(card, it);
      S.cardEls[it.p] = card;
      frag.appendChild(card);
      if (S.thumbs[it.p] === undefined) {
        if (observer) observer.observe(card);
        else wantThumb(it.p);
      }
    }
    grid.appendChild(frag);
    S.rendered = end;
  }

  // Folder card: a 2x2 mosaic of what is inside, the name and the number of items.
  function folderCard(it, i, size) {
    var cat = viewCat();
    var card = document.createElement('div');
    card.className = 'card folder';
    card.setAttribute('data-dir', it.p);
    card.setAttribute('data-i', i);
    card.style.width = size + 'px';
    card.title = it.p;
    var smp = it.node.smp[cat] || [];
    var cells = '';
    for (var k = 0; k < 4; k++) cells += '<i' + (smp[k] ? ' data-mp="' + esc(smp[k]) + '"' : '') + '></i>';
    card.innerHTML = '<div class="th" style="height:' + Math.round(size * 0.78) + 'px"><div class="mos">' + cells + '</div>' +
      '<span class="fbadge">' + icon('folder') + '</span></div>' +
      '<div class="cap">' + esc(it.n) + '</div><div class="meta"><span>' + it.node.cnt[cat] + ' ' + esc(t('items')) + '</span></div>';
    Array.prototype.forEach.call(card.querySelectorAll('[data-mp]'), function (cell) {
      var p = cell.getAttribute('data-mp');
      (S.mosEls[p] = S.mosEls[p] || []).push(cell);
      if (S.thumbs[p]) setMosaic(cell, S.thumbs[p]);
      else if (S.thumbs[p] === undefined) wantThumb(p);
    });
    return card;
  }
  function setMosaic(cell, url) {
    if (!url) { cell.className = 'none'; return; }
    var img = new Image();
    img.onload = function () { cell.style.backgroundImage = 'url("' + url.replace(/"/g, '%22') + '")'; cell.className = 'ok'; };
    img.src = url;
  }

  function metaHtml(it) {
    var bits = [];
    if (it.s || it.s === 0) bits.push(fmtSize(it.s));
    if (it.m) bits.push(fmtDate(it.m));
    var folder = relFolder(it);
    return '<span>' + esc(bits.join(' · ')) + '</span>' + (folder && S.search ? '<span class="fd">' + esc(folder) + '</span>' : '');
  }

  // ---------------------------------------------------------------- model materials view
  function loadModelMats() {
    return call('model_mats').then(function (list) {
      S.modelMats = list || [];
      if (S.view === 'inmodel') renderModelMats();
    });
  }

  function renderModelMats() {
    var box = $('content');
    var q = S.search.trim().toLowerCase();
    var list = S.modelMats.filter(function (m) { return !q || m.display.toLowerCase().indexOf(q) >= 0; });
    renderCrumbs(list.length);
    if (!list.length) { box.innerHTML = '<div class="empty">' + esc(t('no_model_mats')) + '</div>'; return; }
    var size = cardSize();
    var h = '<div class="grid">';
    list.forEach(function (m, i) {
      var bg = m.thumb ? '<img src="' + esc(m.thumb) + '">' : '<div style="width:100%;height:100%;background:' + esc(m.color || '#ccc') + ';opacity:' + (m.alpha == null ? 1 : m.alpha) + '"></div>';
      h += '<div class="card mat mm' + (m.current ? ' cur' : '') + (m.used ? '' : ' unused') + '" data-mm="' + i + '" style="width:' + size + 'px" title="' + esc(m.display + (m.texture ? '\n' + m.width + ' × ' + m.height + ' cm' : '')) + '">' +
        '<div class="th" style="height:' + size + 'px">' + bg + '</div>' +
        (m.used ? '' : '<span class="ver">' + esc(t('unused')) + '</span>') +
        '<div class="cap">' + esc(m.display) + '</div></div>';
    });
    h += '</div>';
    box.innerHTML = h;
    S.mmList = list;
  }

  // ---------------------------------------------------------------- tools view
  function picked() { return S.picked; }

  function swatchStyle(p) {
    if (!p) return 'background:repeating-linear-gradient(45deg,#ddd 0 6px,#f4f4f4 6px 12px)';
    if (p.thumb) return 'background-image:url(\'' + p.thumb.replace(/'/g, '%27') + '\')';
    return 'background:' + (p.color || '#ccc');
  }

  // What the texture buttons will change: the selection, or the SketchUp material.
  function targetHtml() {
    var tt = S.texTarget;
    if (!tt) return '';
    var m = tt.mat, sw = '<div class="sw" style="' + swatchStyle(m) + '"></div>', txt, warn = false;
    if (tt.mode === 'selection') {
      if (!tt.faces) { txt = esc(t('tt_sel_none')); warn = true; }
      else txt = '<b>' + esc(t('tt_sel').replace('%n', tt.faces + (tt.more ? '+' : ''))) + '</b>' + (tt.mats > 1 ? ' · ' + esc(t('tt_sel_mats').replace('%n', tt.mats)) : (m ? '<br>' + esc(m.display) : ''));
    } else if (!m) { txt = esc(t('tt_none')); warn = true; }
    else if (!tt.textured) { txt = esc(t('tt_no_tex')) + '<br><b>' + esc(m.display) + '</b>'; warn = true; }
    else txt = esc(t('tt_mat')) + '<br><b>' + esc(m.display) + '</b>';
    return '<div class="tt' + (warn ? ' warn' : '') + '">' + sw + '<div class="tx">' + txt + '</div></div>';
  }
  function loadTarget() {
    call('tex_target').then(function (tt) { if (tt) { S.texTarget = tt; var el = $('tex-target'); if (el) el.innerHTML = targetHtml(); } });
  }
  BB.on('tex_target', function (tt) {
    S.texTarget = tt;
    var el = $('tex-target');
    if (el) el.innerHTML = targetHtml();
  });

  function pickedSub(p) {
    return p.texture ? esc(p.width + ' × ' + p.height + ' cm') + (p.pixels ? ' · ' + p.pixels[0] + '×' + p.pixels[1] + ' px' : '') : esc(t('no_texture'));
  }

  function toolsHtml() {
    var p = picked();
    var h = '<div class="panels">';
    // placement
    h += '<div class="panel"><h3>' + icon('cube') + esc(t('tp_place')) + '</h3><div class="hint">' + esc(t('tp_place_hint')) + '</div>' +
      '<div class="row"><button class="btn" data-tool="fit3">' + icon('fit') + '<span>' + esc(t('pm_fit3')) + '</span></button>' +
      '<button class="btn" data-tool="fit2">' + icon('fit') + '<span>' + esc(t('pm_fit2')) + '</span></button>' +
      '<button class="btn" data-tool="surface">' + icon('cube') + '<span>' + esc(t('pm_surface')) + '</span></button></div>' +
      '<div class="hint">' + t('tp_keys') + '</div>' +
      '<div class="row"><label class="l">' + esc(t('place_rotate')) + '</label><input class="inp sm" type="number" id="place-rot" value="' + (S.settings.place_rotate || 90) + '"> °</div>' +
      '<div class="hint">' + t('place_hint') + '</div>' +
      '<div class="row"><label class="l">' + esc(t('rotate_step')) + '</label><input class="inp sm" type="number" id="rot-step" value="' + (S.settings.rotate_step || 45) + '"> °</div></div>';
    // import & simplify (Skimp-style)
    h += '<div class="panel"><h3>' + icon('fit') + esc(t('tp_import')) + '</h3><div class="hint">' + esc(t('tp_import_hint')) + '</div>' +
      '<div class="row"><button class="btn pri" data-act="import-browse">' + icon('cube') + '<span>' + esc(t('import_model')) + '</span></button>' +
      '<button class="btn" data-act="simplify-sel">' + icon('fit') + '<span>' + esc(t('simplify_sel')) + '</span></button></div></div>';
    // material tools
    h += '<div class="panel"><h3>' + icon('dropper') + esc(t('tp_mat')) + '</h3><div class="hint">' + esc(t('tp_mat_hint')) + '</div>' +
      '<div class="row"><button class="btn pri" data-act="pick">' + icon('dropper') + '<span>' + esc(t('eyedropper')) + '</span></button>' +
      '<button class="btn" data-act="bucket">' + icon('bucket') + '<span>' + esc(t('bucket')) + '</span></button>' +
      '<button class="btn" data-act="native-paint">' + icon('bucket') + '<span>' + esc(t('native_paint')) + '</span></button>' +
      '<button class="btn" data-act="replace-tex">' + icon('refresh') + '<span>' + esc(t('replace_tex_tool')) + '</span></button></div>' +
      '<div class="hint">' + esc(t('replace_tex_hint')) + '</div>' +
      '<div class="row"><button class="btn" data-act="import-mat-file">' + icon('plus') + '<span>' + esc(t('import_mat_file')) + '</span></button>' +
      '<button class="btn" data-act="import-mat-folder">' + icon('folder-plus') + '<span>' + esc(t('import_folder_mats')) + '</span></button></div>' +
      '<div class="row"><button class="btn" data-act="apply-sel">' + esc(t('apply_sel')) + '</button>' +
      '<button class="btn' + (S.replaceArmed ? ' on' : '') + '" data-act="arm-replace">' + esc(t('replace_mode')) + '</button></div>' +
      '<div class="row"><button class="btn" data-act="save-mat">' + icon('save') + '<span>' + esc(t('save_picked')) + '</span></button>' +
      '<button class="btn" data-act="export-mats">' + esc(t('export_all')) + '</button>' +
      '<button class="btn" data-act="collect-tex">' + esc(t('collect_tex')) + '</button>' +
      '<button class="btn" data-act="mm-purge">' + esc(t('purge_unused')) + '</button></div></div>';
    // picked material editor
    h += '<div class="panel" id="pm-panel"><h3>' + icon('swatch') + esc(t('tp_picked')) + '</h3>';
    if (p) {
      h += '<div class="mat-head"><div class="sw" id="pm-sw" style="' + swatchStyle(p) + '"></div><div><div class="nm" id="pm-nm">' + esc(p.display) + '</div>' +
        '<div class="sub" id="pm-sub">' + pickedSub(p) + '</div></div></div>' +
        '<div class="row"><label class="l">' + esc(t('name')) + '</label><input class="inp grow" id="pm-name" value="' + esc(p.display) + '"></div>';
      if (p.texture) {
        h += '<div class="row"><label class="l">' + esc(t('tex_size')) + '</label><input class="inp sm" type="number" step="0.1" id="pm-w" value="' + p.width + '"> × ' +
          '<input class="inp sm" type="number" step="0.1" id="pm-h" value="' + p.height + '"> cm ' +
          '<label class="chk"><input type="checkbox" id="pm-lock" checked>' + esc(t('keep_ratio')) + '</label></div>';
      }
      h += '<div class="row"><label class="l">' + esc(t('color')) + '</label><input type="color" id="pm-color" value="' + esc(p.color || '#cccccc') + '">' +
        (p.texture ? '<span class="hint" style="margin:0">' + esc(t('colorize_hint')) + '</span>' : '') + '</div>' +
        '<div class="row"><label class="l">' + esc(t('opacity')) + '</label><input type="range" id="pm-alpha" min="0" max="100" value="' + Math.round((p.alpha == null ? 1 : p.alpha) * 100) + '" class="grow">' +
        '<span id="pm-alpha-v">' + Math.round((p.alpha == null ? 1 : p.alpha) * 100) + '%</span></div>' +
        '<div class="hint">' + esc(t('live_hint')) + '</div>';
    } else {
      h += '<div class="hint">' + esc(t('nothing_picked')) + '</div>';
    }
    h += '</div>';
    // texture position
    h += '<div class="panel"><h3>' + icon('rotate') + esc(t('tp_tex')) + '</h3><div class="hint">' + esc(t('tp_tex_hint')) + '</div>' +
      '<div class="target" id="tex-target">' + targetHtml() + '</div>' +
      '<div class="row"><button class="btn" data-tex="rotate" data-v="90">↺ 90°</button><button class="btn" data-tex="rotate" data-v="-90">↻ 90°</button>' +
      '<button class="btn" data-tex="rotate" data-v="180">180°</button><input class="inp sm" type="number" id="tex-ang" value="45">' +
      '<button class="btn" data-act="tex-rot-custom">' + esc(t('rotate')) + '</button></div>' +
      '<div class="row"><button class="btn" data-tex="flip" data-v="h">⇋ ' + esc(t('flip_h')) + '</button><button class="btn" data-tex="flip" data-v="v">⇵ ' + esc(t('flip_v')) + '</button></div>' +
      '<div class="row"><button class="btn" data-tex="scale" data-v="2">' + esc(t('bigger')) + ' ×2</button><button class="btn" data-tex="scale" data-v="0.5">' + esc(t('smaller')) + ' ÷2</button>' +
      '<input class="inp sm" type="number" step="0.1" id="tex-scale" value="1.25"><button class="btn" data-act="tex-scale-custom">' + esc(t('scale')) + '</button></div>' +
      '<div class="row"><label class="l">' + esc(t('nudge')) + '</label><button class="btn icon" data-nudge="-1,0">←</button><button class="btn icon" data-nudge="1,0">→</button>' +
      '<button class="btn icon" data-nudge="0,1">↑</button><button class="btn icon" data-nudge="0,-1">↓</button>' +
      '<input class="inp sm" type="number" step="0.05" id="tex-step" value="' + (S.settings.tex_nudge || 0.1) + '"><span class="hint" style="margin:0">' + esc(t('of_tile')) + '</span></div>' +
      '<div class="row"><button class="btn" data-tex="fit">' + icon('fit') + '<span>' + esc(t('fit_face')) + '</span></button><button class="btn" data-tex="align">' + esc(t('align_edge')) + '</button>' +
      '<button class="btn" data-tex="reset">' + esc(t('reset')) + '</button></div>' +
      '<div class="row"><button class="btn" data-tex="copy">' + esc(t('copy_map')) + '</button><button class="btn" data-tex="paste">' + esc(t('paste_map')) + '</button>' +
      '<label class="chk"><input type="checkbox" id="tex-groups"' + (S.settings.tex_include_groups !== false ? ' checked' : '') + '>' + esc(t('include_groups')) + '</label></div></div>';
    // path tools
    h += '<div class="panel"><h3>' + icon('path') + esc(t('tp_path')) + '</h3><div class="hint">' + esc(t('tp_path_hint')) + '</div></div>';
    h += '</div>';
    return h;
  }

  // ---------------------------------------------------------------- settings view
  function settingsHtml() {
    var st = S.settings;
    var h = '<div class="panels">';
    h += '<div class="panel"><h3>' + icon('folder') + esc(t('libraries')) + '</h3><div class="hint">' + esc(t('lib_hint')) + '</div><div class="roots">';
    (st.roots || []).forEach(function (r, i) {
      h += '<div class="rr"><span class="n">' + esc(r.name || basename(r.path)) + '</span><span class="p" title="' + esc(r.path) + '">' + esc(r.path) + '</span>' +
        '<select data-root-type="' + i + '">' +
        ['models', 'materials', 'both'].map(function (k) { return '<option value="' + k + '"' + (r.type === k ? ' selected' : '') + '>' + esc(t('rt_' + k)) + '</option>'; }).join('') +
        '</select><button class="btn icon" data-root-act="rename" data-i="' + i + '" title="' + esc(t('rename')) + '">✎</button>' +
        '<button class="btn icon" data-root-act="scan" data-i="' + i + '" title="' + esc(t('rescan')) + '">' + icon('refresh') + '</button>' +
        '<button class="btn icon danger" data-root-act="remove" data-i="' + i + '" title="' + esc(t('remove_lib')) + '">' + icon('x') + '</button></div>';
    });
    if (!(st.roots || []).length) h += '<div class="hint">' + esc(t('no_libs')) + '</div>';
    h += '</div><div class="row"><button class="btn pri" data-act="add-root" data-type="models">' + icon('cube') + '<span>' + esc(t('add_models')) + '</span></button>' +
      '<button class="btn pri" data-act="add-root" data-type="materials">' + icon('swatch') + '<span>' + esc(t('add_materials')) + '</span></button>' +
      '<button class="btn" data-act="add-root" data-type="both">' + icon('folder') + '<span>' + esc(t('add_both')) + '</span></button></div></div>';
    h += '<div class="panel"><h3>' + icon('gear') + esc(t('general')) + '</h3>' +
      '<div class="row"><label class="l">' + esc(t('language')) + '</label><div class="seg"><button data-set="language" data-v="fa" class="' + (st.language !== 'en' ? 'on' : '') + '">فارسی</button>' +
      '<button data-set="language" data-v="en" class="' + (st.language === 'en' ? 'on' : '') + '">English</button></div></div>' +
      '<div class="row"><label class="l">' + esc(t('theme')) + '</label><div class="seg"><button data-set="theme" data-v="light" class="' + (st.theme !== 'dark' ? 'on' : '') + '">' + esc(t('light')) + '</button>' +
      '<button data-set="theme" data-v="dark" class="' + (st.theme === 'dark' ? 'on' : '') + '">' + esc(t('dark')) + '</button></div></div>' +
      '<div class="row"><label class="l">' + esc(t('mat_click')) + '</label><select id="set-paint">' +
      ['native', 'banian', 'none'].map(function (k) { return '<option value="' + k + '"' + ((st.paint_tool || 'native') === k ? ' selected' : '') + '>' + esc(t('pt_' + k)) + '</option>'; }).join('') +
      '</select></div>' +
      '<div class="row"><label class="l">' + esc(t('img_width')) + '</label><input class="inp sm" type="number" id="set-imgw" value="' + (st.image_width_cm || 100) + '"> cm</div>' +
      '<div class="row"><label class="chk"><input type="checkbox" id="set-ext"' + (st.show_ext ? ' checked' : '') + '>' + esc(t('show_ext')) + '</label></div>' +
      '<div class="row"><label class="chk"><input type="checkbox" id="set-info"' + (st.show_info ? ' checked' : '') + '>' + esc(t('show_info')) + '</label></div>' +
      '<div class="row"><label class="l">' + esc(t('place_rotate')) + '</label><input class="inp sm" type="number" id="place-rot" value="' + (st.place_rotate || 90) + '"> °</div>' +
      '<div class="row"><button class="btn" data-act="clear-cache">' + esc(t('clear_cache')) + '</button><button class="btn" data-act="reset-window">' + esc(t('reset_window')) + '</button></div></div>';
    h += '<div class="panel"><h3>' + icon('layers') + 'Banian Browser</h3><div class="hint">' +
      esc(t('version')) + ': ' + esc(S.info.version || '') + '<br>SketchUp ' + esc(S.info.su_year || '') + '<br>' +
      esc(t('data_dir')) + ':<br><span style="direction:ltr;display:inline-block;word-break:break-all">' + esc(S.info.data_dir || '') + '</span></div>' +
      '<div class="hint">' + t('shortcuts') + '</div></div>';
    h += '</div>';
    return h;
  }

  // ---------------------------------------------------------------- status bar
  function renderStatus() {
    var p = S.picked;
    var h = '<span class="pk" data-act="goto-tools" title="' + esc(t('picked_material')) + '"><span class="sw" style="' + swatchStyle(p) + '"></span>' +
      '<span>' + esc(p ? p.display : t('nothing_picked_short')) + '</span></span>';
    if (S.replaceArmed) h += '<span class="tag warn">' + esc(t('replace_armed')) + '</span>';
    var scanning = Object.keys(S.scanning).filter(function (k) { return S.scanning[k]; }).length;
    if (scanning) h += '<span class="tag">' + esc(t('scanning')) + '…</span>';
    h += '<span class="grow"></span><span>Banian Browser ' + esc(S.info.version || '') + '</span>';
    $('status').innerHTML = h;
  }

  BB.on('picked', function (p) {
    var prev = S.picked;
    S.picked = p;
    renderStatus();
    if (S.view === 'tools') {
      // same material edited from the panel: refresh the header only, keep the inputs
      if (p && prev && p.name === prev.name && !!p.texture === !!prev.texture && $('pm-sw')) {
        $('pm-sw').setAttribute('style', swatchStyle(p));
        $('pm-nm').textContent = p.display;
        $('pm-sub').innerHTML = pickedSub(p);
      } else {
        var keep = $('content').scrollTop;
        renderContent();
        $('content').scrollTop = keep;
      }
      if (S.texTarget && S.texTarget.mode === 'material') loadTarget();
    }
    // In Model page: only move the "current" mark; the full list is reloaded on demand
    if (S.view === 'inmodel' && p) {
      S.modelMats.forEach(function (m) { m.current = m.name === p.name; });
      var grid = $('content');
      Array.prototype.forEach.call(grid.querySelectorAll('.card.mm'), function (el) {
        var m = S.mmList && S.mmList[+el.getAttribute('data-mm')];
        if (m) el.classList.toggle('cur', m.name === p.name);
      });
    }
  });
  BB.on('index_same', function (d) {
    delete S.scanning[d.root];
    renderTree();
    renderStatus();
  });
  BB.on('index', function (idx) {
    S.indexes[idx.root] = idx;
    delete S.scanning[idx.root];
    rebuild();
    if (S.folder.models && !findNode(S.folder.models)) S.folder.models = null;
    if (S.folder.materials && !findNode(S.folder.materials)) S.folder.materials = null;
    if (hasTree() || S.view === 'favorites' || S.view === 'recent') {
      var keep = $('content').scrollTop;
      renderTree();
      renderPins();
      renderContent();
      $('content').scrollTop = keep;
    }
    renderStatus();
  });
  BB.on('placing', function (on) { S.placing = !!on; });
  BB.on('scanning', function (d) {
    S.scanning[d.root] = true;
    renderTree();
    renderStatus();
  });

  // ---------------------------------------------------------------- item actions
  function itemByCard(card) {
    var i = +card.getAttribute('data-i');
    return S.list[i];
  }

  function useRecent(p) {
    var r = S.settings.recent || [];
    var i = r.indexOf(p);
    if (i >= 0) r.splice(i, 1);
    r.unshift(p);
    S.settings.recent = r;
    var u = S.settings.usage || {};
    u[p] = (u[p] || 0) + 1;
    S.settings.usage = u;
  }

  // webp / gif are not readable by SketchUp: convert them to PNG once, in this dialog.
  function ensureConverted(path) {
    return call('needs_convert', { path: path }).then(function (need) {
      if (!need) return true;
      return call('read_b64', { path: path }).then(function (b64) {
        if (!b64) return false;
        return new Promise(function (resolve) {
          var img = new Image();
          img.onload = function () {
            var c = document.createElement('canvas'); c.width = img.naturalWidth; c.height = img.naturalHeight;
            c.getContext('2d').drawImage(img, 0, 0);
            call('save_converted', { path: path, png: c.toDataURL('image/png').split(',')[1] }).then(function () { resolve(true); });
          };
          img.onerror = function () { toast(t('convert_failed'), true); resolve(false); };
          img.src = 'data:image/' + (extOf(path) === 'gif' ? 'gif' : 'webp') + ';base64,' + b64;
        });
      });
    });
  }
  function withImage(it, fn) {
    if (it.k === 'texture' && /^(webp|gif)$/.test(it.e)) ensureConverted(it.p).then(function (ok) { if (ok) fn(); });
    else fn();
  }

  function activate(it) {
    if (!it) return;
    if (it.k === 'mesh') { call('import_file', { path: it.p }).then(function () { useRecent(it.p); }); return; }
    if (it.k === 'model') {
      if (it.v && it.v > S.info.su) { toast(t('too_new'), true); return; }
      call('place', { path: it.p, mode: S.settings.place_mode || 'normal' }).then(function (ok) { if (ok) useRecent(it.p); });
    } else if (S.replaceArmed) {
      withImage(it, function () { call('mat_replace_with', { path: it.p }).then(function (n) {
        if (n !== null && n !== false) { toast(t('replaced') + (typeof n === 'number' ? ' (' + n + ')' : '')); }
        S.replaceArmed = false;
        renderStatus();
      }); });
    } else {
      withImage(it, function () { call('mat_paint', { path: it.p }).then(function (ok) { if (ok) useRecent(it.p); }); });
    }
  }

  function toggleFav(p, btn) {
    call('fav', { path: p }).then(function (on) {
      var f = S.settings.favorites || [];
      var i = f.indexOf(p);
      if (on && i < 0) f.unshift(p);
      if (!on && i >= 0) f.splice(i, 1);
      S.settings.favorites = f;
      if (btn) btn.classList.toggle('on', !!on);
      if (S.view === 'favorites') renderContent();
    });
  }

  function copyText(txt) {
    var ta = document.createElement('textarea');
    ta.value = txt;
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand('copy'); toast(t('copied')); } catch (e) { /* ignore */ }
    document.body.removeChild(ta);
  }

  function renameItem(it) {
    prompt2(t('rename'), it.n).then(function (name) {
      if (!name || name === it.n) return;
      call('rename', { path: it.p, name: name }).then(function (r) {
        if (r && r.error) toast(r.error, true);
      });
    });
  }

  function deleteItems(paths, label) {
    confirm2(t('delete'), t('confirm_delete') + '\n' + label, true).then(function (ok) {
      if (ok) call('delete', { paths: paths });
    });
  }

  function itemMenu(e, it) {
    var favs = favSet();
    var items = [];
    var common = [
      { sep: true },
      { label: favs[it.p] ? t('unfavorite') : t('favorite'), icon: 'star', action: function () { toggleFav(it.p, null); } },
      { label: t('show_in_folder'), icon: 'folder', action: function () { call('reveal', { path: it.p }); } },
      { label: t('copy_path'), icon: 'save', action: function () { copyText(it.p); } },
      { sep: true },
      { label: t('set_thumb'), icon: 'fit', action: function () { call('set_thumb', { path: it.p }).then(function (u) { if (u) { S.thumbs[it.p] = u; refreshCard(it); } }); } },
      (S.settings.custom_thumbs || {})[it.p] ? { label: t('clear_thumb'), icon: 'x', action: function () { call('clear_thumb', { path: it.p }).then(function (u) { delete S.settings.custom_thumbs[it.p]; S.thumbs[it.p] = u; refreshCard(it); }); } } : null,
      it.k !== 'texture' ? { label: t('gen_thumb'), icon: 'refresh', action: function () { call('gen_thumb', { path: it.p }).then(function (u) { if (u) { S.thumbs[it.p] = u; refreshCard(it); } else toast(t('thumb_failed'), true); }); } } : null,
      { sep: true },
      { label: t('rename'), icon: 'save', action: function () { renameItem(it); } },
      { label: t('delete'), icon: 'x', danger: true, action: function () { deleteItems([it.p], it.n); } }
    ];
    if (it.k === 'mesh') {
      items = [
        { head: it.n + '.' + it.e },
        { label: t('import_preview'), icon: 'cube', action: function () { call('import_file', { path: it.p }); } }
      ];
    } else if (it.k === 'model') {
      items = [
        { head: it.n },
        { label: t('import_simplify'), icon: 'fit', action: function () { call('import_file', { path: it.p }); } },
        { label: t('pm_normal_full'), icon: 'cube', action: function () { call('place', { path: it.p, mode: 'normal' }); } },
        { label: t('pm_fit3_full'), icon: 'fit', action: function () { call('place', { path: it.p, mode: 'fit3' }); } },
        { label: t('pm_fit2_full'), icon: 'fit', action: function () { call('place', { path: it.p, mode: 'fit2' }); } },
        { label: t('pm_surface_full'), icon: 'cube', action: function () { call('place', { path: it.p, mode: 'surface' }); } },
        { sep: true },
        { label: t('replace_sel'), icon: 'refresh', action: function () { call('replace_sel', { path: it.p }); } },
        { label: t('array_path'), icon: 'path', action: function () { call('array_path', { path: it.p }); } },
        { label: t('sweep_path'), icon: 'path', action: function () { call('sweep', { path: it.p }); } },
        { sep: true },
        { label: t('open'), icon: 'folder', action: function () { call('open', { path: it.p }); } },
        { label: t('open_new'), icon: 'folder', action: function () { call('open_new', { path: it.p }); } }
      ];
    } else {
      items = [
        { head: it.n },
        { label: t('paint'), icon: 'bucket', action: function () { withImage(it, function () { call('mat_paint', { path: it.p }); }); } },
        { label: t('apply_sel'), icon: 'bucket', action: function () { withImage(it, function () { call('mat_apply', { path: it.p }); }); } },
        { label: t('add_to_model'), icon: 'plus', action: function () { withImage(it, function () { call('mat_add', { path: it.p }).then(function (ok) { if (ok) toast(t('added')); }); }); } },
        { label: t('replace_picked'), icon: 'refresh', disabled: !S.picked, action: function () {
          withImage(it, function () { call('mat_replace_with', { path: it.p }).then(function (n) { if (n !== null && n !== false) toast(t('replaced')); }); });
        } },
        { label: t('replace_tex_tool'), icon: 'bucket', action: function () {
          withImage(it, function () { call('mat_add', { path: it.p }).then(function (ok) { if (ok) call('replace_tex_tool'); }); });
        } }
      ];
    }
    showMenu(e, items.concat(common));
  }

  function refreshCard(it) {
    var el = S.cardEls[it.p];
    if (el) {
      var th = el.querySelector('.th');
      th.innerHTML = '';
      setCardThumb(el, it);
    }
  }

  function folderMenu(e, p) {
    var root = rootOf(p);
    var isRoot = root && root.path === p;
    var items = [
      { head: isRoot ? (root.name || basename(p)) : basename(p) },
      { label: t('new_folder'), icon: 'folder-plus', action: function () { mkdirIn(p); } },
      { label: t('add_files'), icon: 'plus', action: function () { call('add_files', { dest: p }); } },
      { label: t('show_in_folder'), icon: 'folder', action: function () { call('reveal', { path: p }); } },
      { label: t('rescan'), icon: 'refresh', action: function () { if (root) call('scan', { root: root.path }); } },
      { label: isPinned(p) ? t('unpin') : t('pin'), icon: 'pin', action: function () { togglePin(p); } },
      { sep: true }
    ];
    if (S.view === 'models') items.push({ label: t('save_sel_here'), icon: 'save', action: function () { call('save_sel', { folder: p }); } });
    if (S.view === 'models') items.push({ label: t('save_model_here'), icon: 'save', action: function () { call('save_model', { folder: p }); } });
    if (S.view === 'materials') items.push({ label: t('save_mat_here'), icon: 'save', action: function () { call('model_mat_save', { folder: p }); } });
    if (S.view === 'materials') items.push({ label: t('export_all_here'), icon: 'save', action: function () { call('export_mats', { folder: p }); } });
    if (S.view === 'materials') items.push({ label: t('import_folder_mats'), icon: 'plus', action: function () {
      call('import_mat_folder', { folder: p }).then(function (n) { if (n) toast(t('added') + ' (' + n + ')'); });
    } });
    items.push({ sep: true });
    if (isRoot) {
      items.push({ label: t('rename_lib'), icon: 'save', action: function () {
        prompt2(t('rename_lib'), root.name).then(function (n) { if (n) call('set_root', { root: root.path, name: n }).then(updateRoots); });
      } });
      items.push({ label: t('remove_lib'), icon: 'x', danger: true, action: function () { removeRoot(root); } });
    } else {
      items.push({ label: t('rename'), icon: 'save', action: function () {
        prompt2(t('rename'), basename(p)).then(function (n) { if (n && n !== basename(p)) call('rename', { path: p, name: n }); });
      } });
      items.push({ label: t('delete'), icon: 'x', danger: true, action: function () { deleteItems([p], basename(p)); } });
    }
    showMenu(e, items);
  }

  function mkdirIn(p) {
    prompt2(t('new_folder'), t('new_folder_name')).then(function (n) {
      if (!n) return;
      S.expanded[p] = true;
      call('mkdir', { parent: p, name: n }).then(function (r) { if (r && r.error) toast(r.error, true); });
    });
  }

  function updateRoots(roots) {
    if (!roots) return;
    S.settings.roots = roots;
    rebuild();
    renderAll();
  }

  function removeRoot(root) {
    confirm2(t('remove_lib'), t('remove_lib_confirm') + '\n' + root.path, true).then(function (ok) {
      if (!ok) return;
      call('remove_root', { root: root.path }).then(function (roots) {
        delete S.indexes[root.path];
        updateRoots(roots);
      });
    });
  }

  function addRoot(type) {
    call('add_root', { type: type || 'both' }).then(function (roots) {
      if (roots) { updateRoots(roots); toast(t('lib_added')); }
    });
  }

  function modelMatMenu(e, m) {
    var items = [
      { head: m.display },
      { label: t('mm_select'), icon: 'dropper', action: function () { call('model_mat_select', { name: m.name }); } },
      { label: t('mm_replace_picked'), icon: 'refresh', disabled: !S.picked || S.picked.name === m.name, action: function () {
        call('model_mat_replace', { src: S.picked.name, dst: m.name }).then(function (n) { if (n !== null && n !== false) { toast(t('replaced')); loadModelMats(); } });
      } },
      { label: t('mm_apply_sel'), icon: 'bucket', action: function () {
        call('model_mat_select', { name: m.name }).then(function () { call('apply_sel'); });
      } },
      { label: t('save_to_lib'), icon: 'save', action: function () { call('model_mat_save', { name: m.name }); } },
      { sep: true },
      { label: t('delete'), icon: 'x', danger: true, action: function () {
        confirm2(t('delete'), m.display, true).then(function (ok) { if (ok) call('model_mat_delete', { name: m.name }).then(loadModelMats); });
      } }
    ];
    showMenu(e, items);
  }

  // ---------------------------------------------------------------- events
  function bind() {
    document.addEventListener('click', function (e) {
      if (!e.target.closest('#ctx')) hideMenu();
    });
    window.addEventListener('blur', hideMenu);
    document.addEventListener('contextmenu', function (e) {
      if (!e.target.closest('input, textarea')) e.preventDefault();
    });
    document.addEventListener('keydown', function (e) {
      if ((e.ctrlKey || e.metaKey) && e.keyCode === 70) {
        var q = $('q');
        if (q) { e.preventDefault(); q.focus(); q.select(); }
      }
      // a library model is following the cursor in SketchUp but this window still has
      // the keyboard: send the arrows (and Esc) to the placing tool
      if (S.placing && !e.target.closest('input, textarea, select')) {
        if (e.keyCode === 38 || e.keyCode === 39) { e.preventDefault(); call('place_turn', { dir: 1 }); return; }
        if (e.keyCode === 40 || e.keyCode === 37) { e.preventDefault(); call('place_turn', { dir: -1 }); return; }
        if (e.keyCode === 27) { call('place_cancel'); }
      }
      if (e.keyCode === 27) {
        hideMenu();
        if (S.replaceArmed) { S.replaceArmed = false; renderStatus(); }
      }
    });

    $('rail').addEventListener('click', function (e) {
      var b = e.target.closest('button[data-v]');
      if (b) setView(b.getAttribute('data-v'));
    });

    // tree
    var tree = $('tree');
    tree.addEventListener('click', function (e) {
      var n = e.target.closest('.node');
      if (!n) return;
      var p = n.getAttribute('data-p');
      if (e.target.closest('[data-t]') && p) {
        var node = findNode(p);
        var open = S.expanded[p] !== undefined ? S.expanded[p] : !!(node && node.root);
        S.expanded[p] = !open;
        store('expanded', S.expanded);
        renderTree();
        return;
      }
      selectFolder(p);
      if (window.innerWidth <= 640) { S.sideOpen = false; $('side').className = 'collapsed'; }
    });
    tree.addEventListener('dblclick', function (e) {
      var n = e.target.closest('.node');
      if (!n) return;
      var p = n.getAttribute('data-p');
      if (!p) return;
      S.expanded[p] = !S.expanded[p];
      renderTree();
    });
    tree.addEventListener('contextmenu', function (e) {
      var n = e.target.closest('.node');
      if (!n || !n.getAttribute('data-p')) return;
      folderMenu(e, n.getAttribute('data-p'));
    });
    tree.addEventListener('dragover', function (e) {
      var n = e.target.closest('.node');
      if (!n || !n.getAttribute('data-p')) return;
      e.preventDefault();
      Array.prototype.forEach.call(tree.querySelectorAll('.drop'), function (x) { if (x !== n) x.classList.remove('drop'); });
      n.classList.add('drop');
    });
    tree.addEventListener('dragleave', function (e) {
      var n = e.target.closest('.node');
      if (n) n.classList.remove('drop');
    });
    tree.addEventListener('drop', function (e) {
      var n = e.target.closest('.node');
      if (!n) return;
      e.preventDefault();
      n.classList.remove('drop');
      var dest = n.getAttribute('data-p');
      var src = e.dataTransfer.getData('text/plain');
      if (dest && src && dirname(src) !== dest) {
        call('move', { paths: [src], dest: dest }).then(function (r) { if (r && r.moved && r.moved.length) toast(t('moved')); });
      }
    });

    // side head / crumbs / topbar / content: generic data-act buttons
    document.addEventListener('click', function (e) {
      var a = e.target.closest('[data-act]');
      if (!a) return;
      var act = a.getAttribute('data-act');
      if (act === 'fav') return; // handled in content
      runAct(act, a, e);
    });

    $('pins').addEventListener('click', function (e) {
      var b = e.target.closest('[data-pin]');
      if (!b) return;
      var p = b.getAttribute('data-pin');
      if (!findNode(p)) { toast(t('missing'), true); return; }
      openFolder(p);
    });
    $('pins').addEventListener('contextmenu', function (e) {
      var b = e.target.closest('[data-pin]');
      if (b) pinMenu(e, b.getAttribute('data-pin'));
    });

    $('crumbs').addEventListener('click', function (e) {
      var c = e.target.closest('.cr');
      if (c) selectFolder(c.getAttribute('data-p'));
    });

    $('topbar').addEventListener('input', function (e) {
      if (e.target.id === 'q') {
        S.search = e.target.value;
        var clr = $('topbar').querySelector('.clr');
        if (clr) clr.classList.toggle('hidden', !S.search);
        clearTimeout(S.searchTimer);
        S.searchTimer = setTimeout(renderContent, 120);
      }
      if (e.target.id === 'csize') {
        S.settings.card_size = +e.target.value;
        clearTimeout(S.sizeTimer);
        S.sizeTimer = setTimeout(function () {
          renderContent();
          saveSettings({ card_size: S.settings.card_size });
        }, 60);
      }
    });
    $('topbar').addEventListener('change', function (e) {
      if (e.target.id === 'sort') { saveSettings({ sort: e.target.value }); renderContent(); }
    });
    $('topbar').addEventListener('click', function (e) {
      var pm = e.target.closest('[data-pm]');
      if (pm) { saveSettings({ place_mode: pm.getAttribute('data-pm') }); renderTopbar(); return; }
      var mf = e.target.closest('[data-mf]');
      if (mf) { S.matFilter = mf.getAttribute('data-mf'); renderTopbar(); renderContent(); }
    });

    var content = $('content');
    content.addEventListener('scroll', function () {
      if (S.rendered < S.list.length && content.scrollTop + content.clientHeight > content.scrollHeight - 600) renderMore();
    });
    content.addEventListener('click', function (e) {
      var fav = e.target.closest('[data-act="fav"]');
      var card = e.target.closest('.card');
      if (fav && card) { e.stopPropagation(); toggleFav(card.getAttribute('data-p'), fav); return; }
      if (card && card.hasAttribute('data-mm')) {
        var m = S.mmList[+card.getAttribute('data-mm')];
        if (S.replaceArmed && S.picked && S.picked.name !== m.name) {
          call('model_mat_replace', { src: S.picked.name, dst: m.name }).then(function (n) {
            S.replaceArmed = false; renderStatus();
            if (n !== null && n !== false) { toast(t('replaced')); loadModelMats(); }
          });
        } else {
          call('model_mat_select', { name: m.name });
        }
        return;
      }
      if (card && card.hasAttribute('data-dir')) { openFolder(card.getAttribute('data-dir')); return; }
      if (card && card.hasAttribute('data-i')) activate(itemByCard(card));
      onToolsClick(e);
      onSettingsClick(e);
    });
    content.addEventListener('contextmenu', function (e) {
      var card = e.target.closest('.card');
      if (!card) return;
      if (card.hasAttribute('data-mm')) { modelMatMenu(e, S.mmList[+card.getAttribute('data-mm')]); return; }
      if (card.hasAttribute('data-dir')) { folderMenu(e, card.getAttribute('data-dir')); return; }
      var it = itemByCard(card);
      if (it) itemMenu(e, it);
    });
    content.addEventListener('dragstart', function (e) {
      var card = e.target.closest('.card[data-p]');
      if (card) e.dataTransfer.setData('text/plain', card.getAttribute('data-p'));
    });
    // drop a card on a folder card to move it there
    content.addEventListener('dragover', function (e) {
      var f = e.target.closest('.card.folder');
      if (!f) return;
      e.preventDefault();
      f.classList.add('drop');
    });
    content.addEventListener('dragleave', function (e) {
      var f = e.target.closest('.card.folder');
      if (f) f.classList.remove('drop');
    });
    content.addEventListener('drop', function (e) {
      var f = e.target.closest('.card.folder');
      if (!f) return;
      e.preventDefault();
      f.classList.remove('drop');
      var dest = f.getAttribute('data-dir'), src = e.dataTransfer.getData('text/plain');
      if (dest && src && dirname(src) !== dest) {
        call('move', { paths: [src], dest: dest }).then(function (r) { if (r && r.moved && r.moved.length) toast(t('moved')); });
      }
    });
    content.addEventListener('change', onFormChange);
    content.addEventListener('input', function (e) {
      if (e.target.id === 'pm-alpha') { var v = $('pm-alpha-v'); if (v) v.textContent = e.target.value + '%'; livePicked('alpha', 250); }
      if (e.target.id === 'pm-color') livePicked('color', 250);
      if (e.target.id === 'pm-w' && $('pm-lock') && $('pm-lock').checked && S.picked && S.picked.width) {
        $('pm-h').value = (+e.target.value * S.picked.height / S.picked.width).toFixed(2);
      }
      if (e.target.id === 'pm-h' && $('pm-lock') && $('pm-lock').checked && S.picked && S.picked.height) {
        $('pm-w').value = (+e.target.value * S.picked.width / S.picked.height).toFixed(2);
      }
    });
  }

  function runAct(act, el) {
    switch (act) {
      case 'add-root': addRoot(el.getAttribute('data-type') || (S.view === 'materials' ? 'materials' : (S.view === 'models' ? 'models' : 'both'))); break;
      case 'rescan':
        S.roots.forEach(function (r) { S.scanning[r.path] = true; });
        call('indexes', { rescan: true, full: true });
        renderTree(); renderStatus();
        break;
      case 'toggle-side':
        S.sideOpen = !S.sideOpen;
        $('side').className = S.sideOpen ? '' : 'collapsed';
        break;
      case 'clear-search':
        S.search = '';
        renderTopbar(); renderContent();
        break;
      case 'folder-view':
        saveSettings({ folder_view: S.settings.folder_view === 'flat' ? 'folders' : 'flat' });
        renderTopbar(); renderContent();
        break;
      case 'mkdir': if (S.folder[S.view]) mkdirIn(S.folder[S.view]); break;
      case 'save-sel-here': call('save_sel', { folder: S.folder.models }); break;
      case 'save-mat-here': call('model_mat_save', { folder: S.folder.materials }); break;
      case 'mm-refresh': loadModelMats(); break;
      case 'mm-purge': call('purge_mats').then(function (n) { if (n !== null) toast(t('purged') + ' (' + n + ')'); loadModelMats(); }); break;
      case 'goto-tools': setView('tools'); break;
      case 'pick': call('pick_tool'); break;
      case 'bucket': call('bucket_tool'); break;
      case 'native-paint': call('native_paint'); break;
      case 'apply-sel': call('apply_sel'); break;
      case 'arm-replace':
        if (!S.picked) { toast(t('nothing_picked'), true); return; }
        S.replaceArmed = !S.replaceArmed;
        if (S.replaceArmed) toast(t('replace_armed_tip'));
        renderStatus(); if (S.view === 'tools') renderContent();
        break;
      case 'save-mat': call('model_mat_save', {}); break;
      case 'export-mats': call('export_mats', {}).then(function (n) { if (n) toast(t('exported') + ' (' + n + ')'); }); break;
      case 'collect-tex': call('collect_tex', {}).then(function (n) { if (n) toast(t('exported') + ' (' + n + ')'); }); break;
      case 'tex-rot-custom': texOp('rotate', +($('tex-ang').value || 0)); break;
      case 'tex-scale-custom': texOp('scale', +($('tex-scale').value || 1)); break;
      case 'clear-cache': call('clear_thumb_cache').then(function () { S.thumbs = {}; S.requested = {}; toast(t('done')); }); break;
      case 'reset-window': call('reset_window'); break;
      case 'import-browse': call('import_browse'); break;
      case 'simplify-sel': call('simplify_sel'); break;
      case 'pin-here': if (S.folder[S.view]) togglePin(S.folder[S.view]); break;
      case 'toggle-info':
        saveSettings({ show_info: !S.settings.show_info });
        renderTopbar(); renderContent();
        break;
      case 'replace-tex': call('replace_tex_tool'); break;
      case 'import-mat-folder':
        call('import_mat_folder', { folder: S.view === 'materials' ? S.folder.materials : null }).then(function (n) { if (n) toast(t('added') + ' (' + n + ')'); });
        break;
      case 'import-mat-file':
        call('import_mat_file').then(function (r) {
          if (r && r.convert) ensureConverted(r.convert).then(function (ok) { if (ok) call('mat_paint', { path: r.convert }); });
          if (S.view === 'inmodel') loadModelMats();
        });
        break;
    }
  }

  function texOp(op, value, extra) {
    var args = { op: op, value: value };
    if (extra) Object.keys(extra).forEach(function (k) { args[k] = extra[k]; });
    call('tex', args).then(function (n) { if (typeof n === 'number' && n > 0) toast(t('tex_done') + ' (' + n + ')'); });
  }

  function onToolsClick(e) {
    if (S.view !== 'tools') return;
    var b = e.target.closest('[data-tex]');
    if (b) { texOp(b.getAttribute('data-tex'), b.getAttribute('data-v')); return; }
    var n = e.target.closest('[data-nudge]');
    if (n) {
      var step = +($('tex-step').value || 0.1);
      var d = n.getAttribute('data-nudge').split(',');
      texOp('nudge', null, { du: +d[0] * step, dv: +d[1] * step });
      return;
    }
    var tl = e.target.closest('[data-tool]');
    if (tl) {
      call('tool', { name: tl.getAttribute('data-tool') }).then(function (ok) { if (ok === false) toast(t('place_first'), true); });
    }
  }

  // The picked-material editor applies every change right away (no Apply button).
  var liveTimer = null, livePending = {};
  function livePicked(what, delay) {
    livePending[what] = true;
    clearTimeout(liveTimer);
    liveTimer = setTimeout(flushPicked, delay || 0);
  }
  function flushPicked() {
    var p = S.picked;
    var what = livePending;
    livePending = {};
    if (!p || !$('pm-name')) return;
    var props = {};
    if (what.name) {
      var name = $('pm-name').value.trim();
      if (name && name !== p.display) props.name = name;
    }
    if (what.size && $('pm-w')) {
      var w = +$('pm-w').value, h = +$('pm-h').value;
      if (w > 0 && h > 0 && (Math.abs(w - p.width) > 0.001 || Math.abs(h - p.height) > 0.001)) { props.width = w; props.height = h; }
    }
    if (what.alpha) {
      var a = +$('pm-alpha').value / 100;
      if (Math.abs(a - (p.alpha == null ? 1 : p.alpha)) > 0.004) props.alpha = a;
    }
    if (what.color) {
      var c = $('pm-color').value;
      if (c && c.toLowerCase() !== (p.color || '').toLowerCase()) props.color = c;
    }
    if (!Object.keys(props).length) return;
    call('mat_props', { name: p.name, props: props });
  }

  function onSettingsClick(e) {
    if (S.view !== 'settings') return;
    var s = e.target.closest('[data-set]');
    if (s) {
      var v = {};
      v[s.getAttribute('data-set')] = s.getAttribute('data-v');
      saveSettings(v).then(function () { renderAll(); });
      return;
    }
    var r = e.target.closest('[data-root-act]');
    if (r) {
      var root = S.settings.roots[+r.getAttribute('data-i')];
      var act = r.getAttribute('data-root-act');
      if (act === 'remove') removeRoot(root);
      if (act === 'scan') { S.scanning[root.path] = true; call('scan', { root: root.path }); renderStatus(); }
      if (act === 'rename') prompt2(t('rename_lib'), root.name).then(function (n) { if (n) call('set_root', { root: root.path, name: n }).then(updateRoots); });
    }
  }

  function onFormChange(e) {
    var id = e.target.id;
    var rt = e.target.getAttribute('data-root-type');
    if (rt !== null) {
      var root = S.settings.roots[+rt];
      call('set_root', { root: root.path, type: e.target.value }).then(updateRoots);
      return;
    }
    if (id === 'set-paint') saveSettings({ paint_tool: e.target.value });
    if (id === 'set-imgw') saveSettings({ image_width_cm: +e.target.value || 100 });
    if (id === 'set-ext') { saveSettings({ show_ext: e.target.checked }); }
    if (id === 'set-info') { saveSettings({ show_info: e.target.checked }); }
    if (id === 'place-rot') saveSettings({ place_rotate: Math.max(1, Math.min(360, +e.target.value || 90)) });
    if (id === 'rot-step') saveSettings({ rotate_step: +e.target.value || 45 });
    if (id === 'pm-name') livePicked('name');
    if (id === 'pm-w' || id === 'pm-h') livePicked('size');
    if (id === 'pm-color') livePicked('color');
    if (id === 'pm-alpha') livePicked('alpha');
    if (id === 'tex-groups') saveSettings({ tex_include_groups: e.target.checked });
    if (id === 'tex-step') saveSettings({ tex_nudge: +e.target.value || 0.1 });
  }

  // ---------------------------------------------------------------- start
  function start() {
    S.expanded = load('expanded', {});
    S.sideOpen = window.innerWidth > 640;
    var f = load('folder', null);
    if (f) S.folder = f;
    bind();
    call('init').then(function (info) {
      if (!info) return;
      S.info = info;
      S.settings = info.settings || {};
      S.picked = info.picked;
      S.view = load('view', 'models');
      rebuild();
      renderAll();
      call('page', { page: S.view });
      // show the cached library at once; check the folders for changes a little later,
      // in the background (only changed folders are read again)
      return call('indexes').then(function (list) {
        (list || []).forEach(function (idx) { if (!idx.pending) S.indexes[idx.root] = idx; });
        var missing = (S.settings.roots || []).filter(function (r) { return !S.indexes[r.path]; });
        rebuild();
        renderAll();
        if (S.view === 'inmodel') loadModelMats();
        setTimeout(function () {
          (S.settings.roots || []).forEach(function (r) { S.scanning[r.path] = true; });
          call('indexes', { rescan: true });
          renderTree(); renderStatus();
        }, missing.length ? 50 : 2500);
      });
    });
  }

  BB.start = start;
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
