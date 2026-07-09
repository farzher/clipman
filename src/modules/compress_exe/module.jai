#import "Basic";
#import "Compiler";
File :: #import "File";

STUB_FILEPATH :: "src/modules/compress_exe/packed_stub.jai";
PAYLOAD_PATH  :: "release/clipman.payload.lzms";
SIZE_PATH     :: "release/clipman.payload.size";

// Builds `main_filepath` as an unpacked payload, then builds the packed stub
// using the original output executable name.
compress_exe :: (root_path: string, main_filepath: string, options: *Build_Options) {
  main_filepath_full := path_from_root(root_path, main_filepath);
  options.output_path = path_from_root(root_path, options.output_path);

  absolute_import_path: [..] string;
  for options.import_path array_add(*absolute_import_path, path_from_root(root_path, it));
  options.import_path = absolute_import_path;

  packed_exe_name := options.output_executable_name;
  unpacked_exe_name := tprint("%1.unpacked", packed_exe_name);

  options.output_executable_name = unpacked_exe_name;
  unpacked_workspace := compiler_create_workspace();
  set_build_options(options.*, unpacked_workspace);
  compile_in_workspace(unpacked_workspace, main_filepath_full);

  unpacked_exe_path := tprint("%1%2.exe", options.output_path, options.output_executable_name);

  pack(unpacked_exe_path);

  options.output_executable_name = packed_exe_name;
  packed_workspace := compiler_create_workspace();
  set_build_options(options.*, packed_workspace);
  compile_in_workspace(packed_workspace, path_from_root(root_path, STUB_FILEPATH));

  cleanup(unpacked_exe_path);
}

path_from_root :: (root_path: string, path: string) -> string {
  if path == "" return path;
  if path.count >= 2 && path[1] == #char":" return path;
  if path[0] == #char"/" || path[0] == #char"\\" return path;
  return tprint("%1%2", root_path, path);
}

compile_in_workspace :: (workspace: Workspace, src_files: ..string) {
  compiler_begin_intercept(workspace);

  for src_files add_build_file(it, workspace);

  while true {
    message := compiler_wait_for_message();
    if !message continue;
    if message.workspace != workspace continue;
    if message.kind == .COMPLETE break;
  }

  compiler_end_intercept(workspace);
}

pack :: (exe_path: string) {
  exe_bytes := File.read_entire_file(exe_path);
  assert(exe_bytes != "");

  compressor: *void;
  ok := CreateCompressor(COMPRESS_ALGORITHM_LZMS, null, *compressor);
  assert(ok != 0, "LZMS compressor creation failed");
  defer CloseCompressor(compressor);

  compressed_count: u64;
  Compress(compressor, exe_bytes.data, xx exe_bytes.count, null, 0, *compressed_count);
  assert(compressed_count > 0, "LZMS compressed size probe failed");

  compressed := alloc(xx compressed_count);
  ok = Compress(compressor, exe_bytes.data, xx exe_bytes.count, compressed, compressed_count, *compressed_count);
  assert(ok != 0, "LZMS compression failed");

  File.write_entire_file(PAYLOAD_PATH, compressed, xx compressed_count);
  File.write_entire_file(SIZE_PATH, tprint("%", exe_bytes.count));

  print("Packed payload: % -> % bytes (%.2x smaller)\n", exe_bytes.count, compressed_count, cast(float)exe_bytes.count / cast(float)compressed_count);
}

COMPRESS_ALGORITHM_LZMS :: 5;

cabinet :: #library,system "Cabinet";
CreateCompressor :: (Algorithm: u32, AllocationRoutines: *void, CompressorHandle: **void) -> s32 #foreign cabinet;
Compress         :: (CompressorHandle: *void, UncompressedData: *void, UncompressedDataSize: u64, CompressedBuffer: *void, CompressedBufferSize: u64, CompressedDataSize: *u64) -> s32 #foreign cabinet;
CloseCompressor  :: (CompressorHandle: *void) -> s32 #foreign cabinet;

cleanup :: (unpacked_exe_path: string) {
  File.file_delete(unpacked_exe_path);
  File.file_delete(PAYLOAD_PATH);
  File.file_delete(SIZE_PATH);
}
