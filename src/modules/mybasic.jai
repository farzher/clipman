/* -farzher September 13, 2021
  just a collection of common functions i use
*/



// using #import "Basic";
#import "Basic";

#import "String";
mylog :: (args:..Any, to_standard_error := false) {
  if args.count == 0 { print("\n", to_standard_error=to_standard_error); return; }

  formatstr: string;
  push_tallocator();
  for args  formatstr = join(formatstr, "% ");
  formatstr[formatstr.count-1] = #char "\n"; // replace the trailing space with a newline
  print(formatstr, ..args, to_standard_error=to_standard_error);
}

_lastmylogms: float64;
mylogms :: (args: ..Any) {
  ms := getms() - _lastmylogms;

  print("[%ms] ", formatFloat(ms, trailing_width=2));
  mylog(..args);

  _lastmylogms = getms();
}

die :: (args: ..Any) {
  mylog("[Fatal Error]", to_standard_error=true);
  mylog(..args, to_standard_error=true);
  exit(1);
}


logx :: ($code: Code, loc := #caller_location) -> code.type #expand {
  #import "Program_Print";
  #import "Compiler";
  #import "String";

  code_string := #insert -> string {
    node := compiler_get_nodes(code);
    if node.kind == .PROCEDURE_CALL return _logx_procedure_call(node);
    else                            return "#run code_to_string(code);";
  };

  result := #insert code;
  filename := path_filename(loc.fully_pathed_filename);
  log("[%:%] % = %", filename, loc.line_number, code_string, wrap_in_quotes_if_string(result));
  return result;


  _logx_procedure_call :: (root: *Code_Node) -> string {
    procedure_node := cast(*Code_Procedure_Call)root;

    format_str: String_Builder;
    args: [..] string;
    format_str_for_args: [..] string;
    append(*format_str, node_to_string(procedure_node.procedure_expression));
    append(*format_str, "(");
    for argument: procedure_node.arguments_unsorted {
      node := argument.expression;
      val := node_to_string(node);
      full_argument_name := ifx argument.name then join(argument.name.name, "=") else "";
      array_add(*format_str_for_args, join(full_argument_name, "%"));
      array_add(*args, tprint("#insert,scope(code) \"wrap_in_quotes_if_string(%);\"", escape(val)));
    }
    append(*format_str, join(..format_str_for_args, ", "));
    append(*format_str, ")");

    return tprint("tprint(\"%\", %);", escape(builder_to_string(*format_str)), join(..args, ", "));
  }
  code_to_string :: (code: Code) -> string #expand {
    builder: String_Builder;
    print_expression(*builder, compiler_get_nodes(code));
    return builder_to_string(*builder, allocator=temp);
  }
  node_to_string :: (node: *Code_Node) -> string #expand {
    builder: String_Builder;
    print_expression(*builder, node);
    return builder_to_string(*builder, allocator=temp);
  }
}
// logx depends on this at runtime
wrap_in_quotes_if_string :: (thing: $T) -> string {
  #if T == string return tprint("\"%\"", escape(thing));
  else            return tprint("%", thing);
}
// logx depends on this at runtime
escape :: (str: string) -> string {
  if str == "" return "";

  result: String_Builder;
  for i: 0 .. str.count - 1 {
    if str[i] == {
      case #char "\\"; append(*result, "\\\\");
      case #char "\e"; append(*result, "\\e");
      case #char "\n"; append(*result, "\\n");
      case #char "\r"; append(*result, "\\r");
      case #char "\t"; append(*result, "\\t");
      case #char "\""; append(*result, "\\\"");
      case #char "\0"; append(*result, "\\0");
      case;
        if str[i] < 32 print_to_builder(*result, "\\x%", formatInt(str[i], 16, 2));
        else           append(*result, str[i]);
    }
  }
  return builder_to_string(*result);
}








// NO_CODE :: #code,null;
// logx :: ($c1:Code=NO_CODE, $c2:Code=NO_CODE, $c3:Code=NO_CODE, $c4:Code=NO_CODE, loc := #caller_location) -> c1.type, c2.type, c3.type, c4.type #expand {
//   #if c1 == NO_CODE _logx(#procedure_name(), loc); // todo: make a more useful output for when logx is called with no arugments
//   r1: c1.type; #if #run c1 != NO_CODE  r1 = _logx(c1, loc);
//   r2: c2.type; #if #run c2 != NO_CODE  r2 = _logx(c2, loc);
//   r3: c3.type; #if #run c3 != NO_CODE  r3 = _logx(c3, loc);
//   r4: c4.type; #if #run c4 != NO_CODE  r4 = _logx(c4, loc);
//   return r1, r2, r3, r4;
// }
// _logx :: ($code: Code, loc := #caller_location) -> code.type #expand {
//   #import "Program_Print";
//   #import "Compiler";
//   #import "String";

