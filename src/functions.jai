



// self contained helper functions without global dependencies




// #load "modules/mybasic.jai";
#import,file "modules/mybasic.jai";
#import,file "modules/mywindows.jai";
#import "Window_Creation";


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


#import "lz4-1.9.1";
compress :: (str: string) -> string {
  compressed := talloc_string(str.count + 1024*10/*some extra space incase the compressed version is bigger? perf: i think i only need + 1 extra byte here*/);
  // nvm this actually started crashing with str.count + 1024, i needed to put 1024*10 to stop the crash when copying an image

  bytes_written := LZ4_compress_default(str.data , compressed.data, xx str.count, xx compressed.count);
  if bytes_written <= 0  die("compress error");
  compressed.count = bytes_written;
  return compressed;
}
decompress :: (compressed: string) -> string {
  decompressed := talloc_string(1024 * 1024 * 75 /*75mb is the max we can decompress. 4k monitor screenshots are like 32MB a picture from my phone was crashing at 60mb ... */);
  // decompressed := talloc_string(1024 * 1024 * 200 /*200mb is the max we can decompress. 4k monitor screenshots are like 32MB a picture from my phone was crashing at 60mb ... */);
  bytes_written := LZ4_decompress_safe(compressed.data, decompressed.data, xx compressed.count, xx decompressed.count);
  if bytes_written <= 0  die("decompress error");
  decompressed.count = bytes_written;
  return decompressed;
}



save_bitmap_to_file :: (bitmapinfobytes: string, filepath: string) -> bool {

  stbi   :: #import "stb_image_write";
  String :: #import "String";
  Simp   :: #import "Simp";

  bitmap: Simp.Bitmap;
  // Simp.bitmap_load_from_memory(*bitmap, xx bitmapinfobytes);
  bmpinfo: *BITMAPINFO = xx bitmapinfobytes.data;
  bitmap.width = bmpinfo.bmiHeader.biWidth;
  bitmap.height = bmpinfo.bmiHeader.biHeight;
  bitmap.data.data = bitmapinfobytes.data + size_of(BITMAPINFO); // is this actually correct?


  if bmpinfo.bmiHeader.biBitCount == 24 then bitmap.format = .RGB8; else bitmap.format = .BGRA8;
  _size, _stride := Simp.get_image_size(bitmap.format, bitmap.width, bitmap.height);
  bitmap.stride = xx _stride;

  // doesn't support bgr
  // Simp.bitmap_save(*bitmap, filepath);

  stride := bitmap.stride;
  data   := bitmap.data.data;

  components : s32 = 4;
  if bitmap.format == .RGB8 components = 3;

  // change format from .BGRA8 to .RGBA8
  // wtf??? this is so weird.
  bitmap.data.count = _size;
  if components == 4 {
    for i: 0 .. bitmap.width*bitmap.height-1 {
      Swap(*bitmap.data[i*components+0], *bitmap.data[i*components+2]);
    }
  } else if components == 3 {
    for i: 0 .. bitmap.width*bitmap.height-1 {
      Swap(*bitmap.data[i*components+0], *bitmap.data[i*components+1]);
    }
  }


  name      := temp_c_string(filepath);
  extension := String.path_extension(filepath);

  stbi.stbi_flip_vertically_on_write(1); // image was being saved upside down. again wtf????
  if extension == {
    case "png";
      return stbi.stbi_write_png(name, bitmap.width, bitmap.height, components, data, stride) != 0;
    case "tga";
      return stbi.stbi_write_tga(name, bitmap.width, bitmap.height, components, data, stride) != 0;
    case "bmp";
      return stbi.stbi_write_bmp(name, bitmap.width, bitmap.height, components, data, stride) != 0;
    case "hdr";
      return stbi.stbi_write_hdr(name, bitmap.width, bitmap.height, components, data, stride) != 0;
    case "jpg";
      return stbi.stbi_write_jpg(name, bitmap.width, bitmap.height, components, data, stride, quality=80) != 0;
    case;
      mylog("Bitmap extension", extension, "is not understood by this code.");
      return false;
  }
}
