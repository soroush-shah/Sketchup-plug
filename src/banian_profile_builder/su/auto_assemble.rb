# encoding: UTF-8
# Banian Profile Builder - make an assembly from objects drawn by hand.
#
# Select Banian profiles (rails, handrail, posts...) and your own components
# (balusters, panels...) that you placed next to each other, then run
# "Make Assembly from Selection":
#   * the longest horizontal profile gives the path
#   * other profiles along it become continuous parts (same offset)
#   * vertical profiles become repeated parts (posts) with measured spacing
#   * several copies of one component become a repeated component
#   * a single component becomes a bay that fills each span between posts
# The result is saved in "My assemblies" and replaces the hand-made parts.

require 'json'

module BanianStudio
  module ProfileBuilder
    module Controller
      MSG3 = {
        'en' => {
          'need_run' => 'Select at least one Banian profile that runs along the path (e.g. a handrail), plus the other parts.',
          'made' => 'Assembly created and saved: '
        },
        'fa' => {
          'need_run' => 'حداقل یک پروفایل بانیان که در طول مسیر است (مثلاً دست‌انداز) را همراه با بقیه اجزا انتخاب کنید.',
          'made' => 'اسمبلی ساخته و ذخیره شد: '
        }
      }.freeze

      module_function

      def t3(key)
        (MSG3[lang] || MSG3['en'])[key] || MSG3['en'][key]
      end

      def swap_lr(anchor)
        a = (anchor || 'mc').to_s
        return a unless a.size == 2
        a[0] + { 'l' => 'r', 'r' => 'l' }.fetch(a[1], a[1])
      end

      # Pure part of the conversion (testable): parts are plain hashes in
      # the coordinates of the active context.
      #   runs:  [{spec:, pts:, name:, material:}]  (pts = path points)
      #   posts: [{spec:, center:, zmin:, zmax:}]
      #   comps: [{name:, center:, zmin:, w:, d:, h:, xaxis:}]
      def plan_from_parts(ref_pts, closed, up, runs, posts, comps)
        prep = Sweep.prepare(ref_pts, closed, up)
        t, r, u = Sweep.frames(prep[:points], prep[:closed], prep[:up])[0]
        o = prep[:points][0]
        total = PathOps.length(prep[:points], prep[:closed]) * 25.4
        rel = lambda do |p|
          d = Vec.sub(p, o)
          [Vec.dot(d, r) * 25.4, Vec.dot(d, u) * 25.4, Vec.dot(d, t) * 25.4]
        end
        rows = []
        runs.each do |part|
          spec = JSON.parse(JSON.generate(part[:spec]))
          du, dv, = rel.call(part[:pts][0])
          dir = Vec.norm(Vec.sub(part[:pts][1], part[:pts][0])) || t
          if Vec.dot(dir, t) < 0
            spec['flip'] = !spec['flip']
            spec['anchor'] = swap_lr(spec['anchor'])
            spec['offset_u'] = -(spec['offset_u'] || 0).to_f
          end
          rows << { 'type' => 'layer', 'name' => part[:name].to_s.empty? ? Builder.profile_name(spec) : part[:name],
                    'profile' => spec['profile'], 'params' => spec['params'] || {}, 'custom_loops' => spec['custom_loops'],
                    'anchor' => spec['anchor'] || 'mc', 'rotation' => spec['rotation'] || 0, 'flip' => spec['flip'] ? true : false,
                    'offset_u' => ((spec['offset_u'] || 0).to_f + du).round(1),
                    'offset_v' => ((spec['offset_v'] || 0).to_f + dv).round(1),
                    'material' => part[:material].to_s, 'visible' => true }
        end
        spaced = lambda do |list|
          ss = list.map { |x| x[:s] }.sort
          if ss.size >= 2
            { 'mode' => 'fixed', 'spacing' => ((ss[-1] - ss[0]) / (ss.size - 1)).round(1),
              'setback_start' => [ss[0], 0].max.round(1), 'setback_end' => [total - ss[-1], 0].max.round(1), 'at_corners' => false }
          else
            { 'mode' => 'even', 'spacing' => 1500, 'setback_start' => 0, 'setback_end' => 0, 'at_corners' => true }
          end
        end
        posts.group_by { |p| JSON.generate([p[:spec]['profile'], p[:spec]['params']]) }.each_value do |group|
          list = group.map do |p|
            du, v0, s = rel.call(p[:center])
            bottom = rel.call(Vec.add(p[:center], Vec.mul(u, (p[:zmin] - Vec.dot(p[:center], u)))))[1]
            { s: s, du: du, v0: bottom, len: (p[:zmax] - p[:zmin]) * 25.4, v_center: v0 }
          end
          spec = group[0][:spec]
          rows << { 'type' => 'repeat', 'name' => 'Post', 'profile' => spec['profile'], 'params' => spec['params'] || {},
                    'custom_loops' => spec['custom_loops'], 'anchor' => 'mc', 'rotation' => 0, 'flip' => false,
                    'offset_u' => (list.inject(0.0) { |a, x| a + x[:du] } / list.size).round(1),
                    'v0' => list.map { |x| x[:v0] }.min.round(1), 'length' => list.map { |x| x[:len] }.max.round(1),
                    'jambs' => true, 'material' => spec['material'].to_s, 'visible' => true }.merge(spaced.call(list))
        end
        post_index = rows.index { |rw| rw['type'] == 'repeat' }
        comps.group_by { |c| c[:name] }.each do |name, group|
          list = group.map do |c|
            du, _v, s = rel.call(c[:center])
            v0 = rel.call(Vec.add(c[:center], Vec.mul(u, (c[:zmin] - Vec.dot(c[:center], u)))))[1]
            { s: s, du: du, v0: v0 }
          end
          c = group[0]
          base = { 'name' => name, 'component' => name, 'comp_w' => c[:w], 'comp_d' => c[:d], 'comp_h' => c[:h],
                   'offset_u' => (list.inject(0.0) { |a, x| a + x[:du] } / list.size).round(1),
                   'v0' => list.map { |x| x[:v0] }.min.round(1), 'length' => c[:h], 'scale' => false, 'flip' => false,
                   'material' => '', 'visible' => true }
          if group.size >= 2 || post_index.nil?
            along_x = c[:xaxis] && Vec.dot(c[:xaxis], t).abs > Vec.dot(c[:xaxis], r).abs
            rows << base.merge('type' => 'component', 'rotation' => along_x ? 90 : 0, 'jambs' => false).merge(spaced.call(list))
          else
            rows << base.merge('type' => 'bay', 'bay_ref' => post_index, 'fit' => 'stretch', 'gap' => 0)
          end
        end
        # Put the path at the lowest part (usually the floor) so the saved
        # assembly can be drawn directly on the ground later.
        lows = rows.map { |rw| rw['type'] == 'layer' ? rw['offset_v'].to_f : rw['v0'].to_f }
        low = lows.min || 0.0
        if low.abs > 0.01
          rows.each do |rw|
            key = rw['type'] == 'layer' ? 'offset_v' : 'v0'
            rw[key] = (rw[key].to_f - low).round(1)
          end
          shift = Vec.mul(u, low / 25.4)
          prep = Sweep.prepare(prep[:points].map { |q| Vec.add(q, shift) }, prep[:closed], prep[:up])
        end
        [prep, rows]
      end

      def assembly_from_selection
        model = Sketchup.active_model
        sel = model.selection.to_a
        members = sel.select { |e| Builder.kind(e) == 'member' }
        insts = sel.grep(Sketchup::ComponentInstance)
        runs = []
        posts = []
        members.each do |g|
          info = Builder.read(g)
          next unless info
          pts = info['path'].map { |p| (g.transformation * Geom::Point3d.new(*p)).to_a }
          d = Vec.norm(Vec.sub(pts[-1], pts[0]))
          if pts.size == 2 && d && d[2].abs > 0.95
            bb = g.bounds
            posts << { spec: info['spec'], center: bb.center.to_a, zmin: bb.min.z, zmax: bb.max.z }
          else
            up = info['up'] ? (g.transformation * Geom::Vector3d.new(*info['up'])).to_a : nil
            runs << { spec: info['spec'], pts: pts, closed: info['closed'], up: up, name: g.name,
                      material: info['spec']['material'], len: PathOps.length(pts, info['closed']) }
          end
        end
        if runs.empty?
          UI.messagebox(t3('need_run'))
          return
        end
        ref = runs.max_by { |x| x[:len] }
        comps = insts.map do |i|
          bb = i.bounds
          db = i.definition.bounds
          { name: i.definition.name, center: bb.center.to_a, zmin: bb.min.z,
            w: (db.width * 25.4).round(1), d: (db.height * 25.4).round(1), h: (db.depth * 25.4).round(1),
            xaxis: i.transformation.xaxis.to_a }
        end
        prep, rows = plan_from_parts(ref[:pts], ref[:closed], ref[:up], runs, posts, comps)
        res = UI.inputbox([t('assembly_name')], ['My assembly'], 'Banian Profile Builder')
        return unless res
        name = res[0].to_s.strip
        name = 'My assembly' if name.empty?
        spec = { 'preset' => 'custom', 'name' => name, 'rows' => rows, 'openings' => [], 'flip' => false }
        model.start_operation('Banian Make Assembly', true)
        g = Builder.create(model.active_entities, 'assembly', spec, prep[:points], prep[:closed], prep[:up])
        (members + insts).each { |e| e.erase! if e.valid? }
        model.commit_operation
        id = Library.add_assembly(name, spec)
        spec['preset'] = id
        set_spec('assembly', spec)
        model.selection.clear
        model.selection.add(g) if g
        show
        push_library
        send_js('type' => 'use_spec', 'kind' => 'assembly', 'spec' => spec)
        send_js('type' => 'toast', 'text' => t3('made') + name)
      rescue StandardError => e
        model.abort_operation if model
        report_error(e)
      end
    end
  end
end
