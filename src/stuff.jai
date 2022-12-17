


// this file is a mess, idk









// for making curl requests in the background
// you can spam call req := request_q.get(url), it will only make the request once
// once it's req.ready(req) you can use the req.response, then req.free(req) it
// // example:
// req := request_q.get("farzher.com/404");
// if req.ready(req) {
//   mylog(req.response); // Cannot GET /404
//   req.free(req);
// }
request_q: struct {
  // #import,dir "modules/Request";
  #import "Thread";

  request_cache   : Table(string, Request);
  thread_group    : Thread_Group;
  inited          := false;

  Request :: struct {
    url           : string;
    response      : string;
    status        : enum {NONE; FETCHING; DONE;};
    created_at_ms : float64;
    ready         :: (req: Request) -> bool { return req.status == .DONE; }
    free          :: request_q.free;
  }


  get :: (url: string) -> Request {
    ensure_init();

    req, found := table_find(*request_q.request_cache, url);
    if found return req;

    if !found {
      req: Request;
      req.created_at_ms = getms();
      req.status = .FETCHING;
      req.url = copy_string(url); // url may be in temp storage
      req_ptr := table_add(*request_q.request_cache, req.url, req);
      add_work(*request_q.thread_group, req_ptr, req.url);
    }
    return req;
  }


  free :: (req: Request) {
    table_remove(*request_q.request_cache, req.url);
    free(req.url.data);
    if req.response free(req.response.data);
  }

  free_all_old_finished_requests :: () {
    MAX_AGE_MS :: 5000;

    now := getms();
    for *req: request_q.request_cache {
      if !req.ready(req) continue;
      if (now - req.created_at_ms) < MAX_AGE_MS continue;
      req.free(req);
    }
  }

  ensure_init :: () {
    if request_q.inited return; request_q.inited = true;

    request_q.thread_group.name = "request_q.thread_group";
    request_q.thread_group.logging = false;
    thread_count :: 12; // how many images we can load at the same time
    init(*request_q.thread_group, thread_count, request_q.thread_do_work);
    start(*request_q.thread_group);
  }

  thread_do_work :: (group: *Thread_Group, thread: *Thread, work: *void) -> Thread_Continue_Status {
    req := cast(*Request)work;

    req.response = request(req.url, timeout_seconds=2);
    req.status = .DONE;

    return .CONTINUE;
  }
}


TextureCache: struct {
  #import,file "modules/my_lru_cache.jai";

  texture_cache: LRU(int, Simp.Texture, MAX_RECORDS, FREE_PROC=texture_free);

  MAX_RECORDS :: 100; // a guess at the maximum amount of records that could ever be displayed. if we display more than this bad things could happen

  // simp's implementation "deinit" doesn't actually free the memory currently, lol.
  texture_free :: (texture: *Simp.Texture) {
    #import "GL";
    glDeleteTextures(1, *texture.gl_handle);
  }

  get_texture_for_record :: (record: DbRecord) -> *Simp.Texture {
    can_fetch_img_from_record_text := can_fetch_img_from_text(record.preview);

    // guard against non-image records
    if record.type != .BITMAP && !can_fetch_img_from_record_text then return null;

    // if the texture is already in the cache return it
    textureptr := find_pointer(TextureCache.texture_cache, record.id);
    if textureptr then return textureptr;

    // imgur records require different processing than normal bitmap records
    if can_fetch_img_from_record_text {

      request_q.free_all_old_finished_requests(); // todo: this shouldn't be here
      req := request_q.get(get_img_url_from_text(record.preview));
      if !req.ready(req) return null;
      defer req.free(req);
      if !req.response return null;

      texture: Simp.Texture;
      Simp.texture_load_from_memory(*texture, xx req.response);
      return add(*TextureCache.texture_cache, record.id, texture);
    }

    texture: Simp.Texture;
    bitmap: Simp.Bitmap;
    bitmapinfobytes := decompress(record.preview);
    bmpinfo: *BITMAPINFO = xx bitmapinfobytes.data;
    bitmap.width = bmpinfo.bmiHeader.biWidth;
    bitmap.height = bmpinfo.bmiHeader.biHeight;
    bitmap.data.data = bitmapinfobytes.data + size_of(BITMAPINFO); // is this actually correct?
    // bitmap.format = .BGRA8;
    _size, _stride := Simp.get_image_size(bitmap.format, bitmap.width, bitmap.height);
    bitmap.stride = xx _stride;

    success := Simp.texture_load_from_bitmap(*texture, *bitmap);
    if !success  die("failed to load texture", record.id);

    return add(*TextureCache.texture_cache, record.id, texture);
  }
}

