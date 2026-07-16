


// this file is a mess, idk


Clipman_Event_Type :: enum u32 {
  KEYBOARD    :: cast(u32) Event_Type.KEYBOARD;
  MOUSE_WHEEL :: cast(u32) Event_Type.MOUSE_WHEEL;
  QUIT        :: cast(u32) Event_Type.QUIT;

  CLIP_COPY :: 0x8000_0000;
  FOCUS_LOST;
  HOTKEY;
  MY_TRAY;
}

queue_clipman_event :: (type: Clipman_Event_Type, code: u32 = 0) {
  event: Event;
  event.type  = cast,no_check(Event_Type) type;
  event.utf32 = code; // Payload for custom events; tray messages use this.
  array_add(*events_this_frame, event);
}

clipman_window_proc :: (window: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) -> s64 #c_call {
  push_context {
    if message == {
      case WM_CLIPBOARDUPDATE;   queue_clipman_event(.CLIP_COPY); return 0;
      case WM_HOTKEY;            queue_clipman_event(.HOTKEY);    return 0;
      case WMAPP_NOTIFYCALLBACK; queue_clipman_event(.MY_TRAY, xx lparam); return 0;
      case WM_KILLFOCUS;         queue_clipman_event(.FOCUS_LOST);
      case WM_PAINT;             render_dirty_info.new_event = true;
    }
    return MyWindowProc(window, message, wparam, lparam);
  }
}


// Remote preview downloads live here only until the main thread uploads them
// into TextureCache. Limiting the queue also bounds responses held while hidden.
request_q: struct {
  #import "Hash_Table";
  #import "Thread";

  MAX_PENDING :: 12;

  request_cache : Table(int, *Request);
  thread_group  : Thread_Group;
  inited        := false;

  Request :: struct {
    record_id : int;
    url       : string;
    response  : string;
  }

  start :: (record_id: int, url: string) {
    ensure_init();

    found, req := table_find(*request_q.request_cache, record_id);
    if found || request_q.request_cache.count >= MAX_PENDING return;

    req = New(Request);
    req.record_id = record_id;
    req.url = copy_string(url); // url may be in temporary storage
    table_add(*request_q.request_cache, record_id, req);
    add_work(*request_q.thread_group, req);
  }

  free :: (req: *Request) {
    table_remove(*request_q.request_cache, req.record_id);
    free(req.url);
    if req.response free(req.response);
    free(cast(*void)req); // cast so we call Basic.free, not this procedure
  }

  take_completed :: () -> [] *Request {
    return cast,force([] *Request) get_completed_work(*request_q.thread_group);
  }

  ensure_init :: () {
    if request_q.inited return; request_q.inited = true;

    request_q.thread_group.name = "request_q.thread_group";
    request_q.thread_group.logging = false;
    init(*request_q.thread_group, MAX_PENDING, request_q.thread_do_work);
    start(*request_q.thread_group);
  }

  thread_do_work :: (group: *Thread_Group, thread: *Thread, work: *void) -> Thread_Continue_Status {
    req := cast(*Request)work;
    req.response = request(req.url, timeout_seconds=2);
    return .CONTINUE;
  }
}

// TextureCache owns up to MAX_RECORDS GPU textures while the window is open.
// Eviction deletes the GL handle, and show_window(false) empties the whole cache.
TextureCache: struct {
  #import,file "modules/my_lru_cache.jai";

  MAX_RECORDS :: 100; // a guess at the maximum amount of records that could ever be displayed. if we display more than this bad things could happen
  texture_cache: LRU(int, Simp.Texture, MAX_RECORDS, FREE_PROC=Simp.texture_destroy);

  upload_completed_requests :: () -> bool {
    completed := request_q.take_completed();

    for req: completed {
      defer request_q.free(req);

      if req.response {
        auto_release_temp();
        texture: Simp.Texture;
        if Simp.texture_load_from_memory(*texture, xx req.response) {
          add(*TextureCache.texture_cache, req.record_id, texture);
        }
      }
    }

    return completed.count > 0;
  }

  get_texture_for_record :: (record: DbRecord) -> *Simp.Texture {

    // guard against non-image records
    can_fetch_img_from_record_text := can_fetch_img_from_text(record.preview);
    if !is_image(record) && !can_fetch_img_from_record_text then return null;

    // if the texture is already in the cache return it
    cached_texture := find_pointer(TextureCache.texture_cache, record.id);
    if cached_texture then return cached_texture;

    // text that can render as an image, go fetch the image
    if can_fetch_img_from_record_text {
      request_q.start(record.id, get_img_url_from_text(record.preview));
      return null;
    }

    // upload image from db to gpu
    if is_image(record) {
      // Release full-size decode buffers after this upload.
      auto_release_temp();
      bitmap := windows_bitmap_to_simp_bitmap(record_to_windows_bitmap(record));
      texture: Simp.Texture;
      Simp.texture_load_from_bitmap(*texture, *bitmap);
      return add(*TextureCache.texture_cache, record.id, texture);
    }

    assert(false); return null; // not all control paths return a value;
  }
}

