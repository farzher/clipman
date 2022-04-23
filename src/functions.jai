// i really don't like how #load works.
// there's no encapsulation
// i don't know what come from where or why, it's quite a mess
// i don't like the concept of prefixing every name


Mouse: struct {

  Point :: struct {x: s32; y: s32;}

  pos :: () -> Point {
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



Monitor: struct {

  _size: struct {x, y, w, h :s32;};
  size :: () -> type_of(_size) { ensure_init(); return Monitor._size; }

  init :: () {
    info: MONITORINFO = ---;
    info.cbSize = size_of(type_of(info));
    success := GetMonitorInfoW(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), *info);
    if !success  die("failed to get monitor size");

    Monitor._size.x = info.rcMonitor.left;
    Monitor._size.y = info.rcMonitor.top;
    Monitor._size.w = info.rcMonitor.right - Monitor._size.x;
    Monitor._size.h = info.rcMonitor.bottom - Monitor._size.y;
  }

  ensure_init :: () {
    if Monitor._size.w != 0  return;
    Monitor.init();
  }
}





set_window_pos_to_mouse :: (hwnd: HWND) {
  mouse := Mouse.pos_global();

  x := mouse.x;
  too_far_left_amount := cast(s32)( x + window_width - Monitor.size().w );
  if too_far_left_amount > 0 then x -= too_far_left_amount;

  y := mouse.y;
  too_far_down_amount := cast(s32)( y + window_height - Monitor.size().h );
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





#import "lz4-1.9.1";
compress :: (str: string) -> string {
  compressed := talloc_string(str.count + 1024/*some extra space incase the compressed version is bigger? perf: i think i only need + 1 extra byte here*/);
  bytes_written := LZ4_compress_default(str.data , compressed.data, xx str.count, xx compressed.count);
  if bytes_written <= 0  die("compress error");
  compressed.count = bytes_written;
  return compressed;
}
decompress :: (compressed: string) -> string {
  decompressed := talloc_string(1024 * 1024 * 50 /*50mb is the max we can decompress. 4k monitor screenshots are like 32MB*/);
  bytes_written := LZ4_decompress_safe(compressed.data, decompressed.data, xx compressed.count, xx decompressed.count);
  if bytes_written <= 0  die("decompress error");
  decompressed.count = bytes_written;
  return decompressed;
}



TextureCache: struct {
  #import "my_lru_cache";

  texture_cache: LRU(int, Simp.Texture, MAX_RECORDS, FREE_PROC=texture_free);

  MAX_RECORDS :: 100; // a guess at the maximum amount of records that could ever be displayed. if we display more than this bad things could happen

  // simp's implementation "deinit" doesn't actually free the memory currently, lol.
  texture_free :: (texture: *Simp.Texture) {
    #import "GL";
    glDeleteTextures(1, *texture.gl_handle);
  }

  get_texture_for_record :: (record: DbRecord) -> *Simp.Texture {
    if record.type != .BITMAP then return null;

    textureptr := find_pointer(TextureCache.texture_cache, record.id);
    if textureptr then return textureptr;

    texture: Simp.Texture;
    bitmap: Simp.Bitmap;
    bitmapinfobytes := decompress(record.preview);
    bmpinfo: *BITMAPINFO = xx bitmapinfobytes.data;
    bitmap.width = bmpinfo.bmiHeader.biWidth;
    bitmap.height = bmpinfo.bmiHeader.biHeight;
    bitmap.data.data = bitmapinfobytes.data + size_of(BITMAPINFO); // is this actually correct?
    bitmap.stride = 4;

    success := Simp.texture_load_from_bitmap(*texture, *bitmap);
    if !success  die("failed to load texture", record.id);

    return add(*TextureCache.texture_cache, record.id, texture);
  }
}




search_input: GetRect.Text_Input;
search_string: *string;

GetRect :: #import "GetRect";
init_search_string :: () {
  search_input.active = true;
  search_string = *search_input.text;
}
update_search_string :: () {
  selected_index = 0;
  scroll_offset = 0;
}








my_font: *Simp.Dynamic_Font;
my_big_font: *Simp.Dynamic_Font;
my_tiny_font: *Simp.Dynamic_Font;
init_font :: () {
  // my_font = Simp.get_font_at_size("./", "Anonymous Pro B.ttf", 18);
  my_font = Simp.get_font_at_size("./", "OpenSans-BoldItalic.ttf", 18);
  assert(my_font != null);

  my_big_font = Simp.get_font_at_size("./", "OpenSans-BoldItalic.ttf", 32);
  assert(my_big_font != null);

  my_tiny_font = Simp.get_font_at_size("./", "OpenSans-BoldItalic.ttf", 12);
  assert(my_tiny_font != null);
}



show_window :: (_visible := true) {
  visible = _visible;
  ShowWindow(hwnd, xx ifx visible then SW_SHOW else SW_HIDE);
  if !visible then Simp.swap_buffers(hwnd); // ensure streamer mode doesn't render old information
  if visible then  SetForegroundWindow(hwnd); // ensure window has focus
  if visible then is_streamer_mode = xx config.streamer_mode;
}





multiselecting :: inline () -> bool {return selected_index_end != -1;}
multiselecting :: inline (v: bool, index:=-1) {
  if(v) {
    if !multiselecting() then selected_index_end = ifx index==-1 then selected_index else index;
  } else {
    selected_index_end = -1;
  }
}
isselected :: inline (i: int) -> bool {
  imin, imax := selected_range();
  return i >= imin && i <= imax;
}
selected_range :: () -> min: int, max: int {
  if !multiselecting() return selected_index, selected_index;
  return min(selected_index, selected_index_end), max(selected_index, selected_index_end);
}

selected_expansion: struct {};
for_expansion :: (_: *type_of(selected_expansion), body: Code, flags: For_Flags) #expand {
  imin, imax := selected_range();
  for `it_index: 0 .. imax-imin {
    `it := imin+it_index;
    #insert body;
  }
}





