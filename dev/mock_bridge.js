// Development-only fake SketchUp bridge: lets the UI run in a normal browser.
(function () {
  var roots = [
    { path: 'D:/Library/Objects', type: 'models', name: 'Objects' },
    { path: 'D:/Library/Materials', type: 'materials', name: 'Materials' }
  ];
  var settings = {
    roots: roots, favorites: [], recent: [], usage: {}, custom_thumbs: {}, language: 'fa', theme: 'light',
    card_size: 150, sort: 'name_asc', recursive: true, place_mode: 'normal', paint_tool: 'native',
    image_width_cm: 100, rotate_step: 45, place_rotate: 90, show_info: false,
    pinned: { models: ['D:/Library/Objects/Furniture/Chairs', 'D:/Library/Objects/Plants'], materials: ['D:/Library/Materials/Stone/Marble'] },
    tex_include_groups: true, tex_nudge: 0.1, show_ext: false
  };
  function idx(root, tree) {
    var folders = [], items = [];
    function walk(dir, node) {
      Object.keys(node).forEach(function (k) {
        var v = node[k];
        if (Array.isArray(v)) {
          var p = dir + '/' + k;
          folders.push({ p: p, n: k, d: dir });
          v.forEach(function (n, i) {
            var e = n.split('.').pop();
            items.push({ p: p + '/' + n, n: n.replace(/\.[^.]+$/, ''), e: e, k: e === 'skp' ? 'model' : (e === 'skm' ? 'material' : 'texture'),
              f: p, s: 200000 + i * 91234, m: 1700000000 + i * 86400, v: e === 'skp' ? (i % 7 === 3 ? 27 : 21 + (i % 4)) : undefined });
          });
        } else {
          folders.push({ p: dir + '/' + k, n: k, d: dir });
          walk(dir + '/' + k, v);
        }
      });
    }
    walk(root, tree);
    return { root: root, folders: folders, items: items, exists: true };
  }
  var models = idx('D:/Library/Objects', {
    'Furniture': { 'Sofas': ['Sofa Milano.skp', 'Sofa Oslo.skp', 'Corner Sofa.skp', 'Armchair Luna.skp'],
                   'Tables': ['Dining Table 6p.skp', 'Coffee Table Oak.skp', 'Side Table.skp'],
                   'Chairs': ['Chair Wishbone.skp', 'Bar Stool.skp', 'Office Chair.skp', 'Chair Eames.skp'] },
    'Kitchen': ['Fridge.skp', 'Oven 60.skp', 'Sink Double.skp', 'Hood.skp'],
    'Lighting': ['Pendant Globe.skp', 'Floor Lamp.skp', 'Wall Sconce.skp'],
    'Plants': ['Ficus.skp', 'Monstera.skp', 'Olive Tree.skp', 'Snake Plant.skp', 'Palm.skp'],
    'درها و پنجره‌ها': ['در چوبی.skp', 'پنجره دوجداره.skp']
  });
  var mats = idx('D:/Library/Materials', {
    'Wood': ['Oak Natural.skm', 'Walnut.skm', 'Parquet Herringbone.jpg', 'Ash Light.jpg'],
    'Stone': { 'Marble': ['Calacatta.jpg', 'Nero Marquina.jpg', 'Travertine.skm'], 'Granite': ['Granite Grey.jpg'] },
    'Metal': ['Brushed Steel.skm', 'Brass.skm', 'Copper.jpg'],
    'Fabric': ['Linen Beige.jpg', 'Velvet Green.skm']
  });
  var palette = ['#c8a27a', '#8d6748', '#e8e3da', '#2f3136', '#9aa7a2', '#b8743d', '#6f8f72', '#d9c7a8', '#7b8794', '#c9b28f'];
  function thumb(p, i) {
    var c = palette[i % palette.length];
    var isModel = /\.skp$/.test(p);
    var svg = isModel
      ? '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200"><rect width="200" height="200" fill="#f4f6f5"/><rect x="45" y="80" width="110" height="60" rx="8" fill="' + c + '"/><rect x="45" y="60" width="110" height="28" rx="8" fill="' + c + '" opacity=".75"/><rect x="52" y="140" width="8" height="22" fill="#555"/><rect x="140" y="140" width="8" height="22" fill="#555"/></svg>'
      : '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200"><defs><pattern id="p" width="40" height="40" patternUnits="userSpaceOnUse"><rect width="40" height="40" fill="' + c + '"/><path d="M0 20h40M20 0v40" stroke="#000" stroke-opacity=".12" stroke-width="3"/></pattern></defs><rect width="200" height="200" fill="url(#p)"/></svg>';
    return 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
  }
  var picked = { name: 'Oak Natural', display: 'Oak Natural', color: '#c8a27a', alpha: 1, texture: true, width: 120, height: 60, pixels: [2048, 1024], thumb: thumb('x.skm', 0) };
  var cmds = {
    init: function () { return { settings: settings, version: '1.0.0', su: 26, su_year: 2026, platform: 'win', data_dir: 'C:/Users/me/AppData/Local/BanianBrowser', picked: picked }; },
    page: function () { return true; },
    indexes: function () { setTimeout(function () { BB.emit('index', models); BB.emit('index', mats); }, 300); return [models, mats]; },
    thumbs: function (a) { setTimeout(function () { var o = {}; a.paths.forEach(function (p, i) { o[p] = /Fridge|Hood/.test(p) ? null : thumb(p, p.length + i); }); BB.emit('thumbs', o); }, 80); return true; },
    settings: function (a) { Object.keys(a.values).forEach(function (k) { settings[k] = a.values[k]; }); return settings; },
    fav: function (a) { var i = settings.favorites.indexOf(a.path); if (i >= 0) { settings.favorites.splice(i, 1); return false; } settings.favorites.unshift(a.path); return true; },
    picked: function () { return picked; },
    model_mats: function () { return ['Oak Natural', 'Walnut', 'White Paint', 'Glass', 'Concrete'].map(function (n, i) { return { name: n, display: n, color: palette[i], alpha: n === 'Glass' ? 0.3 : 1, texture: i < 2, width: 100, height: 100, thumb: i < 2 ? thumb('a.skm', i) : null, used: i !== 4, current: i === 0 }; }); },
    tex_target: function () { return { mode: 'material', textured: true, mat: picked }; },
    pin: function (a) { var l = settings.pinned[a.view] = settings.pinned[a.view] || []; var i = l.indexOf(a.path); if (i >= 0) l.splice(i, 1); else l.push(a.path); return settings.pinned; },
    pin_move: function (a) { var l = settings.pinned[a.view] || []; var i = l.indexOf(a.path); var j = Math.max(0, Math.min(l.length - 1, i + a.delta)); l.splice(j, 0, l.splice(i, 1)[0]); return settings.pinned; },
    mat_props: function (a) { window.__props = (window.__props || []).concat([a.props]); Object.keys(a.props).forEach(function (k) { if (k === 'alpha') picked.alpha = a.props.alpha; if (k === 'color') picked.color = a.props.color; }); setTimeout(function () { BB.emit('picked', picked); }, 5); return true; }
  };
  window.sketchup = {
    bb_call: function (json) {
      var m = JSON.parse(json);
      var fn = cmds[m.cmd];
      var data = fn ? fn(m.args || {}) : true;
      setTimeout(function () { BB.reply(m.id, { ok: true, data: data }); }, 10);
    }
  };
})();
