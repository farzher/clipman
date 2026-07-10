#import "Basic";
File :: #import "File";
W    :: #import "Windows";
Pack :: #import "compress_exe";

payload :: #run File.read_entire_file(Pack.PAYLOAD_PATH);

IMAGE_DIRECTORY_ENTRY_IMPORT    :: 1;
IMAGE_DIRECTORY_ENTRY_EXCEPTION :: 3;
IMAGE_DIRECTORY_ENTRY_BASERELOC :: 5;
IMAGE_DIRECTORY_ENTRY_TLS       :: 9;
IMAGE_REL_BASED_DIR64           :: 10;
IMAGE_ORDINAL_FLAG64            :: cast(u64)0x8000000000000000;
PAYLOAD_STATIC_TLS_INDEX        :: cast(u32) 0;

IMAGE_SCN_MEM_EXECUTE :: 0x20000000;
IMAGE_SCN_MEM_READ    :: 0x40000000;
IMAGE_SCN_MEM_WRITE   :: 0x80000000;

COMPRESS_ALGORITHM_LZMS :: 5;

cabinet  :: #library,system "Cabinet";
kernel32 :: #library,system "kernel32";
CreateDecompressor   :: (algorithm: u32, allocation_routines: *void, decompressor_handle: **void) -> s32 #foreign cabinet;
Decompress           :: (decompressor_handle: *void, compressed_data: *void, compressed_data_size: u64, uncompressed_buffer: *void, uncompressed_buffer_size: u64, uncompressed_data_size: *u64) -> s32 #foreign cabinet;
CloseDecompressor     :: (decompressor_handle: *void) -> s32 #foreign cabinet;
FlushInstructionCache :: (process: *void, base_address: *void, size: u64) -> s32 #foreign kernel32;
RtlAddFunctionTable    :: (function_table: *void, entry_count: u32, base_address: u64) -> s32 #foreign kernel32;
RtlDeleteFunctionTable :: (function_table: *void) -> s32 #foreign kernel32;

ntdll :: #library,system "ntdll";

THREAD_BASIC_INFORMATION :: struct {
  exit_status              : s32;
  teb_base_address         : *u8;
  client_id_unique_process : *void;
  client_id_unique_thread  : *void;
  affinity_mask            : u64;
  priority                 : s32;
  base_priority            : s32;
}

THREAD_BASIC_INFORMATION_CLASS          :: 0;
CURRENT_THREAD_HANDLE                    :: cast(*void) -2;
TEB_THREAD_LOCAL_STORAGE_POINTER_OFFSET  :: 0x58; // x64 TEB.ThreadLocalStoragePointer

NtQueryInformationThread :: (thread_handle: *void, thread_information_class: u32, thread_information: *void, thread_information_length: u32, return_length: *u32) -> s32 #foreign ntdll;

main :: () {
  // decompress our normal exe into memory
  decompressor: *void;
  if CreateDecompressor(COMPRESS_ALGORITHM_LZMS, null, *decompressor) == 0 return;
  defer CloseDecompressor(decompressor);

  unpacked_size: u64;
  Decompress(decompressor, payload.data, xx payload.count, null, 0, *unpacked_size);
  if unpacked_size == 0 return;

  unpacked := alloc(xx unpacked_size);
  bytes_written: u64;
  if Decompress(decompressor, payload.data, xx payload.count, unpacked, unpacked_size, *bytes_written) == 0 return;
  if bytes_written != unpacked_size return;

  run_pe_from_memory(cast(*u8)unpacked, xx unpacked_size);
}

