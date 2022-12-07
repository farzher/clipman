/* -farzher September 13, 2021
  just a collection of common functions i use
*/



using #import "Basic";
// #import "Basic"()(ENABLE_ASSERT=false);

#import "String";
mylog :: (args:..Any) {
  if args.count == 0 { print("\n"); return; }

  formatstr: string;
  push_tallocator();
  for args  formatstr = join(formatstr, "% ");
  formatstr[formatstr.count-1] = #char "\n"; // replace the trailing space with a newline
  print(formatstr, ..args);
}

die :: (args: ..Any) {
  mylog("[Fatal Error]");
  mylog(..args);
  exit(1);
}

// mylog :: (args: ..Any) {
//   prefix :: "[netcode] ";
//   tmp :: "% ";
//   format := talloc_string(prefix.count + args.count*tmp.count + 1/*newline*/);
//   memcpy(format.data, prefix.data, prefix.count);
//   for arg, i: args  memcpy(format.data + prefix.count + i*tmp.count, tmp.data, tmp.count);
//   format[format.count-1] = #char"\n";
//   log(format, ..args);
// }

#scope_file
Compiler :: #import "Compiler";
#scope_export
isrelease :: #run Compiler.get_build_options().optimization_level == .RELEASE;

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
    else if ratio < -1 then ratio = -1;
  }

  return bdist*ratio + to1;
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
  c.count = count;
  return c;
}

fromcstr :: (cstr: *u8) -> string {
  ret: string;
  if (cstr == null) return ret;
  ret.data = xx cstr;
  ret.count = c_style_strlen(xx cstr);
  return ret;
}

getms :: () -> float64 { return cast(float64)(get_time()*1000); }
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




// tstr
TStr :: struct {#as str: string; }
tstr: TStr;
to_tstr :: (str: string) -> TStr {
   s: TStr = ---;
   s.str = str;
   return s;
}
tstr_join :: (a:string, b:string) -> string {
    bytes := 0;
    bytes += a.count;
    bytes += b.count;
    if !bytes return "";

    result: string;
    result.count = bytes;
    result.data  = talloc(bytes);
    assert(result.data != null);

    cursor := result.data;
    memcpy(cursor, a.data, a.count);
    cursor += a.count;
    memcpy(cursor, b.data, b.count);

    cursor += b.count;
    assert(cursor == result.data + result.count);

    return result;
}
operator + :: (a: TStr, b: TStr) -> TStr {
  return to_tstr(tstr_join(a.str, b.str));
}
operator + :: (a: TStr, b: string) -> TStr #symmetric {
   return a + to_tstr(b);
}
operator + :: (a: TStr, b: int) -> TStr #symmetric {
   return to_tstr(tprint("%+%", a.str, b));
}



interp :: (_str: string) -> string #expand {
  #insert -> string {
    String :: #import "String";

    builder: String_Builder;

    str := String.replace(_str, "\n", "\\n");

    codestart := 0;
    strstart := 0;

    for i: 0 .. str.count-1 {

      //
      if (str[i] == #char"#" || str[i] == #char"%") && str[i+1] == #char"{" {

        append(*builder, tstr+ "+\""+String.slice(str, strstart, i-strstart)+"\"");

        i += 2;
        codestart = i;
        continue;
      }

      if codestart {
        if str[i] == #char"}" {
          code := String.slice(str, codestart, i-codestart);
          code = String.replace(code, "'", "\"");
          append(*builder, tstr+ "+("+code+")");
          i += 1;
          strstart = i;
          codestart = 0;
        }
      }

      if i == str.count-1 {
        append(*builder, tstr+ "+\""+String.slice(str, strstart, strstart+i+1)+"\"");
      }
    }

    return tstr+ "return tstr" + builder_to_string(*builder) + ";";
  }
}






set_cwd_to_exe_location :: () {
  system :: #import "System";
  String :: #import "String";
  set_working_directory(String.path_strip_filename(system.get_path_of_running_executable()));
}

to_c_string :: (s: string, allocator: Allocator = .{}) -> *u8 {
  result : *u8 = alloc(s.count + 1, allocator);
  memcpy(result, s.data, s.count);
  result[s.count] = 0;
  return result;
}

embed_file :: (file_path: string) -> []u8 {
  Compiler :: #import "Compiler";
  File     :: #import "File";
  return Compiler.add_global_data(xx File.read_entire_file(file_path), .READ_ONLY);
}






#scope_file
#if OS == .WINDOWS {
  #import "Windows";
  kernel32 :: #foreign_system_library "kernel32";
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
