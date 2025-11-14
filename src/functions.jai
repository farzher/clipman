



// self contained helper functions without global dependencies




// #load "modules/mybasic.jai";
#import "Basic";
#import,file "modules/mybasic.jai";
#import,file "modules/mywindows.jai";
#import "Window_Creation";
#import "String";
Strings :: #import,dir "modules/Strings";


Mouse: struct {

  Point :: struct {x: s32; y: s32;}

  pos :: (hwnd: HWND) -> Point {
    x, y := get_mouse_pointer_position(hwnd, false);
    pos: Point = ---;
    pos.x = xx x;
    pos.y = xx y;
    return pos;
  }

  pos_global :: () -> Point {
    p: POINT = ---;
    GetCursorPos(*p);
    pos: Point = ---;
    pos.x = p.x;
    pos.y = p.y;
    return pos;
  }
}




// Monitor.size(hwnd) memoizes the size the first time it's called.
// this probably has issues with multiple monitors
Monitor: struct {

  _size: struct {x, y, w, h :s32;};
  size :: (hwnd: HWND) -> type_of(_size) { ensure_init(hwnd); return Monitor._size; }

  init :: (hwnd: HWND) {
    info: MONITORINFO = ---;
    info.cbSize = size_of(type_of(info));
    success := GetMonitorInfoW(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), *info);
    if !success  die("failed to get monitor size");

    Monitor._size.x = info.rcMonitor.left;
    Monitor._size.y = info.rcMonitor.top;
    Monitor._size.w = info.rcMonitor.right - Monitor._size.x;
    Monitor._size.h = info.rcMonitor.bottom - Monitor._size.y;
  }

  ensure_init :: (hwnd: HWND) {
    if Monitor._size.w != 0  return;
    Monitor.init(hwnd);
  }
}





set_window_pos_to_mouse :: (hwnd: HWND) {

  hwnd_rect: RECT;
  GetWindowRect(hwnd, *hwnd_rect);
  window_width  := hwnd_rect.right - hwnd_rect.left;
  window_height := hwnd_rect.bottom - hwnd_rect.top;

  mouse := Mouse.pos_global();

  x := mouse.x;
  too_far_left_amount := cast(s32)( x + window_width - Monitor.size(hwnd).w );
  if too_far_left_amount > 0 then x -= too_far_left_amount;

  y := mouse.y;
  too_far_down_amount := cast(s32)( y + window_height - Monitor.size(hwnd).h );
  if too_far_down_amount > 0 then y -= too_far_down_amount;

  SetWindowPos(hwnd, HWND_TOPMOST, x, y, xx window_width, xx window_height, /*SWP_NOZORDER | SWP_NOACTIVATE | */SWP_FRAMECHANGED);
  // SetWindowPos(hwnd, HWND_TOPMOST, mouse.x, mouse.y, window_width, window_height, SWP_FRAMECHANGED);
}

send_paste :: () {
  // Create a generic keyboard event structure
  ip: INPUT = ---;
  ip.type = .INPUT_KEYBOARD;
  ip.ki.wScan = 0;
  ip.ki.time = 0;
  ip.ki.dwExtraInfo = 0;

  // Press the "Ctrl" key
  ip.ki.wVk = VK_CONTROL;
  ip.ki.dwFlags = 0; // 0 for key press
  SendInput(1, *ip, size_of(INPUT));

  // Press the "V" key
  ip.ki.wVk = #char "V";
  ip.ki.dwFlags = 0; // 0 for key press
  SendInput(1, *ip, size_of(INPUT));

  // Release the "V" key
  ip.ki.wVk = #char "V";
  ip.ki.dwFlags = KEYEVENTF_KEYUP;
  SendInput(1, *ip, size_of(INPUT));

  // Release the "Ctrl" key
  ip.ki.wVk = VK_CONTROL;
  ip.ki.dwFlags = KEYEVENTF_KEYUP;
  SendInput(1, *ip, size_of(INPUT));
}

