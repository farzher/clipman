#import "Basic";
#import "Compiler";
File :: #import "File";

STUB_FILEPATH :: #run tprint("%/packed_stub.jai", #filepath);
PAYLOAD_PATH  :: #run tprint("%/payload.lzms", #filepath);

// compile the normal exe first so we can compress it, then compile the stub
// using the normal exe's name
compress_exe :: (root_path: string, main_filepath: string, options: *Build_Options) {
  build_options := options.*; // don't leave the caller's options pointing at temporary data
  build_options.output_path = path_from_root(root_path, build_options.output_path);

  absolute_import_paths: [..]string;
  for build_options.import_path array_add(*absolute_import_paths, path_from_root(root_path, it));
  build_options.import_path = absolute_import_paths;

  packed_exe_name   := build_options.output_executable_name;
  unpacked_exe_name := tprint("%.unpacked", packed_exe_name);
  unpacked_exe_path := path_join(build_options.output_path, tprint("%.exe", unpacked_exe_name));

  cleanup(unpacked_exe_path); // cleanup junk from an interrupted build

  build_options.output_executable_name = unpacked_exe_name;
  if !compile_in_new_workspace(build_options, path_from_root(root_path, main_filepath)) {
    cleanup(unpacked_exe_path);
    assert(false, "Failed to compile unpacked executable");
    return;
  }

  if !pack(unpacked_exe_path) {
    cleanup(unpacked_exe_path);
    assert(false, "Failed to compress executable");
    return;
  }

  build_options.output_executable_name = packed_exe_name;
  packed_ok := compile_in_new_workspace(build_options, STUB_FILEPATH);
  cleanup(unpacked_exe_path);
  assert(packed_ok, "Failed to compile packed executable");
}

path_from_root :: (root_path: string, path: string) -> string {
  if path == "" return path;
  if path.count >= 2 && path[1] == #char":" return path;
  if path[0] == #char"/" || path[0] == #char"\\" return path;
  return path_join(root_path, path);
}

path_join :: (directory: string, filename: string) -> string {
  if directory == "" return filename;
  last := directory[directory.count-1];
  if last == #char"/" || last == #char"\\" return tprint("%%", directory, filename);
  return tprint("%/%", directory, filename);
}

compile_in_new_workspace :: (options: Build_Options, src_files: ..string) -> bool {
  workspace := compiler_create_workspace();
  set_build_options(options, workspace);

  compiler_begin_intercept(workspace);
  for src_files add_build_file(it, workspace);

  succeeded := false;
  while true {
    message := compiler_wait_for_message();
    if !message || message.workspace != workspace continue;
    if message.kind != .COMPLETE continue;

    complete := cast(*Message_Complete) message;
    succeeded = complete.error_code == .NONE;
    break;
  }

  compiler_end_intercept(workspace);
  compiler_destroy_workspace(workspace);
  return succeeded;
}

pack :: (exe_path: string) -> bool {
  exe_bytes, read_ok := File.read_entire_file(exe_path);
  if !read_ok || exe_bytes.count == 0 {
    log_error("Could not read executable '%'.\n", exe_path);
    return false;
  }
  defer free(exe_bytes);

  compressor: *void;
  ok := CreateCompressor(COMPRESS_ALGORITHM_LZMS, null, *compressor);
  if ok == 0 {
    log_error("LZMS compressor creation failed.\n");
    return false;
  }
  defer CloseCompressor(compressor);

  compressed_count: u64;
  Compress(compressor, exe_bytes.data, xx exe_bytes.count, null, 0, *compressed_count);
  if compressed_count == 0 {
    log_error("LZMS compressed size probe failed.\n");
    return false;
  }

  compressed := alloc(xx compressed_count);
  defer free(compressed);
  ok = Compress(compressor, exe_bytes.data, xx exe_bytes.count, compressed, compressed_count, *compressed_count);
  if ok == 0 || compressed_count == 0 {
    log_error("LZMS compression failed.\n");
    return false;
  }

  if !File.write_entire_file(PAYLOAD_PATH, compressed, xx compressed_count) {
    log_error("Could not write packed payload '%'.\n", PAYLOAD_PATH);
    return false;
  }

  ratio := cast(float)exe_bytes.count / cast(float)compressed_count;
  print("Packed payload: % -> % bytes (%x smaller)\n", exe_bytes.count, compressed_count, formatFloat(ratio, trailing_width=2, zero_removal=.NO));
  return true;
}

COMPRESS_ALGORITHM_LZMS :: 5;

cabinet :: #library,system "Cabinet";
CreateCompressor :: (algorithm: u32, allocation_routines: *void, compressor_handle: **void) -> s32 #foreign cabinet;
Compress         :: (compressor_handle: *void, uncompressed_data: *void, uncompressed_data_size: u64, compressed_buffer: *void, compressed_buffer_size: u64, compressed_data_size: *u64) -> s32 #foreign cabinet;
CloseCompressor  :: (compressor_handle: *void) -> s32 #foreign cabinet;

cleanup :: (unpacked_exe_path: string) {
  File.file_delete(unpacked_exe_path);
  File.file_delete(PAYLOAD_PATH);
}