//   code_string := #insert -> string {
//     node := compiler_get_nodes(code);
//     if node.kind == .PROCEDURE_CALL return _logx_procedure_call(node);
//     else                            return "#run code_to_string(code);";
//   };

//   result := #insert code;
//   filename := path_filename(loc.fully_pathed_filename);
//   if tprint("%", wrap_in_quotes_if_string(result)) != code_string
//     log("[%:%] % = %", filename, loc.line_number, code_string, wrap_in_quotes_if_string(result));
//   else
//     log("[%:%] %", filename, loc.line_number, code_string);
//   return result;


//   _logx_procedure_call :: (root: *Code_Node) -> string {
//     procedure_node := cast(*Code_Procedure_Call)root;

//     format_str: String_Builder;
//     args: [..] string;
//     format_str_for_args: [..] string;
//     append(*format_str, node_to_string(procedure_node.procedure_expression));
//     append(*format_str, "(");
//     for argument: procedure_node.arguments_unsorted {
//       node := argument.expression;
//       val := node_to_string(node);
//       full_argument_name := ifx argument.name then join(argument.name.name, "=") else "";
//       array_add(*format_str_for_args, join(full_argument_name, "%"));
//       array_add(*args, tprint("#insert,scope(code) \"wrap_in_quotes_if_string(%);\"", escape(val)));
//     }
//     append(*format_str, join(..format_str_for_args, ", "));
//     append(*format_str, ")");

//     return tprint("tprint(\"%\", %);", escape(builder_to_string(*format_str)), join(..args, ", "));
//   }
//   node_to_string :: (node: *Code_Node) -> string #expand {
//     builder: String_Builder;
//     print_expression(*builder, node);
//     return builder_to_string(*builder, allocator=temp);
//   }
// }
// // // logx depends on this
// // code_to_string :: (code: Code) -> string #expand {
// //   builder: String_Builder;
// //   print_expression(*builder, compiler_get_nodes(code));
// //   return builder_to_string(*builder, allocator=temp);
// // }
// // logx depends on this at runtime
// wrap_in_quotes_if_string :: (thing: $T) -> string {
//   #if T == string return tprint("\"%\"", escape(thing));
//   else            return tprint("%", thing);
// }
// // logx depends on this at runtime
// escape :: (str: string) -> string {
//   if str == "" return "";

//   result: String_Builder;
//   for i: 0 .. str.count - 1 {
//     if str[i] == {
//       case #char "\\"; append(*result, "\\\\");
//       case #char "\e"; append(*result, "\\e");
//       case #char "\n"; append(*result, "\\n");
//       case #char "\r"; append(*result, "\\r");
//       case #char "\t"; append(*result, "\\t");
//       case #char "\""; append(*result, "\\\"");
//       case #char "\0"; append(*result, "\\0");
//       case;
//         if str[i] < 32 print_to_builder(*result, "\\x%", formatInt(str[i], 16, 2));
//         else           append(*result, str[i]);
//     }
//   }
//   return builder_to_string(*result);
// }









#scope_file
Compiler :: #import "Compiler";
#scope_export
// isrelease :: #run Compiler.get_build_options().optimization_level == .RELEASE;
RELEASE :: #run Compiler.get_build_options().array_bounds_check == .OFF;

