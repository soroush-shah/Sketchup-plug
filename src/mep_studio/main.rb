# frozen_string_literal: true

require 'sketchup'

module MEPStudio
  PLUGIN_DIR = File.dirname(__FILE__) unless defined?(PLUGIN_DIR)

  %w[core/geo core/catalog core/settings core/util
     builders/run_builder builders/equipment
     tools/path_tool tools/place_tool
     commands/layout commands/clash commands/commands].each do |f|
    Sketchup.require(File.join(PLUGIN_DIR, f))
  end

  module_function

  def icon(name)
    small = File.join(PLUGIN_DIR, 'icons', "#{name}_24.png")
    large = File.join(PLUGIN_DIR, 'icons', "#{name}_32.png")
    [small, large]
  end

  def cmd(label, tip, icon_name = nil, &blk)
    c = UI::Command.new(label) do
      blk.call
    rescue StandardError => e
      Util.ui_error(e)
    end
    c.tooltip = label
    c.status_bar_text = tip
    if icon_name
      s, l = icon(icon_name)
      c.small_icon = s
      c.large_icon = l
    end
    c
  end

  def select_tool(tool)
    Sketchup.active_model.select_tool(tool)
  end

  unless file_loaded?(__FILE__)
    c = {}
    c[:duct] = cmd('Draw Duct / داکت', 'Draw a rectangular or round duct along clicked points (Tab = options)', 'duct') { select_tool(PathTool.new('duct')) }
    c[:pipe] = cmd('Draw Pipe / لوله', 'Draw chilled water, hot water, drain, sprinkler or plumbing pipe (Tab = options)', 'pipe') { select_tool(PathTool.new('pipe')) }
    c[:tray] = cmd('Draw Cable Tray / سینی کابل', 'Draw a cable tray along clicked points', 'tray') { select_tool(PathTool.new('tray')) }
    c[:duct_e] = cmd('Duct from Selected Edges / داکت از روی خطوط', 'Convert selected edges (route) to ducts', 'duct_edges') { Commands.runs_from_edges('duct') }
    c[:pipe_e] = cmd('Pipe from Selected Edges / لوله از روی خطوط', 'Convert selected edges (route) to pipes') { Commands.runs_from_edges('pipe') }
    c[:tray_e] = cmd('Tray from Selected Edges / سینی از روی خطوط', 'Convert selected edges to cable trays') { Commands.runs_from_edges('tray') }
    c[:fcu] = cmd('Place Fan Coil / فن کویل', 'Place a fan coil unit (click on ceiling or floor, Tab = model)', 'fcu') { select_tool(PlaceTool.new('fcu')) }
    c[:fcu_new] = cmd('Add Fan Coil Model / افزودن مدل فن کویل', 'Add a custom fan coil model to the catalogue') { Commands.add_fcu_model }
    c[:term] = cmd('Place Diffuser / Grille / دریچه', 'Place supply diffuser or return grille', 'diffuser') { select_tool(PlaceTool.new('terminal')) }
    c[:term_l] = cmd('Diffuser Layout in Face / چیدمان دیفیوزر', 'Grid of diffusers inside selected ceiling face') { Layout.diffusers }
    c[:spr] = cmd('Place Sprinkler Head / هد اسپرینکلر', 'Place a single sprinkler head') { select_tool(PlaceTool.new('sprinkler')) }
    c[:spr_l] = cmd('Sprinkler Layout + Piping / جانمایی اسپرینکلر', 'Auto layout heads, branch lines and main for the selected face(s)', 'sprinkler') { Layout.sprinklers }
    c[:light] = cmd('Place Light / چراغ', 'Place a light fixture') { select_tool(PlaceTool.new('light')) }
    c[:light_l] = cmd('Lighting Layout in Face / چیدمان چراغ', 'Grid of lights inside selected face', 'light') { Layout.lights }
    c[:edit] = cmd('Edit / Resize Selected Runs / ویرایش', 'Change size, system or insulation of selected ducts / pipes', 'edit') { Commands.edit_selected }
    c[:clash] = cmd('Clash Detection / تشخیص تداخل', 'Find hard and soft clashes between MEP and architecture / structure', 'clash') { Clash.run }
    c[:clear] = cmd('Clear Clash Markers / پاک کردن علامت‌ها', 'Remove clash markers') { Util.operation('MEP: clear markers') { Clash.clear_markers } }
    c[:boq] = cmd('Bill of Quantities / متره', 'Lengths, sheet metal area and counts by system and size', 'boq') { Commands.boq }
    c[:settings] = cmd('Settings / Defaults / تنظیمات', 'Default sizes, elevations and models', 'settings') { Commands.settings }
    vis = {
      'all' => 'Show All Disciplines / نمایش همه', 'mech' => 'Mechanical Only / فقط مکانیکال',
      'fire' => 'Fire Protection Only / فقط اطفا', 'plumb' => 'Plumbing Only / فقط آبرسانی', 'elec' => 'Electrical Only / فقط برق'
    }

    menu = UI.menu('Extensions').add_submenu('MEP Studio')
    hv = menu.add_submenu('HVAC / تهویه')
    [:duct, :duct_e, :fcu, :fcu_new, :term, :term_l].each { |k| hv.add_item(c[k]) }
    pm = menu.add_submenu('Piping / لوله‌کشی')
    [:pipe, :pipe_e].each { |k| pm.add_item(c[k]) }
    fp = menu.add_submenu('Fire Protection / اطفای حریق')
    [:spr, :spr_l].each { |k| fp.add_item(c[k]) }
    el = menu.add_submenu('Electrical / برق')
    [:tray, :tray_e, :light, :light_l].each { |k| el.add_item(c[k]) }
    menu.add_separator
    menu.add_item(c[:edit])
    menu.add_item(c[:clash])
    menu.add_item(c[:clear])
    menu.add_item(c[:boq])
    vm = menu.add_submenu('Visibility / نمایش')
    vis.each { |k, label| vm.add_item(cmd(label, label) { Commands.isolate(k) }) }
    menu.add_separator
    menu.add_item(c[:settings])
    menu.add_item(cmd('Help / راهنما', 'Keyboard shortcuts and workflow') do
      UI.messagebox(File.read(File.join(PLUGIN_DIR, 'ui', 'help.txt'), encoding: 'UTF-8'), MB_MULTILINE, 'MEP Studio')
    end)

    tb = UI::Toolbar.new('MEP Studio')
    [:duct, :duct_e, :fcu, :term, :pipe, :spr_l, :tray, :light_l, :edit, :clash, :boq, :settings].each_with_index do |k, i|
      tb.add_separator if [4, 6, 8].include?(i)
      tb.add_item(c[k])
    end
    tb.restore

    # Right-click menu on MEP elements.
    UI.add_context_menu_handler do |cm|
      sel = Sketchup.active_model.selection
      if sel.any? { |e| Clash::RUN_TYPES.include?(Util.mep_type(e)) }
        cm.add_item(c[:edit])
      end
    end

    file_loaded(__FILE__)
  end
end