run_pe_from_memory :: (pe: *u8, pe_size: s64) -> bool {
  // read the pe headers
  if pe_size < 0x40 || read_u16(pe, 0) != 0x5a4d return false; // MZ

  nt := read_u32(pe, 0x3c);
  if !range_fits(nt, 24, xx pe_size) || read_u32(pe, nt) != 0x00004550 return false; // PE\0\0

  coff := nt + 4;
  number_of_sections     := read_u16(pe, coff + 2);
  size_of_optional_header := read_u16(pe, coff + 16);

  opt := coff + 20;
  section_table_size := cast(u64)number_of_sections * 40;
  if number_of_sections == 0 || size_of_optional_header < 240 return false;
  if !range_fits(opt, size_of_optional_header, xx pe_size) return false;
  if !range_fits(opt + xx size_of_optional_header, section_table_size, xx pe_size) return false;
  if read_u16(pe, opt) != 0x20b return false; // PE32+

  entry_rva       := read_u32(pe, opt + 16);
  preferred_base  := read_u64(pe, opt + 24);
  size_of_image   := read_u32(pe, opt + 56);
  size_of_headers := read_u32(pe, opt + 60);
  if size_of_image == 0 || !range_fits(0, size_of_headers, xx pe_size) || size_of_headers > size_of_image return false;
  if !range_fits(entry_rva, 1, size_of_image) return false;

  // try to put it where it wanted to be, otherwise we'll have to fix all its pointers later
  image := cast(*u8) W.VirtualAlloc(cast(*void)preferred_base, size_of_image, W.MEM_RESERVE | W.MEM_COMMIT, W.PAGE_READWRITE);
  if !image  image = cast(*u8) W.VirtualAlloc(null, size_of_image, W.MEM_RESERVE | W.MEM_COMMIT, W.PAGE_READWRITE);
  if !image return false;
  defer W.VirtualFree(image, 0, W.MEM_RELEASE);

  // copy the exe headers and sections into their new memory
  memcpy(image, pe, size_of_headers);

  section := opt + xx size_of_optional_header;
  for 0 .. number_of_sections-1 {
    virtual_address := read_u32(pe, section + 12);
    raw_size        := read_u32(pe, section + 16);
    raw_pointer     := read_u32(pe, section + 20);

    if raw_size {
      if !range_fits(raw_pointer, raw_size, xx pe_size) return false;
      if !range_fits(virtual_address, raw_size, size_of_image) return false;
      memcpy(image + virtual_address, pe + raw_pointer, raw_size);
    }

    section += 40;
  }

  // do all the junk windows would normally do when loading an exe
  delta := cast(s64)image - cast(s64)preferred_base;
  if delta != 0 && !apply_relocations(image, opt, size_of_image, delta) return false;
  if !resolve_imports(image, opt) return false;

  function_table, exception_table_ok := register_exception_table(image, opt, size_of_image);
  if !exception_table_ok return false;
  defer if function_table RtlDeleteFunctionTable(function_table);

  if !initialize_tls(image, opt) return false;
  if !protect_sections(image, pe, opt, size_of_image, xx size_of_optional_header, number_of_sections) return false;

  CURRENT_PROCESS_HANDLE :: cast(*void) -1;
  if FlushInstructionCache(CURRENT_PROCESS_HANDLE, image, size_of_image) == 0 return false;

  // finally call the normal exe's main function
  EntryProc :: #type () -> void;
  entry := cast(EntryProc)(image + entry_rva);
  entry();
  return true;
}

apply_relocations :: (image: *u8, opt: u32, image_size: u32, delta: s64) -> bool {
  reloc_rva  := read_u32(image, opt + 112 + IMAGE_DIRECTORY_ENTRY_BASERELOC*8 + 0);
  reloc_size := read_u32(image, opt + 112 + IMAGE_DIRECTORY_ENTRY_BASERELOC*8 + 4);
  if reloc_rva == 0 || reloc_size == 0 return false;
  if !range_fits(reloc_rva, reloc_size, image_size) return false;

  cursor := reloc_rva;
  end := reloc_rva + reloc_size;
  while cursor < end {
    if end - cursor < 8 return false;
    page_rva  := read_u32(image, cursor);
    block_size := read_u32(image, cursor + 4);
    if block_size < 8 || block_size > end - cursor return false;

    count := (block_size - 8) / 2;
    entry := cursor + 8;
    for 0 .. count-1 {
      item := read_u16(image, entry + it*2);
      typ := item >> 12;
      if typ == 0 continue; // ignore padding
      if typ != IMAGE_REL_BASED_DIR64 return false;

      patch_rva := page_rva + xx (item & 0x0fff);
      if !range_fits(patch_rva, size_of(u64), image_size) return false;
      patch := cast(*u64)(image + patch_rva);
      patch.* = xx (cast(s64)patch.* + delta);
    }

    cursor += block_size;
  }

  return cursor == end;
}

register_exception_table :: (image: *u8, opt: u32, image_size: u32) -> (*void, bool) {
  table_rva  := read_u32(image, opt + 112 + IMAGE_DIRECTORY_ENTRY_EXCEPTION*8 + 0);
  table_size := read_u32(image, opt + 112 + IMAGE_DIRECTORY_ENTRY_EXCEPTION*8 + 4);
  if table_rva == 0 || table_size == 0 return null, true;

  RUNTIME_FUNCTION_SIZE :: 12;
  if table_size % RUNTIME_FUNCTION_SIZE != 0 return null, false;
  if !range_fits(table_rva, table_size, image_size) return null, false;

  table := image + table_rva;
  count := table_size / RUNTIME_FUNCTION_SIZE;
  success := RtlAddFunctionTable(table, count, cast(u64)image) != 0;
  return table, success;
}