utc_to_time_ago :: (oldutc: int) -> string {
  push_tallocator();

  utc_diff := getutc() - oldutc;

  builder: String_Builder;

  // perf: could do some compile time stuff here?
  for (struct {label: string; seconds: int;}).[
    .{"years",   60*60*24*7*52},
    .{"weeks",   60*60*24*7},
    .{"days",    60*60*24},
    .{"hours",   60*60},
    .{"mins",    60},
    // .{"secs",    1},
  ] {
    count := utc_diff / it.seconds;
    if count {
      label := it.label;
      if count == 1 then label.count -= 1;
      print_to_builder(*builder, "% % ", count, label);
      utc_diff -= count*it.seconds;
    }
  }

  str := builder_to_string(*builder);
  if !str.count then return tprint("% secs ago", utc_diff);
  str = tprint("%ago", str);
  return str;
}


#import "lz4";
compress :: (str: string) -> string {
  compressed := talloc_string(str.count + 1024*10/*some extra space incase the compressed version is bigger? perf: i think i only need + 1 extra byte here*/);
  // nvm this actually started crashing with str.count + 1024, i needed to put 1024*10 to stop the crash when copying an image

  bytes_written := LZ4_compress_default(str.data , compressed.data, xx str.count, xx compressed.count);
  if bytes_written <= 0  die("compress error");
  compressed.count = bytes_written;
  return compressed;
}
// decompress is one of the most common reasons this app crashes.
// either because we didn't allocate enough bytes, or because we're decompressing an empty string
// so now this function deals with those cases
decompress_high_watermark := 1024 * 1024;
decompress :: (compressed: string) -> string {
  if(compressed == "") return "";

  decompressed := talloc_string(decompress_high_watermark);
  bytes_written := LZ4_decompress_safe(compressed.data, decompressed.data, xx compressed.count, xx decompressed.count);

  if bytes_written <= 0 {
    // error. we probably didn't allocate enough space. let's allocate more and try again
    // it's possible the compressed string is corrupt? in that case we'd allocate more and more until we crash ...
    decompress_high_watermark *= 2;
    return decompress(compressed);
  }

  decompressed.count = bytes_written;
  return decompressed;
}


// register hotkey using a string like alt+shift+1 instead of vk key codes
myregisterhotkey :: (hwnd: HWND, id: s32, hotkeystring: string) -> bool {
  Strings.to_lower(*hotkeystring);

  parts := split(hotkeystring, "+");
  mod_parts := parts; mod_parts.count -= 1; // ["alt", "shift"]
  hotkey_part := parts[parts.count-1]; // "1"

  // parse the hotkey_mod
  hotkey_mod: u32 = MOD_NOREPEAT;
  for part: mod_parts {
    if part[0] == {
      case #char "c"; hotkey_mod |= MOD_CONTROL;
      case #char "a"; hotkey_mod |= MOD_ALT;
      case #char "s"; hotkey_mod |= MOD_SHIFT;
      case #char "w"; hotkey_mod |= MOD_WIN;
    }
  }

  // parse the hotkey_vk
  hotkey_vk := string_to_vk(hotkey_part);

  return xx RegisterHotKey(hwnd, id, hotkey_mod, hotkey_vk);
}

