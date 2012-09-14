# -*- coding: utf-8 -*-

# RubyGnome2を用いてUIを表示するプラグイン

require "gtk2"
require File.expand_path File.join(File.dirname(__FILE__), 'mikutter_window')

Plugin.create :gtk do
  windows_by_slug = {}                  # slug => Gtk::MikutterWindow
  panes_by_slug = {}                    # slug => Gtk::NoteBook
  tabs_by_slug = {}                     # slug => Gtk::EventBox
  timelines_by_slug = {}                # slug => Gtk::TimeLine

  TABPOS = [Gtk::POS_TOP, Gtk::POS_BOTTOM, Gtk::POS_LEFT, Gtk::POS_RIGHT]

  # ウィンドウ作成。
  # PostBoxとか複数のペインを持つための処理が入るので、Gtk::MikutterWindowクラスを新設してそれを使う
  on_window_created do |i_window|
    notice "create window #{i_window.slug.inspect}"
    window = Gtk::MikutterWindow.new
    windows_by_slug[i_window.slug] = window
    window.title = i_window.name
    window.set_size_request(240, 240)
    geometry = get_window_geometry(i_window.slug)
    window.set_default_size(*geometry[:size])
    window.move(*geometry[:position])
    window.signal_connect("destroy"){
      Delayer.freeze
      window.destroy
      Gtk::Object.main_quit
      # Gtk.main_quit
      false }
    window.show_all
  end

  # ペイン作成。
  # ペインはGtk::NoteBook
  on_pane_created do |i_pane|
    notice "create pane #{i_pane.slug.inspect}"
    pane = Gtk::Notebook.new.set_tab_pos(TABPOS[UserConfig[:tab_position]]).set_tab_border(0).set_group_id(0).set_scrollable(true)
    panes_by_slug[i_pane.slug] = pane
    tab_position_hook_id = UserConfig.connect(:tab_position){ |key, val, before_val, id|
      notice "change tab pos to #{TABPOS[val]}"
      pane.set_tab_pos(TABPOS[val]) }
    pane.signal_connect('page-reordered'){
      # UserConfig[:tab_order] = books_labels
      false }
    pane.signal_connect('page-removed'){
      Delayer.new{
        unless pane.destroyed?
          if pane.children.empty? and pane.parent
            UserConfig.disconnect(tab_position_hook_id)
            pane.parent.remove(pane) end
          # UserConfig[:tab_order] = books_labels
        end }
      false }
    pane.show_all
  end

  # タブ作成。
  # タブには実体が無いので、タブのアイコンのところをGtk::EventBoxにしておいて、それを実体ということにしておく
  on_tab_created do |i_tab|
    notice "create tab #{i_tab.slug.inspect}"
    tab = Gtk::EventBox.new.tooltip(i_tab.name)
    tab.add(Gtk::Label.new(i_tab.name))
    tabs_by_slug[i_tab.slug] = tab
    tab.show_all
  end

  # タイムライン作成。
  # Gtk::TimeLine
  on_timeline_created do |i_timeline|
    notice "create timeline #{i_timeline.slug.inspect}"
    timeline = Gtk::TimeLine.new
    timelines_by_slug[i_timeline.slug] = timeline
    timeline.show_all
  end

  on_gui_pane_join_window do |i_pane, i_window|
    puts "gui_pane_join_window #{i_pane.slug.inspect}, #{i_window.slug.inspect}"
    windows_by_slug[i_window.slug].panes.pack_end(panes_by_slug[i_pane.slug], false).show_all
  end

  on_gui_tab_join_pane do |i_tab, i_pane|
  end

  on_gui_timeline_join_tab do |i_timeline, i_tab|
    pane = panes_by_slug[i_tab.parent.slug]
    timeline = timelines_by_slug[i_timeline.slug]
    index = 0
    pane.insert_page_menu(index, timeline, tabs_by_slug[i_tab.slug])
    pane.set_tab_reorderable(timeline, true).set_tab_detachable(timeline, true)
  end

  on_gui_timeline_add_messages do |i_timeline, messages|
    notice "gui_timeline_add_messages: update :#{i_timeline.slug} #{messages.is_a?(Array) ? messages.size : 1} message(s)."
    timelines_by_slug[i_timeline.slug].add(messages)
  end

  def get_window_geometry(slug)
    geo = at(:windows_geometry, {})
    if geo[slug]
      geo[slug]
    else
      size = [Gdk.screen_width/3, Gdk.screen_height*4/5]
      { size: size,
        position: [Gdk.screen_width - size[0], Gdk.screen_height/2 - size[1]/2] } end end

end

