#load "stuff.jai";
using,only(Mouse, compress, decompress, utc_to_time_ago, set_window_pos_to_mouse, send_paste, save_bitmap_to_file, myregisterhotkey, add_to_startup, remove_from_startup, is_set_to_run_on_startup)
  Functions :: #import,file "functions.jai";

APP_NAME      :: "ClipMan";
VERSION       :: "v0.0.4";
CONFIG_PATH   :: "clipman.json";

// default config
// overwitten by config_load
config: struct {
  window_width      : int    = 1200;
  window_height     : int    = 840;
  record_height     : int    = 70;
  record_lines      : int    = 3;
  transparency      : int    = 90;
  streamer_mode     : int    = 0; // for privacy. won't render clips unless you take an extra action. 0 to disable
  on_startup_open   : int    = 1;
  enable_watcher    : int    = 0; // after 5min close process and open the watcher process instead to save ram
  large_text_clips  : int    = 10000; // Delete Large Text Clips will only delete clips at least this large
  hotkey            : string = "alt+`";
  db_name           : string = "clipman.db";
  remember_password : string = "";
}

// these values are calculated based on the config data
// (this actual window_height may not be exactly what config.window_height wanted)
window_width  : int; // defined by config_load
window_height : int; // defined by config_load
max_records   : int; // defined by config_load


visible := true;
hwnd    : HWND;
quit    := false;


ONLY_RENDER_WHEN_CHANGED :: true;
#if ONLY_RENDER_WHEN_CHANGED {
  render_dirty_info: struct {
    new_event: bool;
    hover_index: int; // mousemove is current not an event. so we have to track if the mouse position would actually change anything
  }
}