can_fetch_img_from_text :: (str: string) -> bool { return is_imgur_url(str) || is_youtube_url(str); }
get_img_url_from_text :: (str: string) -> string {
  if is_imgur_url(str) return str;
  if is_youtube_url(str) return _("https://img.youtube.com/vi/%{youtube_videoid_from_url(str)}/0.jpg");
  return "";
}

is_imgur_url :: (str: string) -> bool {
  // https://i.imgur.com/IMGID.png
  // http://i.imgur.com/IMGID.jpg

  if obviously_not_a_url(str) return false;

  starts_correctly := Strings.starts_with(str, "https://i.imgur.com/")
                   || Strings.starts_with(str, "http://i.imgur.com/");
  if !starts_correctly return false;

  ends_correctly := Strings.ends_with(str, ".png")
                 || Strings.ends_with(str, ".jpg")
                 || Strings.ends_with(str, ".jpeg");
  if !ends_correctly return false;

  return true;
}

is_youtube_url :: (str: string) -> bool {
  // https://www.youtube.com/watch?v=VIDEOID
  // https://youtu.be/VIDEOID?t=7967

  if obviously_not_a_url(str) return false;

  starts_correctly := Strings.starts_with(str, "https://youtube.com/watch?v=")
                   || Strings.starts_with(str, "https://www.youtube.com/watch?v=")
                   || Strings.starts_with(str, "https://youtu.be/")
                   || Strings.starts_with(str, "https://www.youtu.be/");
  if !starts_correctly return false;

  return true;
}

obviously_not_a_url :: (str: string) -> bool {
  if str.count > 10_000 return true;
  if Strings.contains(str, "\n") return true;
  return false;
}

youtube_videoid_from_url :: (str: string) -> string {
  if !is_youtube_url(str) return "";

  videoid: string;

  videoid = ghetto_regex_capture(str, "youtube.com/watch?v=", is_alnum);
  if videoid return videoid;

  videoid = ghetto_regex_capture(str, "youtu.be/", is_alnum);
  if videoid return videoid;

  return videoid;
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











search_input: GetRect.Text_Input_State;
search_string: *string;

GetRect :: #import "GetRect";
init_search_string :: () {
  search_input.active = true;
  search_input.text.data = search_input.input_buffer.data;
  search_string = *search_input.text;
}
update_search_string :: () {
  selected_index = 0;
  scroll_offset = 0;
}








my_font      : *Simp.Dynamic_Font;
my_big_font  : *Simp.Dynamic_Font;
my_tiny_font : *Simp.Dynamic_Font;
init_font :: () {
  font_file_bytes :: #run embed_file("bin/OpenSans-BoldItalic.ttf");
  my_font      = Simp.get_font_at_size(font_file_bytes, 18);
  my_big_font  = Simp.get_font_at_size(font_file_bytes, 32);
  my_tiny_font = Simp.get_font_at_size(font_file_bytes, 12);
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





colorref : COLORREF : 0x00000000;
old_trans: u8;
m: MARGINS = .{-1, -1, -1, -1};
update_window_transparency :: (can_be_transparent: bool) {
  new_trans: u8 = xx ifx can_be_transparent then ( (cast(float)config.transparency) /100)*255 else 1*255;
  if new_trans != old_trans {
    old_trans = new_trans;

    SetLayeredWindowAttributes(hwnd, colorref, new_trans, LWA_ALPHA /*|LWA_COLORKEY*/);
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



// maybe just use imgui instead? this thing looks like trash
// tinyfiledialogs is dumb and should be replaced
showinputbox :: (title: *u8, message: *u8, ispassword := true) -> *u8 {
  // DialogBoxParamW :: (hInstance: HINSTANCE, lpTemplate: LPCWSTR, hWndParent: HWND, lpDialogFunc: *void, dwInitParam: LPARAM) -> s32 #foreign user32;
  tinyfd :: #foreign_library,no_dll "../bin/tinyfiledialogs64";
  tinyfd_inputBox :: (title: *u8, message: *u8, defaultinput: *u8) -> *u8 #foreign tinyfd;

  // memory leak? where's the memory for the returned string? is it really on the stack?
  return tinyfd_inputBox(title, message, ifx ispassword null else cast(*u8)"1");
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
