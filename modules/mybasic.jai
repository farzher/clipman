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