cmd_arg_spawned_by_watcher := false;
cmd_arg_copy := false;
main :: () {
  cmd_arg_spawned_by_watcher = xx cmd_arg("spawned_by_watcher");
  cmd_arg_copy = xx cmd_arg("copy");

  set_cwd_to_exe_location(); // ensures we read and write files next to the exe, whereever it is

  config_load(); // load the config first

  // create the main window
  hwnd = create_window(
    window_name          = #run interp("%{APP_NAME} %{VERSION}"),
    width                = window_width,
    height               = window_height,
    background_color_rgb = COLORS.to_3f(COLORS.DARK),
    style                = WS_POPUP,
    style_ex             = WS_EX_LAYERED | WS_EX_TOOLWINDOW
  );
  set_window_pos_to_mouse(hwnd);
  show_window(false);
  if config.on_startup_open then show_window(true); // need to call show_window even if it was already visible, to trigger streamer_mode stuff
  if cmd_arg_spawned_by_watcher && !cmd_arg_copy then show_window(true); // showing window twice shouldn't be a problem, right?

  // register our global show hide hotkey
  // todo it would probably be smarter to let them register the hotkey
  // by pressing it instead of typing its string name into config file
  myregisterhotkey(hwnd, 0, config.hotkey);

  // need this to receive clipboard copy events
  AddClipboardFormatListener(hwnd);

  // init Simp rendering stuff
  Simp.set_render_target(hwnd);

  // init everything
  init_everything();

  // create tray icon
  trayicon_create(tooltip=#run interp("%{APP_NAME} %{VERSION}"));

  // this has to happen after init everything
  if cmd_arg_copy then on_copy();

  // main game loop
  while !quit {

    update();

    if visible render(); else sleep_based_on_last_interaction_time();

    maybe_quit_to_watcher();

    tfree();

  }
}

// todo: need a way to edit settings / hotkey / remember password
// ^ this stuff now exists but isn't great. would be nice if i could
// just type out the hotkey instead of having to spell it out in the config file
// todo: ability to resize the window



selected_index        : int;
selected_index_end    : int = -1;
scroll_offset         : int;

records               : [] DbRecord;
total_copy_count      : int;
total_wheel_delta     : int;

is_streamer_mode      : bool;
is_db_locked          : bool;
is_config_parse_error : bool;

order_by := "last_seen_at";

init_everything :: () {

  // init_crash_log();

  init_db();

  records = NewArray(max_records, DbRecord);

  init_search_string();

  update_records();

  init_font();

}

Process :: #import "Process";
maybe_quit_to_watcher :: () {
  if !cmd_arg_spawned_by_watcher && !config.enable_watcher return;
  if visible return;

  ms_since_last_interation := get_ms_since_last_interaction();
  if ms_since_last_interation > 1000*60*5/*5 min*/ {
    UnregisterHotKey(hwnd, 0);
    p: Process.Process;
    success := Process.create_process(*p, "clipman-watcher.exe", kill_process_if_parent_exits = false);
    quit = true;
  }
}

// // redirect stderr to a crash.log file
// // so we can actually know why it crashed in release builds
// // this is annoying because it creates a crash.log even if it never crashed
// // also it keeps the crash.log file open forever
// // also this sucks because the original stderr isn't printed to the console anymore
// init_crash_log :: () {
//   #if !RELEASE return;

//   // create / open the crash.log file so we can get a handle to it
//   crash_log_handle: FILE;
//   fopen_s(*crash_log_handle, "crash.log", "a");
//   SEEK_END :: 2;
//   fseek(crash_log_handle, 0, SEEK_END); // "a" for append isn't working... ? idk, i need fseek to not overwrite the file

//   // rewrite stderr to our crash.log file
//   stderr_fileno :: 2;
//   dup2success := _dup2(_fileno(crash_log_handle), stderr_fileno);
//   if dup2success != 0 {
//     mylog("crash.log failed to initialize ...");
//     return;
//   }

//   mylog("*** Program Started Running at: UTC", getutc(), "***", to_standard_error=true);

//   Debug :: #import "Debug"(USE_GRAPHICS=true);
//   Debug.init();
//   Debug.enable_signal_handler(interactive=true);
// }


init_db :: (key: string = "") {
  db.open(temp_c_string(config.db_name));

  is_db_locked = !db.query("select 1 from sqlite_master");

  // if db is locked then attempt to decrypt it using the provided key or config.rememeber_password
  if is_db_locked {
    db.open(temp_c_string(config.db_name)); // idk why it seems required to reopen the db first
    if key != "" then db.key(key);
    if !key && config.remember_password then db.key(config.remember_password);

    // if db is still locked, return
    is_db_locked = !db.query("select 1 from sqlite_master");
    if is_db_locked then return;
  }

  db.query(#string SQL
    CREATE TABLE IF NOT EXISTS copy (
       id INTEGER PRIMARY KEY,
       preview VARCHAR(255) NOT NULL,
       preview_hash INTEGER,
       full_text TEXT,
       first_seen_at UNSIGNED BIG INT NOT NULL,
       last_seen_at UNSIGNED BIG INT NOT NULL,
       type INTEGER NOT NULL DEFAULT 0,
       count INTEGER NOT NULL DEFAULT 0,
       bytecount INTEGER NOT NULL DEFAULT 0
    )
  SQL);

  db.query("CREATE INDEX IF NOT EXISTS index_last_seen_at ON copy (last_seen_at)");
  db.query("CREATE INDEX IF NOT EXISTS index_first_seen_at ON copy (first_seen_at)");
  db.query("CREATE INDEX IF NOT EXISTS index_type ON copy (type)");
  db.query("CREATE INDEX IF NOT EXISTS index_preview_hash ON copy (preview_hash)");
  db.query("CREATE INDEX IF NOT EXISTS index_bytecount ON copy (bytecount)");

  total_copy_count = db.select_int("select count(1) from copy");

  if !is_db_locked && total_copy_count==0 {
    insert_into_db(#run interp(#string STR
      %{APP_NAME} %{VERSION} by farzher
      Alt + ` (backtick/tilde ~) to toggle
      Hover over the right half of this clip to expand it

      This is a clipboard manager that keeps a history of everything you copy
      Report any bugs to papa@papajohns.com
    STR));
  }
}


ignore_next_blur := false;
update :: () {

  previous_select_index := selected_index;
  previous_scroll_offset := scroll_offset;
  previous_search_string := search_string.*;

  update_records_handeled := false;

  update_window_events();

  #if ONLY_RENDER_WHEN_CHANGED if events_this_frame.count render_dirty_info.new_event = true;

  for * event : events_this_frame {
    // if event.shift_pressed then mylog(event.*);

    // exit when you close the window or hit F5
    if event.type == .QUIT || event.key_code == .F5 then exit(0);

    // handle search input
    GetRect.current_time = getms();
    if event.key_code != .ARROW_UP && event.key_code != .ARROW_DOWN // don't handle up/down arrow with getrect. it does some history navigation nonsense...
      GetRect.handle_event(*search_input, event.*);

    if event.type == .KEYBOARD // use .KEYUP and .KEYDOWN events insead of .KEYBOARD
      event.type = ifx event.key_pressed then event.type.KEYDOWN else .KEYUP;

    if event.type == {

      case .KEYDOWN;

        if event.key_code == {

          // can use F1 keys to paste from that index
          // useful when copy pasting multiple things
          case .F1;                 do_submit_selected(0);
          case .F2;                 do_submit_selected(1);
          case .F3;                 do_submit_selected(2);
          case .F4;                 do_submit_selected(3);
          case .F5;                 do_submit_selected(4);
          case .F6;                 do_submit_selected(5);


          case .MOUSE_BUTTON_LEFT;  do_click();
          case .MOUSE_BUTTON_RIGHT; do_rightclick();
          case .DELETE;             do_delete();
          case .TAB;                do_tab();

          // in keydown so it doesn't trigger after delete confirmation
          case .ENTER;              if is_db_locked then decryptdb(); else do_submit_selected();
          case .ESCAPE;             show_window(false);

          case .ARROW_UP;   selected_index -= 1;
          case .ARROW_DOWN; selected_index += 1;

          case .HOME;
            selected_index = 0;
            scroll_offset = 0;

          case .END;
            scroll_offset = total_copy_count-1;
            selected_index = 0;

          case .PAGE_UP;
            if selected_index > 0 {
              selected_index = 0;
            } else {
              scroll_offset -= max_records-1;
            }

          case .PAGE_DOWN;
            if selected_index < max_records-1 {
              selected_index = max_records-1;
            } else {
              scroll_offset += max_records-1;
            }

        }


      case .CLIP_COPY; on_copy();

      case .FOCUS_LOST;
        if ignore_next_blur {ignore_next_blur=false; continue;}
        show_window(false);
        GetRect.clear_text(*search_input);


      case .HOTKEY; // when you hit the global hotkey, toggle the window
        visible = !visible;
        if visible set_window_pos_to_mouse(hwnd);

        show_window(xx ifx visible then SW_SHOW else SW_HIDE);


      case .MOUSE_WHEEL; // mouse wheel scrolling
        SCROLL_SPEED :: 120; // my mouse scrolls at 120 per click. logitech g600
        total_wheel_delta += event.wheel_delta;
        while abs(total_wheel_delta) >= SCROLL_SPEED {
          scroll_offset     -= ifx total_wheel_delta > 0 then 1 else -1;
          total_wheel_delta += ifx total_wheel_delta > 0 then -SCROLL_SPEED else SCROLL_SPEED;
        }


      case .MY_TRAY;

        if event.mycode == {

          case 514; // left click release
            show_window(true);

          case 517; // right click release

            run_on_startup := is_set_to_run_on_startup(APP_NAME);
            startup_label := ifx run_on_startup then "[✓] Run on Startup" else "Run on Startup";

            selection := popup_menu(.["Exit", startup_label, "Encrypt", "Delete Large Text Clips", "VACUUM DB", "Config / Settings", "Import from Ditto", "Open"]);
            if selection == {

              case "Run on Startup";
                System :: #import "System";
                add_to_startup(APP_NAME, System.get_path_of_running_executable());

              case "[✓] Run on Startup";
                remove_from_startup(APP_NAME);

              case "Exit"; exit(0);

              case "Open"; show_window(true);

              case "Config / Settings";
                ShellExecuteA(null, "open", CONFIG_PATH, null, null, SW_SHOW);

              case "Import from Ditto";
                if is_db_locked break; // db is currently locked

                cditto_filepath := showinputbox("ditto.db filepath", "ditto.db filepath", ispassword=false);
                if cditto_filepath == null then break;
                ditto_filepath := copy_temporary_string(fromcstr(cditto_filepath));

                import_from_ditto_db(ditto_filepath);

              case "Delete Large Text Clips";
                if config.large_text_clips {
                  db.query(#string SQL
                    DELETE FROM copy WHERE (type=? or type=?) AND bytecount > ?
                  SQL, cast(int)COPY_TYPE.TEXT, cast(int)COPY_TYPE.FILE, config.large_text_clips);
                }
                db.query("VACUUM"); // this is slow

              case "VACUUM DB"; db.query("VACUUM");

              case "Encrypt";
                if is_db_locked break; // db cannot be encrypted because it's currently locked

                cpassword := showinputbox("Enter a password", "Enter a password");
                if cpassword == null then break;
                password := copy_temporary_string(fromcstr(cpassword));

                cconfirmpassword := showinputbox("Confirm password", "Confirm password");
                if cconfirmpassword == null then break;
                confirmpassword := copy_temporary_string(fromcstr(cconfirmpassword));

                if confirmpassword != password then break;

                db.rekey(password);
                mylog("rekey() with pw:", password);

            }

        }
    }
  }


  if update_records_handeled then return;

  if previous_search_string != search_string.* then update_search_string();

  // ensure indexes are in range, and if scroll_offset changes, need to re-query
  if previous_select_index != selected_index || previous_scroll_offset != scroll_offset {
    multiselecting(xx input_button_states[Key_Code.SHIFT]&.DOWN, index=previous_select_index);
    ensure_selection_in_range();
  }

  if previous_scroll_offset != scroll_offset || previous_search_string != search_string.*
    update_records();
}





render :: () {

  // if you're hovering over the right side of a record
  // hover_index will be the index of the record you're hovereing
  // this allows for a different view of the record based on your mouse pos
  hover_index: int = -1;
  {
    mouse := Mouse.pos(hwnd);
    is_mouse_in_window := !(mouse.x < 0 || mouse.x > window_width || mouse.y < 0 || mouse.y > window_height);
    is_mouse_in_right_half := is_mouse_in_window && mouse.x >= window_width/4;
    hover_index = ifx is_mouse_in_right_half then mouse.y/config.record_height else -1;
  }

  #if ONLY_RENDER_WHEN_CHANGED {

    // if nothing changed, just sleep, don't render anything. the pervious frame will still be shown.
    nothing_changed := render_dirty_info.hover_index == hover_index && !render_dirty_info.new_event;
    if nothing_changed { sleep_milliseconds(1); return; }

    render_dirty_info.new_event = false; // set new_event as false when we render
    render_dirty_info.hover_index = hover_index;
  }

  update_window_transparency(can_be_transparent=hover_index == -1);

  // render records
  i := records.count-1; while i >= 0 { defer i -= 1;
    record := records[i];

    render_record_background :: () #expand {

      background_color := COLORS.DARK;
      if isselected(i) {
        background_color = COLORS.BLACK;
      } else if i%2==0 {
        background_color = COLORS.DARKER;
      }

      record_height := config.record_height;
      if record.type != .BITMAP && hover_index == i {
        line_count := Strings.count(record.preview, "\n") + 1;
        if line_count > config.record_lines {
          record_height += (line_count - config.record_lines) * (config.record_height/config.record_lines);
        }
      }

      Simp.set_shader_for_color();
      Simp.immediate_quad(cast(float)0, window_height - cast(float)i*config.record_height, cast(float)window_width, window_height - cast(float)i*config.record_height-record_height, background_color);
    }
    render_record_background();

    render_metadata :: () #expand {
      if hover_index == i {
        metatext := utc_to_time_ago(record.first_seen_at);
        if order_by == "bytecount" {
          metatext = interp("bytecount = ${record.bytecount}; ${metatext}");
        }
        text_width := Simp.prepare_text(my_tiny_font, metatext);
        Simp.draw_prepared_text(my_tiny_font, window_width-text_width-10, window_height - i*config.record_height - config.record_height+12, COLORS.TEXT);
      }
    }
    render_metadata();


    render_lines_of_text_or_img :: () #expand {

      // if it's an img, or at least sometimes an img (ex imgur)
      if record.type == .BITMAP || record.type == .WEBP || (hover_index == i && can_fetch_img_from_text(record.preview)) {
        if is_streamer_mode return;

        texture := TextureCache.get_texture_for_record(record);
        if !texture return;

        ratio := min(cast(float)window_width/texture.width, cast(float)config.record_height/texture.height);
        if hover_index == i then ratio = min(cast(float)window_width/texture.width, cast(float)(window_height - i*config.record_height)/texture.height);

        x := cast(float)0;
        y := cast(float)window_height - i*config.record_height;
        width := texture.width * ratio;
        height := texture.height * ratio;
        Simp.set_shader_for_images(texture);

        // why are these different?????????? one of them is upside down. i don't get it
        if record.type == .BITMAP || record.type == .WEBP {
          Simp.immediate_quad(x, y, x + width, y - height, COLORS.WHITE);
        } else {
          Simp.immediate_quad(x, y - height, x + width, y, COLORS.WHITE);
        }

        return;
      }

      color := COLORS.TEXT;
      if record.type == .FILE {
        color = COLORS.MUTED;
      }


      for line, line_count: Strings.line_split(record.preview) {
        if hover_index != i {
          if line_count >= config.record_lines then break;
        } else {
          if line_count >= MAX_LINE_COUNT then break;
        }

        if line.count > MAX_LINE_LEN then line.count = MAX_LINE_LEN;

        if search_string.count {
          text_x := 12;
          text_y := -12/2 + window_height - i*config.record_height - my_font.character_height*(line_count+1);
          for Strings.split(line, search_string.*, keep_separator=.AS_PREFIX, character_compare=Strings.ignore_case) {
            text := it;
            if it_index > 0 {
              matchingtext := it;
              matchingtext.count = search_string.count;
              text.data += search_string.count;
              text.count -= search_string.count;

              text_width := Simp.prepare_text(my_font, maybe_censor(matchingtext));
              Simp.draw_prepared_text(my_font, xx text_x, xx text_y, COLORS.RED);
              text_x += text_width;
            }

            text_width := Simp.prepare_text(my_font, maybe_censor(text));
            the_color := color;
            Simp.draw_prepared_text(my_font, xx text_x, xx text_y, the_color);
            text_x += text_width;
          }
        } else {
          text_width := Simp.prepare_text(my_font, maybe_censor(line));
          text_x := 12;
          text_y := -12/2 + window_height - i*config.record_height - my_font.character_height*(line_count+1);
          the_color := ifx selected_index == i then COLORS.RED else color;
          Simp.draw_prepared_text(my_font, xx text_x, xx text_y, the_color);
        }

      }
    }
    render_lines_of_text_or_img();
  }

  render_errors :: () #expand {
    if is_config_parse_error {
      for line, line_i: string.["CONFIG IS CORRUPT", #run interp("Fix or delete your %{CONFIG_PATH} file")] {
        text_width := Simp.prepare_text(my_font, line);
        Simp.draw_prepared_text(my_font, (window_width-text_width)/2, window_height - (my_font.character_height*(2+line_i)), COLORS.TEXT);
      }
    } else if is_db_locked {
      for line, line_i: string.["DATABASE IS ENCRYPTED", "Type your password and hit enter to decrypt"] {
        text_width := Simp.prepare_text(my_font, line);
        Simp.draw_prepared_text(my_font, (window_width-text_width)/2, window_height - (my_font.character_height*(2+line_i)), COLORS.TEXT);
      }
    } else if is_streamer_mode {
      for line, line_i: string.["STREAMER MODE ENABLED", "To view clips: Click anywhere or hit tab"] {
        text_width := Simp.prepare_text(my_font, line);
        Simp.draw_prepared_text(my_font, (window_width-text_width)/2, window_height - (my_font.character_height*(2+line_i)), COLORS.TEXT);
      }
    }
  }
  render_errors();


  render_search_string :: () #expand {
    ms := getms();
    if ms - search_input.last_keypress_time >= 1000 then return;

    text_width := Simp.prepare_text(my_big_font, maybe_censor(search_string.*));
    text_x := window_width/2 - text_width/2;
    text_y := window_height - 100;
    color := COLORS.RED;
    color.w = mapnumber(xx (ms - search_input.last_keypress_time), 1000, 0, 0, 1, exponent=0);
    Simp.draw_prepared_text(my_big_font, xx text_x, xx text_y, color);

    // #if 1 { // render selection
    //   if search_input.selection.active {
    //     start := search_input.selection.end_character;
    //     end := search_input.selection.start_character;
    //     GetRect.draw_procs.prepare_text = Simp.prepare_text;

    //     sx0, sx1 := GetRect.get_selection_endpoints(my_big_font, search_string.*, 0, xx text_x, start, end);

    //     sy0 := cast(float) text_y;
    //     sy1 := cast(float) text_y+my_big_font.character_height;

    //     #import "Math";
    //     p0 := Vector2.{sx0, sy0};
    //     p1 := Vector2.{sx1, sy0};
    //     p2 := Vector2.{sx1, sy1};
    //     p3 := Vector2.{sx0, sy1};

    //     Simp.set_shader_for_color(true);
    //     Simp.immediate_quad(p0, p1, p2, p3, color);
    //     // Simp.immediate_flush();
    //   }
    // }
  }
  render_search_string();


  render_scroll_bar :: () #expand {
    if scroll_offset > 0 && total_copy_count>0 {
      scroll_percent := cast(float)(scroll_offset + records.count) / total_copy_count;
      if scroll_percent > 0 {
        max_scroll_offset := total_copy_count-max_records;
        scrollbar_width :: 10;
        min_scrollbar_height :: 32;
        scrollbar_height := mapnumber(xx max_scroll_offset, 0, 100, xx window_height, min_scrollbar_height);
        scrollbar_y := mapnumber(xx scroll_offset, 0, xx max_scroll_offset, xx window_height, min_scrollbar_height);

        Simp.set_shader_for_color();
        Simp.immediate_quad(cast(float) window_width-12, scrollbar_y, cast(float) window_width-12+scrollbar_width, scrollbar_y-scrollbar_height, COLORS.RED);

      }
    }
  }
  render_scroll_bar();

  Simp.swap_buffers(hwnd);
  DwmFlush(); // simp opengl vsync burns 100% cpu without this
  Simp.update_window(hwnd);
  Simp.clear_render_target(COLORS.DARK.x, COLORS.DARK.y, COLORS.DARK.z, 0);
  // Simp.clear_render_target(COLORS.BLACKISH.x, COLORS.BLACKISH.y, COLORS.BLACKISH.z, 1);
  // Simp.clear_render_target(0,0,0,0);
  // Simp.clear_render_target(1,0,1,0);
}
















update_records :: () {
  // free existing records
  for records  free(it.preview); // perf: could write all records strings into a single buffer, then i'd never need to free it, just overwrite
  records.count = 0;

  // reset order back to default if we scroll top the top or start searching
  if order_by == "bytecount" {
    if search_string.count then order_by = "last_seen_at";
  } else {
    if scroll_offset == 0 || search_string.count then order_by = "last_seen_at";
  }

  the_select_from :: "select id, preview, last_seen_at, first_seen_at, count, type, bytecount from copy";
  rows: type_of(db.select(""));

  if starts_with(search_string.*, "id:") {
    id_str := substr(search_string.*, "id:".count, -"id:".count);
    id := parse_int(*id_str);
    if id {
      rows = db.select(to_c_string(interp("${the_select_from} where id=? limit 1"),, temp), id);
    }

  } else if search_string.count {
    words := split(search_string.*, " ");
    if(words.count > 1) {
      where_arr: [..]string;
      where_arr.allocator = temp;

      for word: words {
        array_add(*where_arr, interp("preview like '%${word}%'"));
      }

      where_string := join(..where_arr, " AND ",, temp);

      rows = db.select(to_c_string(interp("${the_select_from} where type=? and ${where_string} ORDER BY %{order_by} DESC LIMIT ? OFFSET ?"),, temp), cast(int)COPY_TYPE.TEXT, max_records, scroll_offset);
    } else {
      rows = db.select(to_c_string(interp("${the_select_from} where type=? and preview like '%'||?||'%' ORDER BY %{order_by} DESC LIMIT ? OFFSET ?"),, temp), cast(int)COPY_TYPE.TEXT, search_string.*, max_records, scroll_offset);
    }

  } else {
    rows = db.select(to_c_string(interp("${the_select_from} ORDER BY %{order_by} DESC LIMIT ? OFFSET ?"),, temp), max_records, scroll_offset);
  }

  for row: rows {
    if records.count >= max_records then break;

    record: DbRecord;
    record.id            = db.get_int(row, 0);
    record.preview       = db.get_str(row, 1); // perf don't load entire images here until we need them?
    record.last_seen_at  = db.get_int(row, 2);
    record.first_seen_at = db.get_int(row, 3);
    record.count         = db.get_int(row, 4);
    record.type          = xx db.get_int(row, 5);
    record.bytecount     = db.get_int(row, 6);

    records.count += 1;
    records[it_index] = record;
  }

  ensure_selection_in_range();
}

do_click :: () {
  if is_streamer_mode {is_streamer_mode = false; return; }

  mouse := Mouse.pos(hwnd);
  new_selected_index := mouse.y/config.record_height;
  if new_selected_index != selected_index {
    selected_index = new_selected_index;
    return;
  }

  do_submit_selected();
}
do_rightclick :: () #expand {
  if is_streamer_mode {is_streamer_mode = false; return; }

  mouse := Mouse.pos(hwnd);

  // before the right click menu pops up, select the item they clicked on! and render that change!
    selected_index = mouse.y/config.record_height;
    if selected_index < 0 then return;
    if selected_index >= records.count then return;
    render();

  selection := popup_menu(.["Delete", "Context", "Save To Downloads", "Sort By Size"]);
  if selection == {

    case "Delete"; do_delete();

    case "Context";
      record := records[selected_index];

      order_by = "first_seen_at";

      scroll_offset = db.select_int("select count(1) from copy where first_seen_at > ?", record.first_seen_at);
      scroll_offset -= max_records/2;
      selected_index = max_records/2;
      GetRect.clear_text(*search_input);
      update_records(); // to update records.count; so our selected_index works; i think this will cause us to query twice
      `update_records_handeled = true;

    case "Sort By Size";
      order_by = "bytecount";
      update_records();

    case "Save To Downloads";
      record := records[selected_index];
      if record.type == {
        case .BITMAP; #through;
        case .WEBP;
          System :: #import "System";
          // if you call this too quickly (within the same second) filenames will be the same and overwrite ...
          // ^ fixed by using getutcms
          filepath := tprint("C:/Users/%/Downloads/clipman_%.png", System.get_username(), getutcms());
          success := save_bitmap_to_file(record_to_windows_bitmap(record), filepath);
          if !success  mylog("failed to save image");

        case; mylog("can only save bitmaps"); return;
      }

  }

}

do_delete :: () {
  ignore_next_blur = true;

  message := ifx multiselecting() interp("Are you sure you want to delete these #{selected_count()} clips?") else "Are you sure you want to delete this clip?";
  response := MessageBoxW(null, utf8_to_wide(message), utf8_to_wide("Delete Record"), MB_OKCANCEL | MB_TOPMOST);
  if response != IDOK then return;

  for selected_expansion {
    db.query("delete from copy where id = ?", records[it].id);
    total_copy_count -= 1;
  }

  update_records();

}

do_tab :: () {
  if is_streamer_mode {is_streamer_mode = false; return; }
}

do_submit_selected :: (force_selection := -1) {
  if force_selection != -1 {
    selected_index = force_selection;
  }

  if selected_index < 0 then return;
  if selected_index >= records.count then return;

  show_window(false);

  record := records[selected_index];

  //
  if multiselecting() {
    push_tallocator();
    builder: String_Builder;
    initial_type := record.type;
    for selected_expansion {

      if records[it].type != initial_type {
        mylog("can't multipaste multiple types"); return;
      }

      if it_index != 0  append(*builder, "\n");

      if records[it].type == {
        case .BITMAP; mylog("can't multipaste bitmaps"); return;
        case .TEXT; append(*builder, records[it].preview);
        case .FILE; append(*builder, records[it].preview);
      }
    }
    record.preview = builder_to_string(*builder);
  }


  // copy their selection into the clipobard then paste it
  if record.type == {

    case .TEXT;   if record.preview.count then os_clipboard_set_text(record.preview);

    case .BITMAP; if record.preview.count then os_clipboard_set_bitmap(hwnd, decompress(record.preview));
    case .WEBP  ; if record.preview.count then os_clipboard_set_bitmap(hwnd, record_to_windows_bitmap(record));

    case .FILE;
      push_tallocator();
      filesstr: string;
      for line: Strings.line_split(record.preview) {
        // todo: first_index is broken!!!
        // filesstr = strings_alloc.join(filesstr, Strings.substring(line, first_index(line, " - ")+" - ".count), "\0");
        // filesstr = strings_alloc.join(filesstr, Strings.substring(line, Strings.first_index(line, " - ")+" - ".count), "\0");
        filesstr = String.join(filesstr, Strings.substring(line, Strings.first_index(line, " - ")+" - ".count), "\0");
      }
      if record.preview.count then os_clipboard_set_file(hwnd, filesstr);

  }
  send_paste();
}

decryptdb :: () {
  init_db(search_string.*);
  GetRect.clear_text(*search_input);
}

on_copy :: () {
  bmpinfobytes := os_clipboard_get_bitmap(hwnd);
  if bmpinfobytes.count {
    insert_into_db(bmpinfobytes, .BITMAP);
    update_records();
    return;
  }

  files := os_clipboard_get_file(hwnd);
  if files.count {
    for f, i: files {
      files[i] = tprint("% - %", Strings.substring(f, mylastindex(f, #char "\\")+"\\".count), f);
    }
    // str := strings_alloc.join(files, "\n", tallocator);
    str := String.join(..files, separator="\n",, tallocator);
    insert_into_db(str, .FILE);
    update_records();
    return;
  }

  clip_text := os_clipboard_get_text(); defer free(clip_text);
  if clip_text.count {
    insert_into_db(clip_text, .TEXT);
    update_records();
    return;
  }
}

ensure_selection_in_range :: () {
  if selected_index + scroll_offset >= total_copy_count {
    selected_index -= (selected_index + scroll_offset) - (total_copy_count-1);
  }

  if selected_index < 0 {
    scroll_offset += selected_index;
  } else if selected_index >= max_records {
    scroll_offset += selected_index - (max_records-1);
  }

       if selected_index < 0                 then selected_index = 0;
  else if selected_index >= records.count    then selected_index = records.count-1;

       if scroll_offset < 0                  then scroll_offset = 0;
  else if scroll_offset >= total_copy_count  then {scroll_offset = total_copy_count-1; selected_index = 0;}
}

sleep_based_on_last_interaction_time :: () {
  ms_since_last_interation := get_ms_since_last_interaction();
  ms_to_sleep := mapnumber(xx ms_since_last_interation, 0,1000*60*5/*5 min*/, 1,200, exponent=1.5);
  sleep_milliseconds(xx ms_to_sleep);
}


// sharex screenshot sends 2 copy events, so this is called twice...
// also every time we paste a clip we copy it first, which would cause duplicates
// so we need to deduplicate clips
insert_into_db :: (_str: string, _copy_type: COPY_TYPE = .TEXT) {
  utc : int = xx getutc();

  str := _str; // to make it not immutable
  copy_type := _copy_type; // to make it not immutable
  if _copy_type == .BITMAP then str = compress(str);

  if_the_image_is_big_compress_it :: () #expand {
    if _copy_type == .BITMAP {
      // if str.count > 10000 {
        webpbytes := windows_bitmap_to_webp(_str, quality=90);
        if webpbytes.count > str.count return;
        str = webpbytes;
        copy_type = .WEBP;
      // }
    }
  }
  if_the_image_is_big_compress_it();

  // if this record has already been inserted, just update it instead of inserting a copy
  existing_record_id: int;
  if _copy_type == .BITMAP {

    #import "Hash";
    hash : int = sdbm_hash(str.data, str.count);
    existing_record_id = db.select_int("select id from copy where type=? and preview_hash=? and preview=? limit 1", cast(int)copy_type, hash, str);
  } else {
    existing_record_id = db.select_int("select id from copy where type=? and preview=? limit 1", cast(int)copy_type, str);
  }

  if existing_record_id {
    db.query("UPDATE copy SET last_seen_at=?, count=count+1 where id=?", utc, existing_record_id);
  } else {

    hash : int = 0;
    if _copy_type == .BITMAP {
      hash = sdbm_hash(str.data, str.count);
    }

    success := db.query("INSERT INTO copy (preview, preview_hash, last_seen_at, first_seen_at, type, bytecount) VALUES (?, ?, ?, ?, ?, ?)", str, hash, utc, utc, cast(int)copy_type, str.count);
    if !success then return;
    total_copy_count += 1;
  }

  // write the uncompress image into the cache
  if _copy_type == .BITMAP && copy_type == .WEBP {
    record_id := existing_record_id;
    if !record_id {
      record_id = db.select_int("select last_insert_rowid()");
    }
    if !record_id {
    } else {
      write_entire_file_to_clipman_cache_temp_folder(interp("${record_id}"), compress(_str));
    }

  }

  selected_index = 0;
  scroll_offset = 0;
}

import_from_ditto_db :: (ditto_filepath: string) {

  tmp_insert_into_db :: (str: string, first_seen_at: int, last_seen_at: int, copy_type: COPY_TYPE = .TEXT) -> success: bool {
    exists_id: int = db.select_int("select id from copy where preview = ? and type=? limit 1", str, cast(int)copy_type);

    if exists_id return false;

    success := db.query("INSERT INTO copy (preview, last_seen_at, first_seen_at, type) VALUES (?, ?, ?, ?)", str, last_seen_at, first_seen_at, cast(int)copy_type);
    if !success then {
      mylog("!success", first_seen_at);
      return false;
    }

    total_copy_count += 1;
    selected_index = 0;
    scroll_offset = 0;
    return true;
  }

  MAXIMUM_CLIP_LENGTH :: 10_000;

  mylog("starting ditto import");

  ditto :: #import,file "modules/mysqlite3.jai"(id="ditto");
  for_expansion :: ditto.for_expansion; // gross

  #import "File_Utilities";
  if !file_exists(ditto_filepath) {
    mylog("ditto_filepath doesn't exist:", ditto_filepath);
    return;
  }

  err := ditto.open(temp_c_string(ditto_filepath));
  if err {
    mylog("failed to open ditto_filepath:", ditto_filepath);
    return;
  }

  for ditto.select("select ooData, lDate, lastPasteDate from Main join Data ON Data.lParentID=Main.lID where strClipBoardFormat=?", "CF_UNICODETEXT") {
    push_tallocator();
    auto_release_temp();

    ooData        := ditto.get_txt(it, 0);
    if ooData.count > MAXIMUM_CLIP_LENGTH  continue;

    first_seen_at := ditto.get_int(it, 1);
    last_seen_at  := ditto.get_int(it, 2);


    inserted := tmp_insert_into_db(ooData, first_seen_at, last_seen_at);
    if inserted mylog(ooData);
  }

  mylog("ditto import finished");
}






// depends on many globals
config_load :: () {
  using,only(read_entire_file) #import "File";
  json :: #import,dir "modules/json";

  // define these globals computed by the newly loaded config data
  defer {
    window_width  = config.window_width;
    window_height = config.record_height * (config.window_height/config.record_height);
    max_records   = cast(int) ceil(cast(float)window_height / config.record_height);
  }

  // config file doesn't exist. create it using the default config
  if !file_exists(CONFIG_PATH) {
    json.json_write_file(CONFIG_PATH, config);
    return;
  }

  // read/parse the config file into config
  file_data, read_success := read_entire_file(CONFIG_PATH);
  if !read_success {is_config_parse_error = true; return; }

  parse_success, parsed_config := json.json_parse_string(file_data, type_of(config));
  if !parse_success {is_config_parse_error = true; return; }

  config = parsed_config;
}








COPY_TYPE      :: enum u8 {TEXT :: 0; FILE :: 1; BITMAP :: 2; WEBP :: 3;}

DbRecord       :: struct {id: int; preview: string; first_seen_at: int; last_seen_at: int; count: int; type: COPY_TYPE; bytecount: int; }

MAX_LINE_LEN   :: 200; // only for rendering performance
MAX_LINE_COUNT :: 60;  // only for rendering performance


// all the junk we depend on
// all the junk we depend on

// RELEASE :: #run () -> bool {Compiler :: #import "Compiler"; return Compiler.get_build_options().optimization_level == .RELEASE; }();
// #import "Basic"()(MEMORY_DEBUGGER=true);
#import "Basic";
#import,file "modules/mybasic.jai";
#import,file "modules/mywindows.jai";
#import,file "modules/myclipboard.jai";

db :: #import,file "modules/mysqlite3.jai";
for_expansion :: db.for_expansion; // this is gross

COLORS :: #import,dir "modules/colors";

Simp :: #import "Simp";

using,only(ceil,abs) Math :: #import "Math";

// #import,dir "modules/Input";
#import "Input"; // we need to use this normal style of import so we import the same Input as getrect

#import,dir "modules/Window_Creation";
#import "Windows_Utf8";

String        :: #import "String";
Strings       :: #import,dir "modules/Strings";
// strings_alloc :: #import,dir "modules/Strings_Alloc";
for_expansion :: Strings.for_expansion; // this is gross
