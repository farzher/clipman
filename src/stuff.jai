


// this file is a mess, idk





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
    is_imgur := is_imgur_url(record.preview);

    // guard against non-image records
    if record.type != .BITMAP && !is_imgur then return null;

    // if the texture is already in the cache return it
    textureptr := find_pointer(TextureCache.texture_cache, record.id);
    if textureptr then return textureptr;

    // imgur records require different processing than normal bitmap records
    if is_imgur {
      Global(#code imgurcache: Table(string, string)); // todo: this is a memory leak

      bytes := imgurcache[record.preview];
      if !bytes {
        response := request(record.preview); // todo: make this request async
        if !response then response = "0";
        imgurcache[record.preview] = response;
        bytes = response;
      }

      // something went wrong when fetching the image
      if bytes.count <= 1 return null;

      texture: Simp.Texture;
      Simp.texture_load_from_memory(*texture, xx bytes);
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


is_imgur_url :: (str: string) -> bool {

  starts_correctly := Strings.starts_with(str, "https://i.imgur.com/")
                   || Strings.starts_with(str, "http://i.imgur.com/");
  if !starts_correctly return false;

  ends_correctly := Strings.ends_with(str, ".png")
                 || Strings.ends_with(str, ".jpg")
                 || Strings.ends_with(str, ".jpeg");
  if !ends_correctly return false;

  return true;
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