// wish there was a better way to do this ...
string_to_vk :: (str: string) -> VK: u32 {

  Strings.to_lower(*str);

  if str == {
    case "tab"            ; return VK_TAB;
    case "clear"          ; return VK_CLEAR;
    case "return"         ; return VK_RETURN;
    case "enter"          ; return VK_RETURN;
    case "shift"          ; return VK_SHIFT;
    case "control"        ; return VK_CONTROL;
    case "menu"           ; return VK_MENU;
    case "pause"          ; return VK_PAUSE;
    case "capital"        ; return VK_CAPITAL;
    case "caps"           ; return VK_CAPITAL;
    case "capslock"       ; return VK_CAPITAL;
    case "kana"           ; return VK_KANA;
    case "hangul"         ; return VK_HANGUL;
    case "junja"          ; return VK_JUNJA;
    case "final"          ; return VK_FINAL;
    case "hanja"          ; return VK_HANJA;
    case "kanji"          ; return VK_KANJI;
    case "escape"         ; return VK_ESCAPE;
    case "esc"            ; return VK_ESCAPE;
    case "convert"        ; return VK_CONVERT;
    case "nonconvert"     ; return VK_NONCONVERT;
    case "accept"         ; return VK_ACCEPT;
    case "modechange"     ; return VK_MODECHANGE;
    case "space"          ; return VK_SPACE;
    case "prior"          ; return VK_PRIOR;
    case "next"           ; return VK_NEXT;
    case "end"            ; return VK_END;
    case "home"           ; return VK_HOME;
    case "left"           ; return VK_LEFT;
    case "up"             ; return VK_UP;
    case "right"          ; return VK_RIGHT;
    case "down"           ; return VK_DOWN;
    case "select"         ; return VK_SELECT;
    case "print"          ; return VK_PRINT;
    case "execute"        ; return VK_EXECUTE;
    case "snapshot"       ; return VK_SNAPSHOT;
    case "insert"         ; return VK_INSERT;
    case "delete"         ; return VK_DELETE;
    case "del"            ; return VK_DELETE;
    case "help"           ; return VK_HELP;

    case "lwin"           ; return VK_LWIN;
    case "rwin"           ; return VK_RWIN;
    case "apps"           ; return VK_APPS;
    case "sleep"          ; return VK_SLEEP;
    case "numpad0"        ; return VK_NUMPAD0;
    case "numpad1"        ; return VK_NUMPAD1;
    case "numpad2"        ; return VK_NUMPAD2;
    case "numpad3"        ; return VK_NUMPAD3;
    case "numpad4"        ; return VK_NUMPAD4;
    case "numpad5"        ; return VK_NUMPAD5;
    case "numpad6"        ; return VK_NUMPAD6;
    case "numpad7"        ; return VK_NUMPAD7;
    case "numpad8"        ; return VK_NUMPAD8;
    case "numpad9"        ; return VK_NUMPAD9;
    case "num0"           ; return VK_NUMPAD0;
    case "num1"           ; return VK_NUMPAD1;
    case "num2"           ; return VK_NUMPAD2;
    case "num3"           ; return VK_NUMPAD3;
    case "num4"           ; return VK_NUMPAD4;
    case "num5"           ; return VK_NUMPAD5;
    case "num6"           ; return VK_NUMPAD6;
    case "num7"           ; return VK_NUMPAD7;
    case "num8"           ; return VK_NUMPAD8;
    case "num9"           ; return VK_NUMPAD9;
    case "multiply"       ; return VK_MULTIPLY;
    case "add"            ; return VK_ADD;
    case "separator"      ; return VK_SEPARATOR;
    case "subtract"       ; return VK_SUBTRACT;
    case "decimal"        ; return VK_DECIMAL;
    case "divide"         ; return VK_DIVIDE;
    case "f1"             ; return VK_F1;
    case "f2"             ; return VK_F2;
    case "f3"             ; return VK_F3;
    case "f4"             ; return VK_F4;
    case "f5"             ; return VK_F5;
    case "f6"             ; return VK_F6;
    case "f7"             ; return VK_F7;
    case "f8"             ; return VK_F8;
    case "f9"             ; return VK_F9;
    case "f10"            ; return VK_F10;
    case "f11"            ; return VK_F11;
    case "f12"            ; return VK_F12;
    case "f13"            ; return VK_F13;
    case "f14"            ; return VK_F14;
    case "f15"            ; return VK_F15;
    case "f16"            ; return VK_F16;
    case "f17"            ; return VK_F17;
    case "f18"            ; return VK_F18;
    case "f19"            ; return VK_F19;
    case "f20"            ; return VK_F20;
    case "f21"            ; return VK_F21;
    case "f22"            ; return VK_F22;
    case "f23"            ; return VK_F23;
    case "f24"            ; return VK_F24;
    case "numlock"        ; return VK_NUMLOCK;
    case "scroll"         ; return VK_SCROLL;
    case "scrolllock"     ; return VK_SCROLL;
    case "oem_nec_equal"  ; return VK_OEM_NEC_EQUAL;
    case "oem_fj_jisho"   ; return VK_OEM_FJ_JISHO;
    case "oem_fj_masshou" ; return VK_OEM_FJ_MASSHOU;
    case "oem_fj_touroku" ; return VK_OEM_FJ_TOUROKU;
    case "oem_fj_loya"    ; return VK_OEM_FJ_LOYA;
    case "oem_fj_roya"    ; return VK_OEM_FJ_ROYA;
    case "lshift"         ; return VK_LSHIFT;
    case "rshift"         ; return VK_RSHIFT;
    case "lcontrol"       ; return VK_LCONTROL;
    case "rcontrol"       ; return VK_RCONTROL;
    case "lmenu"          ; return VK_LMENU;
    case "rmenu"          ; return VK_RMENU;
    case "browser_back"        ; return VK_BROWSER_BACK;
    case "browser_forward"     ; return VK_BROWSER_FORWARD;
    case "browser_refresh"     ; return VK_BROWSER_REFRESH;
    case "browser_stop"        ; return VK_BROWSER_STOP;
    case "browser_search"      ; return VK_BROWSER_SEARCH;
    case "browser_favorites"   ; return VK_BROWSER_FAVORITES;
    case "browser_home"        ; return VK_BROWSER_HOME;
    case "volume_mute"         ; return VK_VOLUME_MUTE;
    case "volume_down"         ; return VK_VOLUME_DOWN;
    case "volume_up"           ; return VK_VOLUME_UP;
    case "media_next_track"    ; return VK_MEDIA_NEXT_TRACK;
    case "media_prev_track"    ; return VK_MEDIA_PREV_TRACK;
    case "media_stop"          ; return VK_MEDIA_STOP;
    case "media_play_pause"    ; return VK_MEDIA_PLAY_PAUSE;
    case "launch_mail"         ; return VK_LAUNCH_MAIL;
    case "launch_media_select" ; return VK_LAUNCH_MEDIA_SELECT;
    case "launch_app1"         ; return VK_LAUNCH_APP1;
    case "launch_app2"         ; return VK_LAUNCH_APP2;
    case "oem_1"          ; return VK_OEM_1;
    case "oem_plus"       ; return VK_OEM_PLUS;
    case "oem_comma"      ; return VK_OEM_COMMA;
    case "oem_minus"      ; return VK_OEM_MINUS;
    case "oem_period"     ; return VK_OEM_PERIOD;
    case "oem_2"          ; return VK_OEM_2;
    case "oem_3"          ; return VK_OEM_3;
    case "oem_4"          ; return VK_OEM_4;
    case "oem_5"          ; return VK_OEM_5;
    case "oem_6"          ; return VK_OEM_6;
    case "oem_7"          ; return VK_OEM_7;
    case "oem_8"          ; return VK_OEM_8;
    case "oem_ax"         ; return VK_OEM_AX;
    case "oem_102"        ; return VK_OEM_102;
    case "ico_help"       ; return VK_ICO_HELP;
    case "ico_00"         ; return VK_ICO_00;
    case "processkey"     ; return VK_PROCESSKEY;
    case "ico_clear"      ; return VK_ICO_CLEAR;
    case "packet"         ; return VK_PACKET;
  }

  return VkKeyScanA(str[0]);
}


