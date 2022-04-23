#load "functions.jai";

APP_NAME      :: "ClipMan";
VERSION       :: "v0.0.0";
CONFIG_PATH   :: "clipman.json";
config: struct { // overwitten by config_load
  window_width      : int    = 1200;
  window_height     : int    = 840;
  record_height     : int    = 70;
  record_lines      : int    = 3;
  hotkey_mod        : int    = MOD_ALT | MOD_NOREPEAT;
  hotkey_key        : int    = 0xc0/*tilde `*/;
  transparency      : int    = 90;
  streamer_mode     : int    = 0; // for privacy. won't render clips unless you take an extra action. 0 to disable
  on_startup_open   : int    = 1;
  on_startup_delete_clips_bigger_than   : int = 10000;
  db_name           : string = "clipman.db";
  remember_password : string = "";
}
window_width  : int; // defined by config_load
window_height : int; // defined by config_load
max_records   : int; // defined by config_load


visible := true;
hwnd    : HWND;



main :: () {
  set_working_directory("./bin"); // set cwd
  config_load(); // load the config first

  // create the main window
  hwnd = create_window(
    window_name=#run tprint("% %", APP_NAME, VERSION),
    width=window_width, height=window_height,
    background_color_rgb=COLORS.to_3f(COLORS.DARK),
    style=WS_POPUP,
    style_ex=WS_EX_LAYERED | WS_EX_TOOLWINDOW
  );
  set_window_pos_to_mouse(hwnd);
  show_window(false);
  if config.on_startup_open then show_window(true); // just to trigger streamer_mode stuff

  // register our global show hide hotkey
  RegisterHotKey(hwnd, 0, xx config.hotkey_mod, xx config.hotkey_key);

  // need this to receive clipboard copy events
  AddClipboardFormatListener(hwnd);

  // init Simp rendering stuff
  Simp.set_render_target(hwnd);
  // Simp.simp_init(hwnd, xx window_width, xx window_height, xx window_width, xx window_height, windowed=true, vsync=true);

  // init everything
  init_everything();

  // create tray icon
  trayicon_create(tooltip=#run tprint("% %", APP_NAME, VERSION));

  // main game loop
  while 1 {

    update();

    if visible then render(); else sleep_milliseconds(1000/10);

    tfree();

  }
}

// todo: need a tutorial that expains the basics if you were to just run the exe
// todo: need a way to edit settings / hotkey / remember password
// todo: ability to resize the window
// todo: sort by size? so you can manually remove the big stuff to cleanup



selected_index: int;
selected_index_end: int = -1;
scroll_offset: int;

records: [..] DbRecord;
total_copy_count: int;
total_wheel_delta: int;

is_streamer_mode: bool;
is_db_locked: bool;
is_config_parse_error: bool;

init_everything :: () {

  init_db();

  array_reserve(*records, max_records);

  init_search_string();

  update_records();

  init_font();

}


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
       full_text TEXT,
       first_seen_at UNSIGNED BIG INT NOT NULL,
       last_seen_at UNSIGNED BIG INT NOT NULL,
       type INTEGER NOT NULL DEFAULT 0,
       count INTEGER NOT NULL DEFAULT 0
    )
  SQL);

  // auto delete big clips like images on startup, to keep the db small
  if config.on_startup_delete_clips_bigger_than {
    db.query(#string SQL
      DELETE FROM copy WHERE length(cast(preview as blob)) > ?
    SQL, config.on_startup_delete_clips_bigger_than);
  }
  db.query("VACUUM");

  db.query(#string SQL
    CREATE INDEX IF NOT EXISTS index_last_seen_at ON copy (last_seen_at)
  SQL);

  // todo do i need an index on preview? wouldn't this make the table twice as big?
  // db.query(#string SQL
  //   CREATE UNIQUE INDEX IF NOT EXISTS index_preview ON copy (preview);
  // SQL);


  total_copy_count = db.select_int("select count(1) from copy");

  if !is_db_locked && total_copy_count==0 {
    tutorial_copy := #string STR
      % % by farzher
      Alt + ` (backtick/tilde ~) to toggle
      Hover over the right half of this clip to expand it

      This is a clipboard manager that keeps a history of everything you copy
      Report any bugs to papa@papajohns.com
    STR;
    insert_into_db(tprint(tutorial_copy, APP_NAME, VERSION));
  }
}


ignore_next_blur := false;
update :: () {

  previous_select_index := selected_index;
  previous_scroll_offset := scroll_offset;
  previous_search_string := <<search_string;

  update_records_handeled := false;

  update_window_events(); for * event : events_this_frame {
    // if event.shift_pressed then mylog(<<event);

    // exit when you close the window or hit F5
    if event.type == .QUIT || event.key_code == .F5 then exit(0);

    // handle search input
    GetRect.current_time = getms();
    GetRect.handle_event(*search_input, .{}, <<event);

    if event.type == .KEYBOARD // use .KEYUP and .KEYDOWN events insead of .KEYBOARD
      event.type = ifx event.key_pressed then event.type.KEYDOWN else .KEYUP;

    if event.type == {
      case .KEYUP;
        if event.key_code == {

          case .F1;                 #if 0 report_memory_leaks();
          case .MOUSE_BUTTON_LEFT;  do_click();
          case .MOUSE_BUTTON_RIGHT; do_rightclick();
          case .DELETE;             do_delete();
          case .TAB;                do_tab();

        }

      case .KEYDOWN;

        if event.key_code == {

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
        search_string.count = 0;


      case .HOTKEY; // when you hit the global hotkey, toggle the window
        visible = !visible;
        if visible set_window_pos_to_mouse(hwnd);

        show_window(xx ifx visible then SW_SHOW else SW_HIDE);


      case .MOUSE_WHEEL; // mouse wheel scrolling
        total_wheel_delta += event.wheel_delta;
        SCROLL_SPEED :: 100;
        if total_wheel_delta >= SCROLL_SPEED || total_wheel_delta <= -SCROLL_SPEED {
          scroll_count := total_wheel_delta / SCROLL_SPEED;
          total_wheel_delta -= scroll_count * SCROLL_SPEED;

          scroll_offset += -scroll_count;
        }
        total_wheel_delta = 0;


      case .MY_TRAY;

        if event.mycode == {

          case 514; // left click release
            show_window(true);

          case 517; // right click release

            selection := popup_menu(.["Exit", "Encrypt", "Open"]);
            if selection == {
              case "Exit"; exit(0);
              case "Open"; show_window(true);
              case "Encrypt";
                if is_db_locked {
                  // db cannot be encrypted because it's currently locked
                  break;
                }

                cpassword := showinputbox("Enter a password", "Enter a password");
                if cpassword == null then break;
                password := copy_string(fromcstr(cpassword), tallocator);

                cconfirmpassword := showinputbox("Confirm password", "Confirm password");
                if cconfirmpassword == null then break;
                confirmpassword := copy_string(fromcstr(cconfirmpassword), tallocator);

                if confirmpassword != password then break;

                db.rekey(password);
                mylog("rekey() with pw:", password);
            }

        }
        // mylog("idk2", event.mycode);
    }
  }


  if update_records_handeled then return;

  if previous_search_string != <<search_string then update_search_string();

  // ensure indexes are in range, and if scroll_offset changes, need to re-query
  if previous_select_index != selected_index || previous_scroll_offset != scroll_offset {
    multiselecting(xx input_button_states[Key_Code.SHIFT]&.DOWN, index=previous_select_index);
    ensure_selection_in_range();
  }

  if previous_scroll_offset != scroll_offset || previous_search_string != <<search_string
    update_records();
}








render :: () {
  #if true { // weird hover feature
    mouse := Mouse.pos();
    is_mouse_in_window := !(mouse.x < 0 || mouse.x > window_width || mouse.y < 0 || mouse.y > window_height);
    is_mouse_in_right_half := is_mouse_in_window && mouse.x >= window_width/4;
    hover_index: int = ifx is_mouse_in_right_half then mouse.y/config.record_height else -1;
  } else {
    hover_index := -1;
  }

  update_window_transparency(can_be_transparent=hover_index == -1);

  // render records
  i := records.count-1; while i >= 0 { defer i -= 1;
    record := records[i];

    render_record_background();
    render_record_background :: () #expand {

      background_color := COLORS.DARK;
      if isselected(i) {
        background_color = COLORS.BLACK;
      } else if i%2==0 {
        background_color = COLORS.DARKER;
      }

      record_height := config.record_height;
      if record.type != .BITMAP && hover_index == i {
        line_count := count(record.preview, "\n") + 1;
        if line_count > config.record_lines {
          record_height += (line_count - config.record_lines) * (config.record_height/config.record_lines);
        }
      }

      Simp.set_shader_for_color();
      Simp.immediate_quad(cast(float)0, window_height - cast(float)i*config.record_height, cast(float)window_width, window_height - cast(float)i*config.record_height-record_height, background_color);
    }

    render_metadata();
    render_metadata :: () #expand {
      if hover_index == i {
        text_width := Simp.prepare_text(my_tiny_font, utc_to_time_ago(record.last_seen_at));
        // text_width := Simp.prepare_text(my_tiny_font, tprint("%", record.last_seen_at));
        Simp.draw_prepared_text(my_tiny_font, window_width-text_width-10, window_height - i*config.record_height - config.record_height+12, COLORS.TEXT);
      }
    }


    if !is_streamer_mode then render_lines_of_text();
    render_lines_of_text :: () #expand {
      if record.type == .BITMAP {

        texture := TextureCache.get_texture_for_record(record);

        ratio := min(cast(float)window_width/texture.width, cast(float)config.record_height/texture.height);
        if hover_index == i then ratio = min(cast(float)window_width/texture.width, cast(float)(window_height - i*config.record_height)/texture.height);

        x := cast(float)0;
        y := cast(float)window_height - i*config.record_height;
        width := texture.width * ratio;
        height := texture.height * ratio;
        Simp.set_shader_for_images(texture);
        Simp.immediate_quad(x, y, x + width, y - height, COLORS.WHITE);
        return;
      }

      color := COLORS.TEXT;
      if record.type == .FILE {
        color = COLORS.MUTED;
      }


      for line, line_count: line_split(record.preview) {
        if hover_index != i {
          if line_count >= config.record_lines then break;
        } else {
          if line_count >= MAX_LINE_COUNT then break;
        }

        if line.count > MAX_LINE_LEN then line.count = MAX_LINE_LEN;

        if search_string.count {
          text_x := 12;
          text_y := -12/2 + window_height - i*config.record_height - my_font.character_height*(line_count+1);
          for split(line, <<search_string, keep_separator=.AS_PREFIX, compare=ignore_case) {
            text := it;
            if it_index > 0 {
              matchingtext := it;
              matchingtext.count = search_string.count;
              text.data += search_string.count;
              text.count -= search_string.count;

              text_width := Simp.prepare_text(my_font, matchingtext);
              Simp.draw_prepared_text(my_font, xx text_x, xx text_y, COLORS.RED);
              text_x += text_width;
            }

            text_width := Simp.prepare_text(my_font, text);
            the_color := color;
            Simp.draw_prepared_text(my_font, xx text_x, xx text_y, the_color);
            text_x += text_width;
          }
        } else {
          text_width := Simp.prepare_text(my_font, line);
          text_x := 12;
          text_y := -12/2 + window_height - i*config.record_height - my_font.character_height*(line_count+1);
          the_color := ifx selected_index == i then COLORS.RED else color;
          Simp.draw_prepared_text(my_font, xx text_x, xx text_y, the_color);
        }

      }
    }
  }

  render_errors();
  render_errors :: () #expand {
    if is_config_parse_error {
      for line, line_i: string.["CONFIG IS CORRUPT", #run tprint("Fix or delete your % file", CONFIG_PATH)] {
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


  render_search_string();
  render_search_string :: () #expand {
    ms := getms();
    if ms - search_input.last_keypress_time >= 1000 then return;

    search_string_to_render: string = <<search_string;
    if is_db_locked {
      search_string_to_render.data = talloc(search_string_to_render.count);
      memset(search_string_to_render.data, #char"*", search_string_to_render.count);
    }

    text_width := Simp.prepare_text(my_big_font, search_string_to_render);
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

    //     sx0, sx1 := GetRect.get_selection_endpoints(my_big_font, <<search_string, 0, xx text_x, start, end);

    //     sy0 := cast(float) text_y;
    //     sy1 := cast(float) text_y+my_big_font.character_height;

    //     p0 := make_vector2(sx0, sy0);
    //     p1 := make_vector2(sx1, sy0);
    //     p2 := make_vector2(sx1, sy1);
    //     p3 := make_vector2(sx0, sy1);

    //     Simp.set_shader_for_color(true);
    //     Simp.immediate_quad(p0, p1, p2, p3, color);
    //     // Simp.immediate_flush();
    //   }
    // }
  }


  render_scroll_bar();
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

  rows: #run type_of(db.select(""));
  if search_string.count {
    // todo split search into multiples on space
    // map(split(search_string), "preview like '%'||?||'%'"
    // join(, " AND ")
    rows = db.select("select id, preview, last_seen_at, first_seen_at, count, type from copy where preview like '%'||?||'%' ORDER BY last_seen_at DESC LIMIT ? OFFSET ?", <<search_string, max_records, scroll_offset);
  } else {
    rows = db.select("select id, preview, last_seen_at, first_seen_at, count, type from copy ORDER BY last_seen_at DESC LIMIT ? OFFSET ?", max_records, scroll_offset);
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

    records.count += 1;
    records[it_index] = record;
  }

  ensure_selection_in_range();
}

do_click :: () {
  if is_streamer_mode {is_streamer_mode = false; return; }

  mouse := Mouse.pos();
  new_selected_index := mouse.y/config.record_height;
  if new_selected_index != selected_index {
    selected_index = new_selected_index;
    return;
  }

  do_submit_selected();
}
do_rightclick :: () #expand {
  if is_streamer_mode {is_streamer_mode = false; return; }

  mouse := Mouse.pos();

  selection := popup_menu(.["Delete", "Context"]);
  if selection == {

    case "Delete"; mylog("delete menu item not yet supported"); return;

    case "Context";
      if search_string.count == 0 then return;
      // is_mouse_in_right_half := mouse.x >= window_width/4;
      // if !is_mouse_in_right_half then return;
      selected_index = mouse.y/config.record_height;
      if selected_index < 0 then return;
      if selected_index >= records.count then return;
      record := records[selected_index];
      scroll_offset = db.select_int("select count(1) from copy where last_seen_at > ?", record.last_seen_at);
      scroll_offset -= max_records/2;
      selected_index = max_records/2;
      search_string.count = 0;
      update_records(); // to update records.count; so our selected_index works; i think this will cause us to query twice
      `update_records_handeled = true;
  }

}

