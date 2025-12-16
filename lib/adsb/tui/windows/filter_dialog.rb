# frozen_string_literal: true

require_relative 'base_window'

module ADSB
  module TUI
    module Windows
      # Modal filter configuration dialog
      class FilterDialog < BaseWindow
        ITEMS = [
          { key: :position_only, label: 'Position only', type: :toggle },
          { key: :military_only, label: 'Military only', type: :toggle },
          { key: :police_only, label: 'Police only', type: :toggle },
          { key: :min_altitude, label: 'Min altitude', type: :number, suffix: ' ft' },
          { key: :max_altitude, label: 'Max altitude', type: :number, suffix: ' ft' },
          { key: :clear, label: 'Clear all filters', type: :action }
        ].freeze

        def initialize(filter_engine:)
          width = 35
          height = ITEMS.length + 4
          top = 5
          left = 20

          super(height: height, width: width, top: top, left: left, title: 'Filters', border: true)
          @filter_engine = filter_engine
          @selected_index = 0
          @editing = false
          @edit_value = ''
        end

        def draw
          @window.clear
          draw_border
          draw_title

          start_row, start_col, _, c_width = content_area
          row = start_row

          ITEMS.each_with_index do |item, idx|
            selected = idx == @selected_index
            draw_item(row, start_col, c_width, item, selected)
            row += 1
          end

          # Instructions
          row += 1
          draw_text(row, start_col, 'Enter:Toggle  Esc:Close', Color::Scheme::DIM)
        end

        def handle_key(key)
          if @editing
            handle_edit_key(key)
          else
            handle_nav_key(key)
          end
        end

        private

        def draw_item(row, col, width, item, selected)
          attrs = selected ? Curses::A_REVERSE : 0
          label = item[:label].ljust(18)

          value = case item[:type]
                  when :toggle
                    @filter_engine.send(item[:key]) ? '[X]' : '[ ]'
                  when :number
                    val = @filter_engine.send(item[:key])
                    if @editing && selected
                      "[#{@edit_value}_]"
                    else
                      "#{val}#{item[:suffix]}"
                    end
                  when :action
                    ''
                  end

          @window.setpos(row, col)
          @window.attron(attrs)
          @window.addstr("#{label} #{value}"[0, width - 1])
          @window.attroff(attrs)
        end

        def handle_nav_key(key)
          case key
          when 'j', Curses::Key::DOWN
            @selected_index = (@selected_index + 1) % ITEMS.length
            :update
          when 'k', Curses::Key::UP
            @selected_index = (@selected_index - 1) % ITEMS.length
            :update
          when 10, 13, Curses::Key::ENTER, ' '
            toggle_or_edit_current
          when 27 # Escape
            :close
          when 'q'
            :close
          end
        end

        def handle_edit_key(key)
          case key
          when 27 # Escape
            @editing = false
            :update
          when 10, 13, Curses::Key::ENTER
            apply_edit
            @editing = false
            :update
          when 127, Curses::Key::BACKSPACE
            @edit_value = @edit_value[0...-1]
            :update
          when Integer
            if key >= 48 && key <= 57 # 0-9
              @edit_value += key.chr
              :update
            end
          when String
            if key.match?(/\d/)
              @edit_value += key
              :update
            end
          end
        end

        def toggle_or_edit_current
          item = ITEMS[@selected_index]

          case item[:type]
          when :toggle
            current = @filter_engine.send(item[:key])
            @filter_engine.send("#{item[:key]}=", !current)
            :update
          when :number
            @editing = true
            @edit_value = @filter_engine.send(item[:key]).to_s
            :update
          when :action
            if item[:key] == :clear
              clear_all_filters
              :update
            end
          end
        end

        def apply_edit
          item = ITEMS[@selected_index]
          return unless item[:type] == :number

          value = @edit_value.to_i
          value = 0 if value.negative?
          value = 100_000 if value > 100_000

          @filter_engine.send("#{item[:key]}=", value)
        end

        def clear_all_filters
          @filter_engine.search_text = ''
          @filter_engine.position_only = false
          @filter_engine.military_only = false
          @filter_engine.police_only = false
          @filter_engine.min_altitude = 0
          @filter_engine.max_altitude = 100_000
        end
      end
    end
  end
end
