/* -farzher September 13, 2021
  just a collection of common functions i use
*/

#import "Basic";
#import "String";
#import "Windows";
mylog :: (args:..Any, to_standard_error := false, loc := #caller_location) {
  if args.count == 0 { print("\n", to_standard_error=to_standard_error); return; }

  formatstr: string;
  push_tallocator();
  for args  formatstr = join(formatstr, "% ");
  formatstr[formatstr.count-1] = #char "\n"; // replace the trailing space with a newline

  filename := path_filename(loc.fully_pathed_filename);
  args_with_extra: [..] Any;
  array_add(*args_with_extra, filename);
  array_add(*args_with_extra, loc.line_number);
  for args array_add(*args_with_extra, it);

  print(join("[%:%] ", formatstr), ..args_with_extra, to_standard_error=to_standard_error);
}

die :: (args: ..Any) {
  mylog("[Fatal Error]", to_standard_error=true);
  mylog(..args, to_standard_error=true);
  exit(1);
}

ini_parse_string :: (content: string, destination: *$T) -> bool {
  info := type_info(T);
  if info.type != .STRUCT return false;
  struct_info := cast(*Type_Info_Struct) info;

  parsed := destination.*; // Keep defaults for keys omitted from the file.
  lines := split(content, "\n",, temp);
  for raw_line: lines {
    line := trim(raw_line);
    if !line continue;
    if line[0] == #char "#" || line[0] == #char ";" continue;

    equals_index := find_index_from_left(line, "=");
    if equals_index < 0 return false;

    key        := trim(slice(line, 0, equals_index));
    value_text := trim(slice(line, equals_index + 1, line.count - equals_index - 1));
    if !key return false;

    member: *Type_Info_Struct_Member;
    for *candidate: struct_info.members {
      if candidate.flags & .CONSTANT continue;
      if candidate.name == key { member = candidate; break; }
    }
    if !member continue;

    slot := cast(*u8) *parsed + member.offset_in_bytes;
    if member.type == type_info(int) {
      value, success, remainder := string_to_int(value_text, T = int);
      if !success || trim(remainder) return false;
      (.*) cast(*int) slot = value;
    } else if member.type == type_info(string) {
      (.*) cast(*string) slot = copy_string(value_text);
    } else {
      return false;
    }
  }

  destination.* = parsed;
  return true;
}

ini_write_file :: (filename: string, value: $T) -> bool {
  File :: #import "File";

  info := type_info(T);
  if info.type != .STRUCT return false;
  struct_info := cast(*Type_Info_Struct) info;

  builder: String_Builder;
  defer free_buffers(*builder);

  for *member: struct_info.members {
    if member.flags & .CONSTANT continue;

    append(*builder, member.name);
    append(*builder, " = ");

    slot := cast(*u8) *value + member.offset_in_bytes;
    if member.type == type_info(int) {
      print_to_builder(*builder, "%", (.*) cast(*int) slot);
    } else if member.type == type_info(string) {
      append(*builder, (.*) cast(*string) slot);
    } else {
      return false;
    }
    append(*builder, "\n");
  }

  return File.write_entire_file(filename, *builder);
}