save_bitmap_to_file :: (bitmapinfobytes: string, filepath: string) -> bool {

  stbi   :: #import "stb_image_write";
  String :: #import "String";
  Simp   :: #import "Simp";

  bitmap: Simp.Bitmap;
  // Simp.bitmap_load_from_memory(*bitmap, xx bitmapinfobytes);
  bitmap_header: *BITMAPINFOHEADER = xx bitmapinfobytes.data;
  bitmap.width = bitmap_header.biWidth;
  bitmap.height = bitmap_header.biHeight;
  if bitmap_header.biBitCount == 24 then bitmap.format = .RGB8; else bitmap.format = .BGRA8;
  _size, _stride := Simp.get_image_size(bitmap.format, bitmap.width, bitmap.height);
  bitmap.stride = xx _stride;
  bitmap.data.count = _size;
  bitmap.data.data = bitmapinfobytes.data + size_of(BITMAPINFOHEADER);
  if bitmap_header.biCompression == BI_BITFIELDS then bitmap.data.data += 3 * 4/*bytes*/;

  // doesn't support bgr
  // Simp.bitmap_save(*bitmap, filepath);

  stride := bitmap.stride;
  data   := bitmap.data.data;

  components : s32 = 4;
  if bitmap.format == .RGB8 components = 3;

  // change format from .BGRA8 to .RGBA8
  // wtf??? this is so weird.
  for i: 0 .. bitmap.width*bitmap.height-1 {
    swap(*bitmap.data[i*components+0], *bitmap.data[i*components+2]);
  }


  name      := temp_c_string(filepath);
  extension := String.path_extension(filepath);

  stbi.stbi_flip_vertically_on_write(1); // image was being saved upside down. again wtf????
  if extension == {
    case "png";
      return stbi.stbi_write_png(name, bitmap.width, bitmap.height, components, data, stride) != 0;
    case "tga";
      return stbi.stbi_write_tga(name, bitmap.width, bitmap.height, components, data) != 0;
    case "bmp";
      return stbi.stbi_write_bmp(name, bitmap.width, bitmap.height, components, data) != 0;
    case "jpg";
      return stbi.stbi_write_jpg(name, bitmap.width, bitmap.height, components, data, quality=80) != 0;
    case;
      mylog("Bitmap extension", extension, "is not understood by this code.");
      return false;
  }
}