do_delete :: () {
  ignore_next_blur = true;

  response := MessageBoxW(null, utf8_to_wide("Are you sure you want to delete this?"), utf8_to_wide("Delete Record"), MB_OKCANCEL | MB_TOPMOST);
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

do_submit_selected :: () {
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
    case .FILE;
      push_tallocator();
      filesstr: string;
      for line: line_split(record.preview) {
        // todo: first_index is broken!!!
        // filesstr = strings_alloc.join(filesstr, substring(line, first_index(line, " - ")+" - ".count), "\0");
        filesstr = strings_alloc.join(filesstr, substring(line, String.find_index_from_left(line, " - ")+" - ".count), "\0");
      }
      if record.preview.count then os_clipboard_set_file(hwnd, filesstr);
  }
  send_paste();
}

decryptdb :: () {
  init_db(<<search_string);
  search_string.count = 0;
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
      files[i] = tprint("% - %", substring(f, mylastindex(f, #char "\\")+"\\".count), f);
    }
    str := strings_alloc.join(files, "\n", tallocator);
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


insert_into_db :: (_str: string, copy_type: COPY_TYPE = .TEXT) {
  utc : int = xx getutc();

  str := _str; // to make it not immutable
  if copy_type == .BITMAP then str = compress(str);

  id: int;
  for db.select("select id from copy where preview = ? and type=? limit 1", str, cast(int)copy_type)  id = db.get_int(it, 0);

  if id {
    db.query("UPDATE copy SET last_seen_at=?, count=count+1 where id=?", utc, id);
  } else {
    success := db.query("INSERT INTO copy (preview, last_seen_at, first_seen_at, type) VALUES (?, ?, ?, ?)", str, utc, utc, cast(int)copy_type);
    if !success then return;
    total_copy_count += 1;
  }

  selected_index = 0;
  scroll_offset = 0;
}






#import "json";
#import "File";
config_load :: () {
  file_data, file_success := read_entire_file(CONFIG_PATH);

  if(file_success) {
    replace(file_data, "\r\n", #char" "); // because the json reader can't deal with newlines ... at least not windows newlines
    root, parse_success := json_parse_string(file_data, type_of(config));
    if(parse_success) {
      config = root;
    } else {
      is_config_parse_error = true;
    }
  } else {
    write_success := json_write_file(CONFIG_PATH, config, indent_char="\n");
  }

  window_width  = config.window_width;
  window_height = config.record_height * (config.window_height/config.record_height);
  max_records   = cast(int) ceil(cast(float)window_height / config.record_height);
}








COPY_TYPE :: enum u8 {TEXT; FILE; BITMAP;}
DbRecord :: struct {id: int; preview: string; first_seen_at: int; last_seen_at: int; count: int; type: COPY_TYPE; }
MAX_LINE_LEN  :: 200; // only for rendering performance
MAX_LINE_COUNT:: 60;  // only for rendering performance

#import "mybasic";
#import "mywindows";
#import "myclipboard";

db :: #import "mysqlite3";
for_expansion :: db.for_expansion; // this is gross

COLORS :: #import "colors";

#import "Math";

Simp :: #import "Simp";

#import "Input";
#import "Window_Creation";
#import "Windows_Utf8";

String :: #import "String";
#import "Strings";
strings_alloc :: #import "Strings_Alloc";