is_image :: (record: DbRecord) -> bool { return record.type == .BITMAP || record.type == .WEBP; }
render_record_image :: (record: DbRecord, x: float, y: float, max_w: float, max_h: float) {
  texture := TextureCache.get_texture_for_record(record);
  if !texture return;

  ratio := min(max_w/texture.width, max_h/texture.height);
  w := texture.width * ratio;
  h := texture.height * ratio;

  Simp.set_shader_for_images(texture);
  Simp.immediate_quad(x, y-h, x + w, y, COLORS.WHITE);
}


can_fetch_img_from_text :: (str: string) -> bool { return is_imgur_url(str) || is_youtube_url(str) || is_twitch_url(str); }
get_img_url_from_text :: (str: string) -> string {
  if is_imgur_url(str)   return str;
  if is_youtube_url(str) return interp("https://img.youtube.com/vi/%{youtube_videoid_from_url(str)}/0.jpg");
  if is_twitch_url(str)  return interp("https://static-cdn.jtvnw.net/previews-ttv/live_user_%{twitch_username_from_url(str)}-0x0.jpg");
  return "";
}

is_imgur_url :: (str: string) -> bool {
  // https://i.imgur.com/IMGID.png
  // http://i.imgur.com/IMGID.jpg

  if obviously_not_a_url(str) return false;

  starts_correctly := Strings.starts_with(str, "https://i.imgur.com/")
                   || Strings.starts_with(str, "http://i.imgur.com/");
  return starts_correctly && (Strings.ends_with(str, ".png")
                           || Strings.ends_with(str, ".jpg")
                           || Strings.ends_with(str, ".jpeg"));
}

is_youtube_url :: (str: string) -> bool {
  // https://www.youtube.com/watch?v=VIDEOID
  // https://youtu.be/VIDEOID?t=7967
  // https://www.youtube.com/shorts/OSTLiIh6FQg
  // https://www.youtube.com/live/LtOiwjNsB0U

  if obviously_not_a_url(str) return false;

  return Strings.starts_with(str, "https://youtube.com/watch?v=")
      || Strings.starts_with(str, "https://www.youtube.com/watch?v=")
      || Strings.starts_with(str, "https://youtu.be/")
      || Strings.starts_with(str, "https://www.youtu.be/")
      || Strings.starts_with(str, "https://youtube.com/shorts/")
      || Strings.starts_with(str, "https://www.youtube.com/shorts/")
      || Strings.starts_with(str, "https://youtube.com/live/")
      || Strings.starts_with(str, "https://www.youtube.com/live/");
}

is_twitch_url :: (str: string) -> bool {
  if obviously_not_a_url(str) return false;
  return Strings.contains(str, "twitch.tv/");
}
twitch_username_from_url :: (str: string) -> string {
  username := ghetto_regex_capture(str, "twitch.tv/", is_alnum);
  Strings.to_lower(*username);
  return username;
}

obviously_not_a_url :: (str: string) -> bool {
  return str.count > 10_000 || Strings.contains(str, "\n");
}

youtube_videoid_from_url :: (str: string) -> string {
  if !is_youtube_url(str) return "";
  for prefix: string.["youtube.com/watch?v=", "youtu.be/", "youtube.com/shorts/", "youtube.com/live/"] {
    video_id := ghetto_regex_capture(str, prefix, is_alnum);
    if video_id return video_id;
  }
  return "";
}

ghetto_regex_capture :: (str: string, begin: string, is_matching_fn: (u8)->bool) -> string {
  index := Strings.first_index(str, begin);
  if index == -1 return "";
  index += begin.count;

  end_index: int = index;
  while end_index < str.count { defer end_index += 1;
    if !is_matching_fn(str[end_index]) { end_index -= 1; break; }
  }
  if !end_index return "";

  return Strings.substring(str, index, end_index - index);
}