initialize_tls :: (image: *u8, opt: u32) -> bool {
  tls_rva  := read_u32(image, opt + 112 + IMAGE_DIRECTORY_ENTRY_TLS*8 + 0);
  tls_size := read_u32(image, opt + 112 + IMAGE_DIRECTORY_ENTRY_TLS*8 + 4);
  if tls_rva == 0 || tls_size == 0 return true;

  // these are VAs and apply_relocations has already fixed them for us
  start_raw            := read_u64(image, tls_rva + 0);
  end_raw              := read_u64(image, tls_rva + 8);
  address_of_index     := read_u64(image, tls_rva + 16);
  address_of_callbacks := read_u64(image, tls_rva + 24);
  size_of_zero_fill    := read_u32(image, tls_rva + 32);

  // the normal exe uses static tls index 0
  // TlsAlloc is different dynamic tls and won't work here
  tls_index := PAYLOAD_STATIC_TLS_INDEX;
  (cast(*u32)address_of_index).* = tls_index;

  raw_size := end_raw - start_raw;
  block_size := raw_size + xx size_of_zero_fill;
  if block_size {
    tls_block := alloc(xx block_size);
    memset(tls_block, 0, xx block_size);
    if raw_size memcpy(tls_block, cast(*void)start_raw, xx raw_size);
    if !set_static_tls_value_for_current_thread(tls_index, tls_block) return false;
  }

  if address_of_callbacks {
    Callback :: #type (module: *void, reason: u32, reserved: *void) -> void #c_call;
    callback_ptr := cast(**void)address_of_callbacks;
    while callback_ptr.* {
      callback := cast(Callback)callback_ptr.*;
      callback(image, W.DLL_PROCESS_ATTACH, null);
      callback_ptr += 1;
    }
  }

  return true;
}

set_static_tls_value_for_current_thread :: (tls_index: u32, tls_block: *void) -> bool {
  info: THREAD_BASIC_INFORMATION;
  status := NtQueryInformationThread(CURRENT_THREAD_HANDLE, THREAD_BASIC_INFORMATION_CLASS, *info, size_of(THREAD_BASIC_INFORMATION), null);
  if status < 0 || !info.teb_base_address return false;

  vector := (cast(***void)(info.teb_base_address + TEB_THREAD_LOCAL_STORAGE_POINTER_OFFSET)).*;
  if !vector return false;

  (vector + tls_index).* = tls_block;
  return true;
}

// load the dlls and functions used by the normal exe
resolve_imports :: (image: *u8, opt: u32) -> bool {
  import_rva := read_u32(image, opt + 112 + IMAGE_DIRECTORY_ENTRY_IMPORT*8 + 0);
  if import_rva == 0 return true;

  desc := import_rva;
  while read_u32(image, desc + 12) != 0 {
    dll_name := image + read_u32(image, desc + 12);
    module := W.LoadLibraryA(dll_name);
    if !module return false;

    original_first_thunk := read_u32(image, desc + 0);
    first_thunk          := read_u32(image, desc + 16);
    if original_first_thunk == 0 original_first_thunk = first_thunk;

    lookup := original_first_thunk;
    thunk  := first_thunk;
    while read_u64(image, lookup) != 0 {
      thunk_value := read_u64(image, lookup);
      proc: *void;
      if (thunk_value & IMAGE_ORDINAL_FLAG64) != 0 {
        ordinal := cast(*u8)(thunk_value & 0xffff);
        proc = W.GetProcAddress(module, ordinal);
      } else {
        import_by_name := image + thunk_value;
        proc = W.GetProcAddress(module, import_by_name + 2);
      }
      if !proc return false;

      (cast(*u64)(image + thunk)).* = cast(u64)proc;
      lookup += 8;
      thunk += 8;
    }

    desc += 20;
  }

  return true;
}

// set the memory permissions that each exe section wanted
protect_sections :: (image: *u8, pe: *u8, opt: u32, image_size: u32, size_of_optional_header: u16, number_of_sections: u16) -> bool {
  section := opt + xx size_of_optional_header;
  for 0 .. number_of_sections-1 {
    virtual_size    := read_u32(pe, section + 8);
    virtual_address := read_u32(pe, section + 12);
    raw_size        := read_u32(pe, section + 16);
    characteristics := read_u32(pe, section + 36);

    size := max(virtual_size, raw_size);
    if size {
      if !range_fits(virtual_address, size, image_size) return false;
      old: u32;
      if !W.VirtualProtect(image + virtual_address, size, section_protection(characteristics), *old) return false;
    }

    section += 40;
  }
  return true;
}

section_protection :: (characteristics: u32) -> u32 {
  executable := (characteristics & IMAGE_SCN_MEM_EXECUTE) != 0;
  readable   := (characteristics & IMAGE_SCN_MEM_READ)    != 0;
  writable   := (characteristics & IMAGE_SCN_MEM_WRITE)   != 0;

  if executable {
    if writable return W.PAGE_EXECUTE_READWRITE;
    if readable return W.PAGE_EXECUTE_READ;
    return W.PAGE_EXECUTE;
  }

  if writable return W.PAGE_READWRITE;
  if readable return W.PAGE_READONLY;
  return W.PAGE_NOACCESS;
}

range_fits :: (offset: u64, count: u64, total: u64) -> bool {
  return offset <= total && count <= total - offset;
}

read_u16 :: (base: *u8, offset: u32) -> u16 { return (cast(*u16)(base + offset)).*; }
read_u32 :: (base: *u8, offset: u32) -> u32 { return (cast(*u32)(base + offset)).*; }
read_u64 :: (base: *u8, offset: u32) -> u64 { return (cast(*u64)(base + offset)).*; }
