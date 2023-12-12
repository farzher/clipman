


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



// TextureCache.get_texture_for_record will return from the cache if it exists,
// or put it in the cache and return it.
// the cache uses my_lru_cache which probably should be improved.
// this will keep up to MAX_RECORDS textures around in ram forever. would be nice to delete
// old stuff when clipman isn't in use for a while
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
    if record.type != .BITMAP && record.type != .WEBP && !can_fetch_img_from_record_text then return null;

    // if the texture is already in the cache return it
    textureptr := find_pointer(TextureCache.texture_cache, record.id);
    if textureptr then return textureptr;

    // url records require different processing than normal bitmap records
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

    if record.type == .BITMAP || record.type == .WEBP {
      bitmap := windows_bitmap_to_simp_bitmap(record_to_windows_bitmap(record));
      texture: Simp.Texture;
      Simp.texture_load_from_bitmap(*texture, *bitmap);
      return add(*TextureCache.texture_cache, record.id, texture);
    }

    assert(false); return null; // not all control paths return a value;
  }
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

is_twitch_url :: (str: string) -> bool {
  if obviously_not_a_url(str) return false;

  if !Strings.contains(str, "twitch.tv/") return false;

  return true;
}
twitch_username_from_url :: (str: string) -> string {
  username := ghetto_regex_capture(str, "twitch.tv/", is_alnum);
  Strings.to_lower(username);
  return username;
}

obviously_not_a_url :: (str: string) -> bool {
  if str.count > 10_000 return true;
  if Strings.contains(str, "\n") return true;
  return false;
}

return_this_if :: (code: Code) #expand {value := #insert code; if value `return value; }
youtube_videoid_from_url :: (str: string) -> string {
  if !is_youtube_url(str) return "";
  return_this_if(ghetto_regex_capture(str, "youtube.com/watch?v=", is_alnum));
  return_this_if(ghetto_regex_capture(str, "youtu.be/", is_alnum));
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
selected_count :: () -> int {
  min, max := selected_range();
  count := (max - min) + 1;
  return count;
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
  tinyfd :: #library,no_dll "../bin/tinyfiledialogs64";
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









// cf_dib is the raw contents of GetClipboardData(CF_DIB)
// try to parse this thing into a simp bitmap
windows_bitmap_to_simp_bitmap :: (cf_dib: string) -> Simp.Bitmap {
  if(cf_dib == "") return .{};

  BI_BITFIELDS :: 3;

  bitmap_header: *BITMAPINFOHEADER = xx cf_dib.data;

  bytes_per_pixel := (() -> int #expand {
    if bitmap_header.biBitCount == 24 return 3;
    if bitmap_header.biBitCount == 32 return 4;
    assert(false); // shouldn't get here
  })();

  bitmap_pixeldata := (() -> string #expand {
    pixel_offset := size_of(BITMAPINFOHEADER);
    if bitmap_header.biCompression == BI_BITFIELDS then pixel_offset += 3*4;

    bitmap_pixeldata := cf_dib;
    bitmap_pixeldata.data += pixel_offset;
    bitmap_pixeldata.count -= pixel_offset;

    // if bytes_per_pixel is 3, convert it to 4, so we don't have to worry about 4 byte padding and junk
    ensure_4_bytes_per_pixel_BGRA_format :: () #expand {
      if bytes_per_pixel == 4 return;
      assert(bytes_per_pixel == 3);

      correct_pixeldata := talloc_string(bitmap_header.biWidth * bitmap_header.biHeight * 4);

      pixels_pushed := 0;
      push_pixel :: (r: u8, g: u8, b: u8) #expand {
        correct_pixeldata[pixels_pushed*4+0] = b;
        correct_pixeldata[pixels_pushed*4+1] = g;
        correct_pixeldata[pixels_pushed*4+2] = r;
        correct_pixeldata[pixels_pushed*4+3] = 255;
        pixels_pushed += 1;
      }

      w := bitmap_header.biWidth;
      stride_padding := bitmap_header.biWidth % 4;

      for y: 0..bitmap_header.biHeight-1 {
        for x: 0..bitmap_header.biWidth-1 {
          push_pixel(
            bitmap_pixeldata[(x+y*w)*3 +stride_padding*y +2],
            bitmap_pixeldata[(x+y*w)*3 +stride_padding*y +1],
            bitmap_pixeldata[(x+y*w)*3 +stride_padding*y +0]
          );
        }
      }

      bitmap_pixeldata = xx correct_pixeldata;
      bytes_per_pixel = 4;
    }
    ensure_4_bytes_per_pixel_BGRA_format();

    return bitmap_pixeldata;
  })();

  bitmap: Simp.Bitmap;
  bitmap.width  = bitmap_header.biWidth;
  bitmap.height = bitmap_header.biHeight;
  bitmap.format = .BGRA8;
  bitmap.stride = bitmap.width * 4;
  bitmap.data   = xx bitmap_pixeldata;
  return bitmap;
}