tallocator :: temp;
tfree :: reset_temporary_storage;
push_tallocator :: () #expand {
  old_allocator           := context.allocator;
  `defer context.allocator = old_allocator;

  context.allocator        = tallocator;
};

mapnumber :: (value: float, from1: float, from2: float, to1: float, to2: float) -> float {
  ratio := (value - from1) / (from2 - from1);
  if ratio > 1 then ratio = 1;
  else if ratio < 0 then ratio = 0;
  return (to2 - to1)*ratio + to1;
}

getms :: () -> float64 { return cast(float64)(seconds_since_init()*1000); }
getutc :: () -> u32 {
  systemtime: SYSTEMTIME;
  GetSystemTime(*systemtime);
  filetime: FILETIME;
  SystemTimeToFileTime(*systemtime, *filetime);

  WINDOWS_TICK      :: 10_000_000;
  SEC_TO_UNIX_EPOCH :: 11644473600;

  utc: *u64 = xx *filetime;
  return cast(u32)( utc.* / WINDOWS_TICK - SEC_TO_UNIX_EPOCH);
}
getutcms :: () -> u64 {
  systemtime: SYSTEMTIME;
  GetSystemTime(*systemtime);
  filetime: FILETIME;
  SystemTimeToFileTime(*systemtime, *filetime);

  WINDOWS_TICK      :: 10_000_000 / 1000;
  SEC_TO_UNIX_EPOCH :: 11644473600;

  utc: *u64 = xx *filetime;
  return utc.* / WINDOWS_TICK - SEC_TO_UNIX_EPOCH;
}

// String interpolation: interp("hello %{name}") compiles to tprint("hello %", name).
interp :: string_interpolation;
string_interpolation  :: ($_str: string, allocator: Allocator = temp, caller_scope := #caller_code) -> string #expand {
  a := ifx allocator.proc then allocator else context.allocator;
  push_allocator(a); // sprint doesn't accept an allocator, so we have to push_allocator to the context

  #insert,scope(caller_scope) -> string {

    String :: #import "String";

    str := _str; // to make str not constant
    // when using #string you can have newlines in your string
    // we need to rewrite these actual newlines to \n because our string to sprint can't have real newline in it
    str = String.replace(str, "\n", "\\n");
    // all " need to be escaped
    str = String.replace(str, "\"", "\\\"");

    // loop through str char by char, building the format_str and arguments
    format_str: String_Builder;
    arguments : [..] string;
    for i: 0 .. str.count-1 {

      is_start_of_interpolated_code := (str[i] == #char"#" || str[i] == #char"%" || str[i] == #char"$") && (i+1 < str.count-1 && str[i+1] == #char"{");

      // if this character is a % that's not part of code, transform it into \% so it's interpreted as a normal %
      if !is_start_of_interpolated_code && str[i] == #char"%" {
        append(*format_str, "\\%");
        continue;
      }

      // if this character is just a normal part of the string, write the character to format_str as is
      if !is_start_of_interpolated_code {
        append(*format_str, str[i]);
        continue;
      }

      // Write a format placeholder and save the interpolated expression.
      append(*format_str, "%0");
      i += 2;

      closing_brace_index := -1;
      j := i; while j < str.count { defer j += 1;
        // Skip braces inside single-quoted strings.
        if str[j] == #char"'" j = String.find_index_from_left(str, "'", j+1);
        if str[j] == #char"}" {closing_brace_index = j; break; }
      }
      assert(closing_brace_index != -1);

      arg := String.slice(str, i, closing_brace_index - i);
      arg = String.replace(arg, "'", "\"");
      array_add(*arguments, arg);
      i = xx closing_brace_index;
    }

    arguments_string := "";
    if arguments.count {
      builder: String_Builder;
      for arguments {
        append(*builder, ", ");
        append(*builder, it);
      }
      arguments_string = builder_to_string(*builder);
    }

    return tprint("return sprint(\"%\"%);", builder_to_string(*format_str), arguments_string);
  }
}

set_cwd_to_exe_location :: () {
  system :: #import "System";
  String :: #import "String";
  set_working_directory(String.path_strip_filename(system.get_path_of_running_executable()));
}

#import,dir "curl";

// Performs a blocking HTTP request. Allocates response_body using context.allocator
request :: (url: string, data := "", method := "", headers := string.[], include_headers := false, follow_redirects := true, timeout_seconds := 0, ) -> response_body: string, response_code: int, curl_code: CURLcode {
  size_t :: u64;

  write_callback :: (data: *u8, size: size_t, item_count: size_t, userdata: *void) -> size_t #c_call {
    byte_count := size * item_count;
    builder := cast(*String_Builder) userdata;

    jai_context: #Context;
    push_context jai_context {
      append(builder, data, xx byte_count);
    }
    return byte_count;
  }

  curl := curl_easy_init();
  assert(curl != null);
  defer curl_easy_cleanup(curl);

  curl_easy_setopt(curl, .URL, temp_c_string(url));

  if method                              curl_easy_setopt(curl, .CUSTOMREQUEST, temp_c_string(method));
  if data || (method && method != "GET") curl_easy_setopt(curl, .POSTFIELDS, temp_c_string(data));
  if include_headers                     curl_easy_setopt(curl, .HEADER, 1); // simply prepends headers to body
  if method == "HEAD"                    curl_easy_setopt(curl, .NOBODY, 1);
  if follow_redirects                    curl_easy_setopt(curl, .FOLLOWLOCATION, 1);
  if timeout_seconds                     curl_easy_setopt(curl, .TIMEOUT, timeout_seconds);

  slist: *curl_slist;
  defer if slist curl_slist_free_all(slist);

  for headers slist = curl_slist_append(slist, temp_c_string(it));
  if slist curl_easy_setopt(curl, .HTTPHEADER, slist);

  builder: String_Builder;
  defer free_buffers(*builder);
  curl_easy_setopt(curl, .WRITEFUNCTION, write_callback);
  curl_easy_setopt(curl, .WRITEDATA,     *builder);

  // i was getting the error PEER_FAILED_VERIFICATION
  curl_easy_setopt(curl, .SSL_VERIFYPEER, 0);
  curl_easy_setopt(curl, .SSL_VERIFYHOST, 0);

  // actually execute the request. this is blocking
  curl_code := curl_easy_perform(curl);

  response_code: int;
  if curl_code == .OK  curl_easy_getinfo(curl, .RESPONSE_CODE, *response_code);

  response_body := builder_to_string(*builder);
  return response_body, response_code, curl_code;
}
