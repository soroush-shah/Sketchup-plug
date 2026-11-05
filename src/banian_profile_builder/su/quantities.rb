# encoding: UTF-8
# Banian Profile Builder - instant quantity report.
#
# Quantities are computed once when an object is built and cached in its
# attributes, so the report never touches geometry. Occurrences are counted
# through the definition tree (an object inside a component placed 10 times
# counts 10 times) without walking raw faces/edges.

require 'json'

module BanianStudio
  module ProfileBuilder
    module Quantities
      PRICE_DICT = 'banian_pb_prices'.freeze

      module_function

      def pb_groups(model)
        list = []
        model.definitions.each do |d|
          next unless d.group?
          d.instances.each { |g| list << g if Builder.pb?(g) }
        end
        list
      end

      def occurrences(parent, memo)
        return 1 if parent.is_a?(Sketchup::Model)
        return 0 unless parent.is_a?(Sketchup::ComponentDefinition)
        return memo[parent] if memo.key?(parent)
        memo[parent] = 0 # guards against cycles
        memo[parent] = parent.instances.inject(0) { |s, i| s + occurrences(i.parent, memo) }
      end

      def key_for(e)
        [e['profile'], e['size'], e['name'], e['material']].join('|')
      end

      def report(model)
        memo = {}
        rows = {}
        pb_groups(model).each do |g|
          occ = occurrences(g.parent, memo)
          next if occ == 0
          qty = begin
            JSON.parse(g.get_attribute(Builder::DICT, 'qty', '[]'))
          rescue JSON::ParserError
            []
          end
          qty.each do |e|
            k = key_for(e)
            r = (rows[k] ||= e.merge('key' => k, 'count' => 0, 'length_mm' => 0.0, 'volume_mm3' => 0.0, 'objects' => 0))
            r['count'] += e['count'].to_i * occ
            r['length_mm'] += e['length_mm'].to_f * occ
            r['volume_mm3'] += e['volume_mm3'].to_f * occ
            r['objects'] += occ
          end
        end
        dict = model.attribute_dictionary(PRICE_DICT)
        list = rows.values.sort_by { |r| [r['profile'].to_s, r['size'].to_s, r['name'].to_s] }
        list.each { |r| r['price'] = dict ? dict[r['key']].to_f : 0.0 }
        list
      end

      def set_price(model, key, price)
        model.set_attribute(PRICE_DICT, key, price.to_f)
      end

      # Selects every object (in the current context) that contributes to key.
      def select_key(model, key)
        sel = model.selection
        sel.clear
        model.active_entities.each do |e|
          next unless Builder.pb?(e)
          qty = JSON.parse(e.get_attribute(Builder::DICT, 'qty', '[]')) rescue []
          sel.add(e) if qty.any? { |q| key_for(q) == key }
        end
      end

      def to_csv(rows, headers)
        lines = [headers.map { |h| csv_cell(h) }.join(',')]
        rows.each { |r| lines << r.map { |c| csv_cell(c) }.join(',') }
        "﻿" + lines.join("\r\n") + "\r\n"
      end

      def csv_cell(v)
        s = v.to_s
        s =~ /[",\r\n]/ ? '"' + s.gsub('"', '""') + '"' : s
      end
    end
  end
end
