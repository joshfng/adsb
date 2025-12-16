# frozen_string_literal: true

# Compatibility layer providing Curses-like API using ncursesw
# This allows our TUI code to use familiar Curses syntax while using the working ncursesw gem

require "ncursesw"

module Curses
  # Constants
  A_NORMAL = Ncurses::A_NORMAL
  A_BOLD = Ncurses::A_BOLD
  A_REVERSE = Ncurses::A_REVERSE
  A_UNDERLINE = Ncurses::A_UNDERLINE
  A_BLINK = Ncurses::A_BLINK
  A_DIM = Ncurses::A_DIM

  COLOR_BLACK = Ncurses::COLOR_BLACK
  COLOR_RED = Ncurses::COLOR_RED
  COLOR_GREEN = Ncurses::COLOR_GREEN
  COLOR_YELLOW = Ncurses::COLOR_YELLOW
  COLOR_BLUE = Ncurses::COLOR_BLUE
  COLOR_MAGENTA = Ncurses::COLOR_MAGENTA
  COLOR_CYAN = Ncurses::COLOR_CYAN
  COLOR_WHITE = Ncurses::COLOR_WHITE

  # Key constants - note: END is a reserved keyword, use KEY_END instead
  module Key
    DOWN = Ncurses::KEY_DOWN
    UP = Ncurses::KEY_UP
    LEFT = Ncurses::KEY_LEFT
    RIGHT = Ncurses::KEY_RIGHT
    NPAGE = Ncurses::KEY_NPAGE
    PPAGE = Ncurses::KEY_PPAGE
    HOME = Ncurses::KEY_HOME
    # END is reserved, use this directly: Ncurses::KEY_END
    ENTER = Ncurses::KEY_ENTER
    BACKSPACE = Ncurses::KEY_BACKSPACE
    DC = Ncurses::KEY_DC
  end

  # Make KEY_END accessible
  KEY_END = Ncurses::KEY_END

  class << self
    attr_accessor :stdscr_window

    def init_screen
      @stdscr = Ncurses.initscr
      @stdscr_window = Window.new(nil, @stdscr)
      @stdscr_window
    end

    def close_screen
      Ncurses.endwin
    end

    def start_color
      Ncurses.start_color
    end

    def has_colors?
      Ncurses.has_colors?
    end

    def use_default_colors
      Ncurses.use_default_colors
    end

    def init_pair(pair, fg, bg)
      Ncurses.init_pair(pair, fg, bg)
    end

    def color_pair(pair)
      Ncurses.COLOR_PAIR(pair)
    end

    def cbreak
      Ncurses.cbreak
    end

    def noecho
      Ncurses.noecho
    end

    def curs_set(visibility)
      Ncurses.curs_set(visibility)
    end

    def timeout=(ms)
      Ncurses.timeout(ms)
    end

    def getch
      ch = Ncurses.getch
      return nil if ch == Ncurses::ERR

      # Convert printable ASCII to string (like original curses gem)
      # Special keys (arrows, function keys, etc.) remain as integers
      if ch >= 32 && ch < 127
        ch.chr
      else
        ch
      end
    end

    def lines
      Ncurses.LINES
    end

    def cols
      Ncurses.COLS
    end

    def doupdate
      Ncurses.doupdate
    end

    def stdscr
      @stdscr_window
    end

    def colors
      Ncurses.COLORS rescue 8
    end
  end

  # Window class wrapper
  class Window
    attr_reader :win

    def initialize(height_or_nil, width_or_win = nil, top = nil, left = nil)
      if width_or_win.is_a?(Ncurses::WINDOW)
        # Wrapping existing window (for stdscr)
        @win = width_or_win
      else
        # Creating new window
        height = height_or_nil
        width = width_or_win
        @win = Ncurses::WINDOW.new(height, width, top, left)
      end
    end

    def keypad(enable)
      Ncurses.keypad(@win, enable)
    end

    def setpos(row, col)
      Ncurses.wmove(@win, row, col)
    end

    def addstr(str)
      Ncurses.waddstr(@win, str.to_s)
    end

    def attron(attrs)
      Ncurses.wattron(@win, attrs)
    end

    def attroff(attrs)
      Ncurses.wattroff(@win, attrs)
    end

    def clear
      Ncurses.wclear(@win)
    end

    def refresh
      Ncurses.wrefresh(@win)
    end

    def noutrefresh
      Ncurses.wnoutrefresh(@win)
    end

    def box(vert, horiz)
      if vert.is_a?(String) && horiz.is_a?(String)
        Ncurses.box(@win, vert.ord, horiz.ord)
      else
        Ncurses.box(@win, vert, horiz)
      end
    end

    def resize(height, width)
      Ncurses.wresize(@win, height, width)
    end

    def move(top, left)
      Ncurses.mvwin(@win, top, left)
    end

    def close
      Ncurses.delwin(@win)
    end

    def getch
      ch = Ncurses.wgetch(@win)
      return nil if ch == Ncurses::ERR

      # Convert printable ASCII to string (like original curses gem)
      if ch >= 32 && ch < 127
        ch.chr
      else
        ch
      end
    end
  end
end