// colorref: COLORREF;
//   colorref |= ( cast(COLORREF) (COLORS.DARK.x*0xFF)) << 0;
//   colorref |= ( cast(COLORREF) (COLORS.DARK.y*0xFF)) << 8;
//   colorref |= ( cast(COLORREF) (COLORS.DARK.z*0xFF)) << 16;
// colorref : COLORREF : 0xFF000000;
colorref : COLORREF : 0x00000000;
// colorref : COLORREF : 0x00ff00ff;
old_trans: u8;
m: MARGINS = .{-1, -1, -1, -1};
update_window_transparency :: (can_be_transparent: bool) {
  new_trans: u8 = xx ifx can_be_transparent then ( (cast(float)config.transparency) /100)*255 else 1*255;
  if new_trans != old_trans {
    old_trans = new_trans;

    SetLayeredWindowAttributes(hwnd, colorref, new_trans, LWA_ALPHA /*|LWA_COLORKEY*/);


    // DwmExtendFrameIntoClientArea(hwnd, *m);

    // bb: DWM_BLURBEHIND;
    // bb.dwFlags = DWM_BB_ENABLE;
    // bb.fEnable = .TRUE;
    // bb.hRgnBlur = null;
    // DwmEnableBlurBehindWindow(hwnd, *bb);
  }

}



MAKEINTRESOURCEW :: (i: u32) -> *u16 { return cast(*u16)i; }
WMAPP_NOTIFYCALLBACK :: WM_APP + 1;
trayicon_create :: (tooltip: string) {
  nid: NOTIFYICONDATA;
  nid.hWnd = hwnd;
  nid.uFlags = NIF_ICON | NIF_TIP | NIF_MESSAGE | NIF_SHOWTIP;
  nid.uCallbackMessage = WMAPP_NOTIFYCALLBACK;
  nid.hIcon = LoadIconW(GetModuleHandleW(null), MAKEINTRESOURCEW(2));

  memcpy(*nid.szTip, tooltip.data, tooltip.count);
  Shell_NotifyIconA(NIM_ADD, *nid);

  // NOTIFYICON_VERSION_4 is prefered
  NOTIFYICON_VERSION_4 :: 4;
  nid.uVersion = NOTIFYICON_VERSION_4;
  Shell_NotifyIconA(NIM_SETVERSION, *nid);
}





popup_menu :: (items: []string) -> string {
  hpop := CreatePopupMenu();
  for item, item_i: items {
    InsertMenuW(hpop, 0, MF_BYPOSITION | MF_STRING, xx (item_i+1), utf8_to_wide(item));
  }
  SetForegroundWindow(hwnd);
  mouse_global := Mouse.pos_global();
  selection : int = xx TrackPopupMenu(hpop, TPM_BOTTOMALIGN | TPM_LEFTALIGN |TPM_RETURNCMD, mouse_global.x, mouse_global.y, 0, hwnd, null);
  if selection == 0 then return "";
  return items[selection-1];
}




showinputbox :: (title: *u8, message: *u8) -> *u8 {
  // DialogBoxParamW :: (hInstance: HINSTANCE, lpTemplate: LPCWSTR, hWndParent: HWND, lpDialogFunc: *void, dwInitParam: LPARAM) -> s32 #foreign user32;
  tinyfd :: #foreign_library,no_dll "tinyfiledialogs64";
  tinyfd_inputBox :: (title: *u8, message: *u8, defaultinput: *u8) -> *u8 #foreign tinyfd;

  // memory leak?
  return tinyfd_inputBox(title, message, null);
}



// last_index wasn't working for some reason...
mylastindex :: (str: string, char: u8) -> int {
  i := str.count-1;
  while i >= 0 {
    if str[i] == char return i;
    i -= 1;
  }
  return -1;
}