#import,dir "modules/libwebp";

windows_bitmap_to_webp :: (bitmapinfobytes: string, quality : float = 90) -> webpbytes: string, width: s32, height: s32 {
  bitmap := windows_bitmap_to_simp_bitmap(bitmapinfobytes);
  webpbytesptr: *u8;
  webpbytecount: int;
  if bitmap.format == .RGB8 {
    webpbytecount = WebPEncodeRGB (bitmap.data.data, bitmap.width, bitmap.height, bitmap.stride, quality, *webpbytesptr);
  } else {
    webpbytecount = WebPEncodeRGBA(bitmap.data.data, bitmap.width, bitmap.height, bitmap.stride, quality, *webpbytesptr);
  }
  defer WebPFree(webpbytesptr);
  webpbytesstr: string;
  webpbytesstr.data = webpbytesptr;
  webpbytesstr.count = webpbytecount;
  return copy_string(webpbytesstr, allocator=temp), bitmap.width, bitmap.height;
}

webp_to_pixels :: (webpbytes: string) -> pixels: string, width: s32, height: s32 {
  width: s32;
  height: s32;
  pixeldata := WebPDecodeRGBA(webpbytes.data, xx webpbytes.count, *width, *height);
  defer WebPFree(pixeldata);
  pixels: string;
  pixels.data = pixeldata;
  pixels.count = width*height*4;
  return copy_string(pixels, allocator=temp), width, height;
}

webp_to_simp_bitmap :: (webpbytes: string) -> Simp.Bitmap {
  pixels, width, height := webp_to_pixels(webpbytes);
  return windows_bitmap_to_simp_bitmap(pixels_to_windows_bitmap(pixels, width, height));
}

webp_to_windows_bitmap :: (webpbytes: string) -> string {
  pixels, width, height := webp_to_pixels(webpbytes);
  return pixels_to_windows_bitmap(pixels, width, height);
}

webp_to_webp :: (webpbytes: string, quality : float = 70) -> string {
  pixels, width, height := webp_to_pixels(webpbytes);
  // note: probably some unecessary work in here
  bitmap := pixels_to_windows_bitmap(pixels, width, height);
  return windows_bitmap_to_webp(bitmap, quality=quality);
}

pixels_to_windows_bitmap :: (pixels: string, width: s32, height: s32) -> string {
  bitmap_header: BITMAPINFOHEADER;
  bitmap_header.biWidth = width;
  bitmap_header.biHeight = height;
  bitmap_header.biSize = 40;
  bitmap_header.biPlanes = 1;
  bitmap_header.biBitCount = 8*4;
  bitmap_header.biSizeImage = xx (width*height * 4/*rgba bytes per pixel*/);

  bitmap_header_str := to_stringbytes(*bitmap_header);

  #import "String";
  return join(bitmap_header_str, pixels, allocator=temp);
}

record_to_windows_bitmap :: (record: DbRecord) -> string {
  if record.type == .BITMAP return decompress(record.preview);

  cached_bitmap := read_entire_file_from_clipman_cache_temp_folder(interp("${record.id}"));
  if cached_bitmap.count return decompress(cached_bitmap);
  if record.type == .WEBP return webp_to_windows_bitmap(record.preview);

  return ""; // all return paths
}

to_stringbytes :: (thing: *$T) -> string {
  str: string;
  str.data  = xx thing;
  str.count = size_of(T);
  return str;
}


read_entire_file_from_clipman_cache_temp_folder :: (name: string) -> bytes: string {
  temp := getenv("temp");
  if !temp {
    mylog("couldn't find %temp% folder, full quality image cache won't exist");
    return "";
  }

  temp_folder_path := to_string(temp);
  clipman_cache_path := interp("${temp_folder_path}/clipman");
  make_directory_if_it_does_not_exist(clipman_cache_path);
  return read_entire_file(interp("${clipman_cache_path}/${name}"));
}
write_entire_file_to_clipman_cache_temp_folder :: (name: string, data: string) {
  temp := getenv("temp");
  if !temp {
    mylog("couldn't find %temp% folder, full quality image cache won't exist");
    return;
  }

  temp_folder_path := to_string(temp);
  clipman_cache_path := interp("${temp_folder_path}/clipman");
  make_directory_if_it_does_not_exist(clipman_cache_path);
  write_entire_file(interp("${clipman_cache_path}/${name}"), data);
}