tallocator :: __temporary_allocator;
tfree :: reset_temporary_storage;
tget :: get_temporary_storage_mark;
tset :: set_temporary_storage_mark;
push_trelease :: auto_release_temp;
push_treset :: auto_release_temp;
push_tallocator :: () #expand {
  old_allocator           := context.allocator;
  `defer context.allocator = old_allocator;

  context.allocator        = tallocator;
};

printF :: () { print("F"); }

map :: (array: [] $T, f: (T) -> $R) -> [..] R {
  result: [..] R;
  for array array_add(*result, f(it));
  return result;
}

#import "Math";
mapnumber :: (value: float, from1: float, from2: float, to1: float, to2:float, exponent:float=0, clamp:=true) -> float {
  adist := from2 - from1;
  bdist := to2 - to1;
  ratio := (value - from1) / adist;
  isnegative := ratio < 0;

  if exponent {
    ratio = pow(abs(ratio), exponent);
    if isnegative then ratio = -ratio;
  }

  if clamp {
    if ratio > 1 then ratio = 1;
    else if ratio < 0 then ratio = 0;
  }

  return bdist*ratio + to1;
}

get_ms :: () -> float64 {
  return to_float64_seconds(current_time_monotonic()) * 1000;
}

time :: ($code: Code, name: string, count:=1) #expand {
  starttime := get_time();
  for 1 .. count  #insert code;
  difftime := get_time()-starttime;

  fixedname := talloc_string(9);
  for 0..fixedname.count-1   fixedname[it] = #char" ";
  memcpy(fixedname.data, name.data, min(9, name.count) );

  mylog(fixedname, "time:", difftime, "seconds.");
}
bench :: time;
bench :: (name: string, $code: Code, count:=1) #expand {
  bench(code, name, count=count);
}

substr :: inline (str: string, index: int, count: int = 0) -> string #must {
  if count == 0 count = str.count - index;

  c: string = ---;
  c.data = str.data + index;

  if count < 0 {
    c.count = str.count + count;
  } else {
    c.count = count;
  }

  return c;
}

fromcstr :: (cstr: *u8) -> string {
  ret: string;
  if (cstr == null) return ret;
  ret.data = xx cstr;
  ret.count = c_style_strlen(xx cstr);
  return ret;
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
  return cast(u32)( <<utc / WINDOWS_TICK - SEC_TO_UNIX_EPOCH);
}
getutcms :: () -> u64 {
  systemtime: SYSTEMTIME;
  GetSystemTime(*systemtime);
  filetime: FILETIME;
  SystemTimeToFileTime(*systemtime, *filetime);

  WINDOWS_TICK      :: 10_000_000 / 1000;
  SEC_TO_UNIX_EPOCH :: 11644473600;

  utc: *u64 = xx *filetime;
  return <<utc / WINDOWS_TICK - SEC_TO_UNIX_EPOCH;
}





// string interpolation.
// example: tprinti("hello %{name}") compiles to tprint("hello %", name)
// perf: is calling append for every single character slow?
sprinti :: #bake_arguments interp(allocator = .{});
tprinti :: #bake_arguments interp(allocator = temp);
// _       :: string_interpolation;
interp  :: string_interpolation;
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

      // if this character is a % that's not part of code, transform it into %% so it's interpreted as a normal %
      if !is_start_of_interpolated_code && str[i] == #char"%" {
        append(*format_str, "%%");
        continue;
      }

      // if this character is just a normal part of the string, write the character to format_str as is
      if !is_start_of_interpolated_code {
        append(*format_str, str[i]);
        continue;
      }

      // we have a block of interpolated code. write %0 to the format_str and push the code into arguments
      if is_start_of_interpolated_code {
        append(*format_str, "%0");
        i += 2;

        closing_brace_index := -1;
        j := i; while j < str.count { defer j += 1;
          // if we're in a string, skip to the end without checking for } inside the string ex %{'{}{}{}'}
          if str[j] == #char"'" j = String.find_index_from_left(str, "'", j+1); // this can return -1, should probably assert on this
          if str[j] == #char"}" {closing_brace_index = j; break; }
        }
        assert(closing_brace_index != -1);

        arg := String.slice(str, i, closing_brace_index - i);
        arg = String.replace(arg, "'", "\""); // rewrite ' to " ex "Mode: %{ifx SOA 'SOA' else 'AOS'}"
        array_add(*arguments, arg);

        i = xx closing_brace_index;
        continue;
      }
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

// to_c_string :: (s: string) -> *u8 {
//   result : *u8 = alloc(s.count + 1);
//   memcpy(result, s.data, s.count);
//   result[s.count] = 0;
//   return result;
// }

embed_file :: (file_path: string) -> []u8 {
  File :: #import "File";
  return xx File.read_entire_file(file_path);
}

Global :: (code: Code) #expand {
  Compiler :: #import "Compiler";
  #run Compiler.add_build_string(tprint("%;", code_to_string(code)), -1);
}

code_to_string :: (code: Code) -> string #expand {
  PP       :: #import "Program_Print";
  Compiler :: #import "Compiler";
  code_node := Compiler.compiler_get_nodes(code);
  builder: String_Builder;
  PP.print_expression(*builder, code_node);
  return builder_to_string(*builder, allocator=temp);
}


using #import "Hash_Table";
operator [] :: (t: Table(string, string), index: string) -> string {
  result, found := table_find(*t, index);
  if !found return "";
  return result;
}
operator []= :: (t: *Table(string, string), index: string, value: string) {;
  table_add(t, index, value);
}




OneLine :: ($str: string) -> string {return #run dedent(str, glue=" "); }
Dedent :: ($str: string) -> string {return #run dedent(str); }
dedent :: (_str: string, glue := "\n") -> string {
  #import "String";

  if _str.count == 0 return "";

  // if the last character in the string is a newline, remove the trailing newline
  str := _str;
  if str[str.count-1] == #char"\n" str.count -= 1;

  // if there's only 1 line... just return it trimmed
  lines := split(str, "\n");
  if lines.count == 1 return trim(lines[0]);

  // figure how much indentation we need to remove from each line
  min_indent := count_leading_spaces(lines[0]);
  for line: lines {
    min_indent = min(min_indent, count_leading_spaces(line));
  }

  // remove the indentation, build the new string
  builder: String_Builder;
  for line: lines {
    spaces_to_eat := min(line.count, min_indent);
    append(*builder, slice(line, spaces_to_eat, line.count-spaces_to_eat));
    if it_index == lines.count-1 break;
    append(*builder, glue);
  }
  return builder_to_string(*builder);


  count_leading_spaces :: (str: string) -> int {
    for i: 0 .. str.count-1 {
      if str[i] != #char" " return i;
    }
    return str.count;
  }
}







#if OS == .WINDOWS {
  #scope_file
  #import "Windows";
  kernel32 :: #system_library "kernel32";
  stdinhandle: HANDLE;
  ReadConsoleA :: (hConsoleHandle: HANDLE, buff : *u8, chars_to_read : s32,  chars_read : *s32, lpInputControl := *void ) -> BOOL #foreign kernel32;

  #scope_export
  stdin :: (allocator: Allocator = .{}) -> string {
    if !stdinhandle  stdinhandle = GetStdHandle( STD_INPUT_HANDLE );

    MAX_BYTES_TO_READ :: 1024;
    temp : [MAX_BYTES_TO_READ] u8;
    result: string = ---;
    bytes_read : s32;

    if !ReadConsoleA( stdinhandle, temp.data, xx temp.count, *bytes_read ) return "";

    bytes_read -= 2; // remove the \r\n at the end

    result.data  = alloc(bytes_read, allocator);
    result.count = bytes_read;
    memcpy(result.data, temp.data, bytes_read);
    return result;
  }
}
#if OS == .LINUX {
  #scope_file
  #import "POSIX";
  #scope_export
  stdin :: (allocator: Allocator = .{}) -> string {
    temp: [4096] u8;
    bytes_read := read(STDIN_FILENO, temp.data, temp.count-1);

    bytes_read -= 1; // remove the \n at the end

    result: string = ---;
    result.data  = alloc(bytes_read, allocator);
    result.count = bytes_read;
    memcpy(result.data, temp.data, bytes_read);
    return result;
  }
}

#import "Curl";
// Allocates response_body using context.allocator
request :: (url: string, data := "", method := "", headers := string.[], include_headers := false, follow_redirects := true, timeout_seconds := 0) -> response_body: string, response_code: int, curl_code: CURLcode {

  size_t :: u64;
  write_callback :: (ptr: *u8, size: size_t, nmemb: size_t, userdata: *void) -> size_t #c_call {
    builder := cast(*String_Builder)userdata;
    jai_context: #Context;
    push_context jai_context {
        append(builder, ptr, xx nmemb);
    }
    return nmemb;
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

  if headers.count {
    slist: *curl_slist;
    for headers  slist = curl_slist_append(slist, temp_c_string(it));
    curl_easy_setopt(curl, .HTTPHEADER, slist);
  }

  builder: String_Builder;
  defer free_buffers(*builder);
  curl_easy_setopt(curl, .WRITEFUNCTION, write_callback);
  curl_easy_setopt(curl, .WRITEDATA,     *builder);

  // i was getting the error PEER_FAILED_VERIFICATION
  curl_easy_setopt(curl, .SSL_VERIFYPEER, 0);
  curl_easy_setopt(curl, .SSL_VERIFYHOST, 0);

  // actually execute the request. this is blocking
  curl_code: CURLcode = curl_easy_perform(curl);

  response_code: int;
  if curl_code == .OK  curl_easy_getinfo(curl, .RESPONSE_CODE, *response_code);

  response_body: string = builder_to_string(*builder);

  return response_body, response_code, curl_code;
}