censor :: (str: string) -> string {
  censored := talloc_string(str.count);
  memset(censored.data, #char"*", censored.count);
  return censored;
}
maybe_censor :: (str: string) -> string {
  return ifx is_streamer_mode || is_db_locked censor(str) else str;
}

my_font      : *Simp.Dynamic_Font;
my_big_font  : *Simp.Dynamic_Font;
my_tiny_font : *Simp.Dynamic_Font;
load_clipman_font :: (pixel_height: int) -> *Simp.Dynamic_Font {
  font: *Simp.Dynamic_Font;
  if !font  font = Simp.get_font_at_size("C:/Windows/Fonts", "verdanaz.ttf", pixel_height);
  if !font  font = Simp.get_font_at_size(".", "OpenSans-BoldItalic.ttf", pixel_height);
  if !font  font = Simp.get_font_at_size("C:/Windows/Fonts", "consolab.ttf", pixel_height);
  if !font  font = Simp.get_font_at_size("C:/Windows/Fonts", "segoeuiz.ttf", pixel_height);
  if !font  font = Simp.get_font_at_size("C:/Windows/Fonts", "segoeui.ttf", pixel_height);
  if !font  font = Simp.get_font_at_size("C:/Windows/Fonts", "arial.ttf", pixel_height);
  if !font  font = Simp.get_font_at_size("C:/Windows/Fonts", "tahoma.ttf", pixel_height);
  if !font  font = Simp.get_font_at_size("C:/Windows/Fonts", "verdana.ttf", pixel_height);

  assert(font != null, "Unable to load a font from C:/Windows/Fonts or OpenSans-BoldItalic.ttf.");
  return font;
}
init_font :: () {
  // Simp's default 2048x1024 RGBA atlas reserves 8 MB in both RAM and GPU
  // memory. This grows additional pages as needed, so start at a saner size.
  Simp.init_fonts(1024, 512);

  my_font      = load_clipman_font(18);
  my_big_font  = load_clipman_font(32);
  my_tiny_font = load_clipman_font(12);
}


scrub_window_buffers :: () {
  Simp.set_render_target(hwnd);
  Simp.clear_render_target(COLORS.DARK.x, COLORS.DARK.y, COLORS.DARK.z, 0);
  Simp.swap_buffers(hwnd);
  Simp.clear_render_target(COLORS.DARK.x, COLORS.DARK.y, COLORS.DARK.z, 0);
}

show_window :: (show := true) {
  if show {

    if visible { // already visible, just focus
      SetForegroundWindow(hwnd);
      return;
    }
    visible = true;

    init_ui();
    is_streamer_mode = xx config.streamer_mode;
    update_records();

    // Render at zero alpha so DWM never presents the previous frame.
    SetLayeredWindowAttributes(hwnd, 0, 0, LWA_ALPHA);
    ShowWindow(hwnd, SW_SHOW);
    DwmFlush();
    render_dirty_info.new_event = true;
    render();
    SetLayeredWindowAttributes(hwnd, 0, window_alpha, LWA_ALPHA);

    SetForegroundWindow(hwnd);
  }

  if !show {

    if !visible return;
    visible = false;

    SetLayeredWindowAttributes(hwnd, 0, 0, LWA_ALPHA);
    ShowWindow(hwnd, SW_HIDE);
    scrub_window_buffers();
    lru_free(*TextureCache.texture_cache);
  }
}

multiselecting :: inline () -> bool { return selected_index_end != -1; }
multiselecting :: inline (v: bool, index := -1) {
  if v {
    if !multiselecting() then selected_index_end = ifx index == -1 then selected_index else index;
  } else {
    selected_index_end = -1;
  }
}
is_selected :: inline (i: int) -> bool {
  imin, imax := selected_range();
  return i >= imin && i <= imax;
}
selected_range :: () -> min: int, max: int {
  if !multiselecting() return selected_index, selected_index;
  return min(selected_index, selected_index_end), max(selected_index, selected_index_end);
}
selected_count :: () -> int {
  min, max := selected_range();
  return max - min + 1;
}

selected_expansion: struct {};
for_expansion :: (_: *type_of(selected_expansion), body: Code, flags: For_Flags) #expand {
  imin, imax := selected_range();
  for `it_index: 0 .. imax-imin {
    `it := imin+it_index;
    #insert body;
  }
}