add_to_startup :: ($app_name: string, app_path: string) -> bool {
  hKey: HKEY;
  result: LONG;

  // Open the run key
  run_key :: "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run";
  result = RegOpenKeyExA(HKEY_CURRENT_USER, run_key, 0, KEY_ALL_ACCESS, *hKey);
  if result != ERROR_SUCCESS {
    log_error("Error opening registry key\n");
    return false;
  }
  defer RegCloseKey(hKey);

  // Set the value
  app_path_with_backslash := replace(app_path, "/", "\\");
  app_path_with_backslash = tprint("\"%\"", app_path_with_backslash);
  result = RegSetValueExA(hKey, app_name, 0, REG_SZ, cast(LPBYTE) to_c_string(app_path_with_backslash,, allocator=temp), cast(DWORD)(app_path_with_backslash.count));
  if result != ERROR_SUCCESS {
    log_error("Error setting registry value\n");
    return false;
  }

  log("Added to startup successfully\n");
  return true;
}


remove_from_startup :: ($app_name: string) -> bool {
  hKey: HKEY;
  result: LONG;

  // Open the run key
  run_key :: "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run";
  result = RegOpenKeyExA(HKEY_CURRENT_USER, run_key, 0, KEY_ALL_ACCESS, *hKey);
  if result != ERROR_SUCCESS {
    log_error("Error opening registry key\n");
    return false;
  }
  defer RegCloseKey(hKey);

  // Delete the value
  result = RegDeleteValueA(hKey, app_name);
  if result != ERROR_SUCCESS {
    log_error("Error deleting registry value\n");
    return false;
  }

  log("Removed from startup successfully\n");
  return true;
}



is_set_to_run_on_startup :: ($app_name: string) -> bool {
  hKey: HKEY;
  result: LONG;
  buffer: [MAX_PATH]u8;
  buffer_size: DWORD = MAX_PATH;
  value_type: DWORD;

  run_key :: "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run";
  result = RegOpenKeyExA(HKEY_CURRENT_USER, run_key, 0, KEY_READ, *hKey);
  if result != ERROR_SUCCESS {
    log_error("Error opening registry key\n");
    return false;
  }
  defer RegCloseKey(hKey);

  result = RegQueryValueExA(hKey, app_name, null, *value_type, cast(LPBYTE)buffer.data, *buffer_size);
  if result == ERROR_SUCCESS && value_type == REG_SZ {
    print("Application is set to run on startup\n");
    print("Startup command: %\n", to_string(buffer.data, buffer_size));
    return true;
  } else if result == ERROR_FILE_NOT_FOUND {
    print("Application is not set to run on startup\n");
    return false;
  } else {
    print("Error querying registry value\n");
    return false;
  }
}