window_alpha: u8;
update_window_transparency :: (can_be_transparent: bool) {
  new_alpha: u8 = xx ifx can_be_transparent then cast(float)config.transparency/100*255 else 255;
  if new_alpha != window_alpha {
    window_alpha = new_alpha;
    // Stay at zero alpha during show_window's privacy-gated first render.
    if visible then SetLayeredWindowAttributes(hwnd, 0, new_alpha, LWA_ALPHA);
  }
}

MAKEINTRESOURCEW :: (i: u32) -> *u16 { return cast(*u16)i; }
WMAPP_NOTIFYCALLBACK :: WM_APP + 1;
trayicon_create :: (tooltip: string) {
  nid: NOTIFYICONDATA;
  nid.hWnd = hwnd;
  nid.uID    = 1;
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
trayicon_free :: () {
  nid: NOTIFYICONDATA;
  nid.hWnd   = hwnd;
  nid.uID    = 1;
  Shell_NotifyIconA(NIM_DELETE, *nid);
}

popup_menu :: (items: []string) -> string {
  hpop := CreatePopupMenu();
  CHECKED_PREFIX :: "[✓] ";
  for item, item_i: items {
    // if the item name starts with "[✓] " we will remove that from the name and add a real checkmark to the label
    is_checked := Strings.starts_with(item, CHECKED_PREFIX);
    is_checked_flag : u32 = xx ifx is_checked then MF_CHECKED else 0;
    label := ifx is_checked then String.slice(item, CHECKED_PREFIX.count, item.count - CHECKED_PREFIX.count) else item;

    InsertMenuW(hpop, 0, MF_BYPOSITION | MF_STRING | is_checked_flag, xx (item_i+1), utf8_to_wide(label,, allocator=temp));
  }
  SetForegroundWindow(hwnd);
  mouse_global := Mouse.pos_global();
  selection : int = xx TrackPopupMenu(hpop, TPM_BOTTOMALIGN | TPM_LEFTALIGN |TPM_RETURNCMD, mouse_global.x, mouse_global.y, 0, hwnd, null);
  if selection == 0 then return "";
  return items[selection-1];
}

inputbox_result_buffer: [4096]u8;
inputbox_accepted := false;
inputbox_hwnd     : HWND;
inputbox_edit     : HWND;

INPUTBOX_OK_ID     :: 1;
INPUTBOX_CANCEL_ID :: 2;

inputbox_accept :: () {
  GetWindowTextA(inputbox_edit, *inputbox_result_buffer[0], xx inputbox_result_buffer.count);
  inputbox_accepted = true;
  DestroyWindow(inputbox_hwnd);
}

inputbox_cancel :: () {
  inputbox_accepted = false;
  DestroyWindow(inputbox_hwnd);
}

inputbox_wndproc :: (wnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> s64 #c_call {
  push_context {
    if msg == WM_COMMAND {
      id := cast(u16)(wparam & 0xffff);
      if id == INPUTBOX_OK_ID {
        inputbox_accept();
        return 0;
      }
      if id == INPUTBOX_CANCEL_ID {
        inputbox_cancel();
        return 0;
      }
    }

    if msg == WM_CLOSE {
      inputbox_cancel();
      return 0;
    }

    return DefWindowProcW(wnd, msg, wparam, lparam);
  }
}

// Minimal native input popup.
// Returns null on cancel; otherwise returns a pointer to inputbox_result_buffer.
showinputbox :: (title: string, ispassword := true) -> *u8 {
  WS_EX_DLGMODALFRAME : u32 : 0x00000001;
  WS_EX_TOPMOST       : u32 : 0x00000008;
  WS_POPUP            : u32 : 0x80000000;
  WS_CAPTION          : u32 : 0x00C00000;
  WS_SYSMENU          : u32 : 0x00080000;
  WS_VISIBLE          : u32 : 0x10000000;
  WS_CHILD            : u32 : 0x40000000;
  WS_TABSTOP          : u32 : 0x00010000;
  ES_AUTOHSCROLL      : u32 : 0x0080;
  ES_PASSWORD         : u32 : 0x0020;
  BS_DEFPUSHBUTTON    : u32 : 0x00000001;
  WM_SETFONT          :: 0x0030;
  WM_KEYDOWN          :: 0x0100;
  VK_RETURN           :: 0x0D;
  VK_ESCAPE           :: 0x1B;
  SM_CXSCREEN         :: 0;
  SM_CYSCREEN         :: 1;
  IDC_ARROW           :: cast(*s16)32512;
  FW_NORMAL           :: 400;
  DEFAULT_CHARSET     :: 1;
  OUT_DEFAULT_PRECIS  :: 0;
  CLIP_DEFAULT_PRECIS :: 0;
  DEFAULT_QUALITY     :: 0;
  DEFAULT_PITCH       :: 0;

  inputbox_accepted = false;
  memset(*inputbox_result_buffer[0], 0, inputbox_result_buffer.count);

  hinstance := GetModuleHandleW(null);

  wc: WNDCLASSEXW;
  wc.cbSize = size_of(WNDCLASSEXW);
  wc.lpfnWndProc = xx inputbox_wndproc;
  wc.hInstance = hinstance;
  wc.hCursor = LoadCursorW(null, IDC_ARROW);
  wc.lpszClassName = utf8_to_wide("clipman_inputbox_window");
  RegisterClassExW(*wc);

  w: s32 = 360;
  h: s32 = 127;
  x := (GetSystemMetrics(SM_CXSCREEN) - w) / 2;
  y := (GetSystemMetrics(SM_CYSCREEN) - h) / 2;

  inputbox_hwnd = CreateWindowExW(WS_EX_DLGMODALFRAME | WS_EX_TOPMOST, wc.lpszClassName, utf8_to_wide(title), WS_POPUP | WS_CAPTION | WS_SYSMENU | WS_VISIBLE, x, y, w, h, hwnd, null, hinstance, null);
  if inputbox_hwnd == null return null;

  inputbox_edit = CreateWindowExW(0, utf8_to_wide("EDIT"), utf8_to_wide(""), WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_AUTOHSCROLL | (ifx ispassword then ES_PASSWORD else cast(u32)0), 12, 16, 320, 22, inputbox_hwnd, cast(HMENU)1001, hinstance, null);
  ok := CreateWindowExW(0, utf8_to_wide("BUTTON"), utf8_to_wide("OK"), WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON, 176, 52, 75, 24, inputbox_hwnd, cast(HMENU)INPUTBOX_OK_ID, hinstance, null);
  cancel := CreateWindowExW(0, utf8_to_wide("BUTTON"), utf8_to_wide("Cancel"), WS_CHILD | WS_VISIBLE | WS_TABSTOP, 257, 52, 75, 24, inputbox_hwnd, cast(HMENU)INPUTBOX_CANCEL_ID, hinstance, null);

  font := CreateFontW(-12, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH, utf8_to_wide("Segoe UI"));
  SendMessageW(inputbox_edit, WM_SETFONT, xx font, 1);
  SendMessageW(ok, WM_SETFONT, xx font, 1);
  SendMessageW(cancel, WM_SETFONT, xx font, 1);

  EnableWindow(hwnd, .FALSE);
  SetForegroundWindow(inputbox_hwnd);
  SetFocus(inputbox_edit);

  msg: MSG;
  while IsWindow(inputbox_hwnd) && GetMessageW(*msg, null, 0, 0) {
    if msg.message == WM_KEYDOWN {
      if msg.wParam == VK_RETURN {
        inputbox_accept();
        continue;
      }
      if msg.wParam == VK_ESCAPE {
        inputbox_cancel();
        continue;
      }
    }
    TranslateMessage(*msg);
    DispatchMessageW(*msg);
  }

  if IsWindow(hwnd) EnableWindow(hwnd, .TRUE);
  SetForegroundWindow(hwnd);

  if !inputbox_accepted return null;
  return *inputbox_result_buffer[0];
}

// Convert raw CF_DIB clipboard bytes to a Simp bitmap.
windows_bitmap_to_simp_bitmap :: (cf_dib: string) -> Simp.Bitmap {
  if cf_dib.count < size_of(BITMAPINFOHEADER) return .{};

  header := cast(*BITMAPINFOHEADER) cf_dib.data;

  width  := header.biWidth;
  height := header.biHeight;
  is_bottom_up := true;

  if height < 0 {
    height = -height;
    is_bottom_up = false;
  }

  pixels_offset := header.biSize;
  if header.biCompression == BI_BITFIELDS pixels_offset += 12;
  if cf_dib.count < pixels_offset return .{};

  src_bytes_per_pixel := header.biBitCount / 8;
  src_stride := ((width * src_bytes_per_pixel) + 3) & ~3;

  bitmap: Simp.Bitmap;
  bitmap.width  = width;
  bitmap.height = height;
  bitmap.format = .RGBA8;
  bitmap.stride = width * 4;
  bitmap.data = NewArray(width * height * 4, u8, initialized=false,, temp);

  dest_raw_ptr := bitmap.data.data;
  src_pixels_start := cf_dib.data + pixels_offset;

  for y: 0..height-1 {
    src_y := ifx is_bottom_up then (height - 1) - y else y;

    src_row  := src_pixels_start + (src_y * src_stride);
    dest_row := dest_raw_ptr     + (y * bitmap.stride);

    for x: 0..width-1 {
      src_ptr  := src_row  + (x * src_bytes_per_pixel);
      dest_ptr := dest_row + (x * 4);

      dest_ptr[0] = src_ptr[2];
      dest_ptr[1] = src_ptr[1];
      dest_ptr[2] = src_ptr[0];
      dest_ptr[3] = ifx src_bytes_per_pixel == 4 then src_ptr[3] else 255;
    }
  }

  return bitmap;
}

#import,dir "modules/libwebp";

windows_bitmap_to_webp :: (bitmapinfobytes: string, quality: float = 90) -> string {
  bitmap := windows_bitmap_to_simp_bitmap(bitmapinfobytes);
  webp_data: *u8;
  webp_size := WebPEncodeRGBA(bitmap.data.data, bitmap.width, bitmap.height, bitmap.stride, quality, *webp_data);
  defer WebPFree(webp_data);

  webp: string;
  webp.data = webp_data;
  webp.count = webp_size;
  return copy_string(webp,, temp);
}

webp_to_windows_bitmap :: (webp: string) -> string {
  width: s32;
  height: s32;
  pixels_data := WebPDecodeRGBA(webp.data, xx webp.count, *width, *height);
  defer WebPFree(pixels_data);

  pixels: string;
  pixels.data = pixels_data;
  pixels.count = width*height*4;
  return pixels_to_windows_bitmap(pixels, width, height);
}

pixels_to_windows_bitmap :: (pixels: string, width: s32, height: s32) -> string {
  bitmap_header: BITMAPINFOHEADER;
  bitmap_header.biWidth = width;
  bitmap_header.biHeight = height;
  bitmap_header.biSize = 40;
  bitmap_header.biPlanes = 1;
  bitmap_header.biBitCount = 8*4;
  bitmap_header.biSizeImage = xx (width*height * 4/*rgba bytes per pixel*/);

  bitmap := talloc_string(size_of(BITMAPINFOHEADER) + xx bitmap_header.biSizeImage);
  memcpy(bitmap.data, *bitmap_header, size_of(BITMAPINFOHEADER));

  // WebP decodes to top-down RGBA. Positive-height CF_DIB stores bottom-up BGRA rows.
  dest := bitmap.data + size_of(BITMAPINFOHEADER);
  for y: 0..height-1 {
    src := pixels.data + ((height - 1 - y) * width * 4);

    for 0..width-1 {
      dest[0] = src[2];
      dest[1] = src[1];
      dest[2] = src[0];
      dest[3] = src[3];

      src += 4;
      dest += 4;
    }
  }

  return bitmap;
}

record_to_windows_bitmap :: (record: DbRecord) -> string {
  if record.type == .BITMAP return decompress(record.preview);

  cached_bitmap := read_entire_file_from_clipman_cache_temp_folder(interp("${record.id}"));
  defer free(cached_bitmap);
  if cached_bitmap.count return decompress(cached_bitmap);
  if record.type == .WEBP return webp_to_windows_bitmap(record.preview);

  return "";
}

clipman_cache_file_path :: (name: string) -> string {
  temp_dir := getenv("temp");
  if !temp_dir {
    mylog("couldn't find %temp% folder, full quality image cache won't exist");
    return "";
  }

  cache_dir := interp("${to_string(temp_dir)}/clipman");
  make_directory_if_it_does_not_exist(cache_dir);
  return interp("${cache_dir}/${name}");
}

read_entire_file_from_clipman_cache_temp_folder :: (name: string) -> string {
  path := clipman_cache_file_path(name);
  if !path return "";
  return read_entire_file(path);
}

write_entire_file_to_clipman_cache_temp_folder :: (name: string, data: string) {
  path := clipman_cache_file_path(name);
  if path then write_entire_file(path, data);
}
