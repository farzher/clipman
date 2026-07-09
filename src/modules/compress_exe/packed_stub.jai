#import "Basic";
File    :: #import "File";
String  :: #import "String";
W       :: #import "Windows";
Pack    :: #import "compress_exe";

PAYLOAD_UNPACKED_SIZE :: #run get_payload_unpacked_size();
payload :: #run File.read_entire_file(Pack.PAYLOAD_PATH);

IMAGE_DIRECTORY_ENTRY_IMPORT   :: 1;
IMAGE_DIRECTORY_ENTRY_BASERELOC :: 5;
IMAGE_DIRECTORY_ENTRY_TLS       :: 9;
IMAGE_REL_BASED_DIR64          :: 10;
IMAGE_ORDINAL_FLAG64           :: cast(u64)0x8000000000000000;
PAYLOAD_STATIC_TLS_INDEX       :: cast(u32) 0;

IMAGE_SCN_MEM_EXECUTE :: 0x20000000;
IMAGE_SCN_MEM_READ    :: 0x40000000;
IMAGE_SCN_MEM_WRITE   :: 0x80000000;

COMPRESS_ALGORITHM_LZMS :: 5;

cabinet  :: #library,system "Cabinet";
kernel32 :: #library,system "kernel32";
CreateDecompressor :: (Algorithm: u32, AllocationRoutines: *void, DecompressorHandle: **void) -> s32 #foreign cabinet;
Decompress         :: (DecompressorHandle: *void, CompressedData: *void, CompressedDataSize: u64, UncompressedBuffer: *void, UncompressedBufferSize: u64, UncompressedDataSize: *u64) -> s32 #foreign cabinet;
CloseDecompressor  :: (DecompressorHandle: *void) -> s32 #foreign cabinet;

ntdll :: #library,system "ntdll";

THREAD_BASIC_INFORMATION :: struct {
  ExitStatus: s32;
  TebBaseAddress: *u8;
  ClientId_UniqueProcess: *void;
  ClientId_UniqueThread: *void;
  AffinityMask: u64;
  Priority: s32;
  BasePriority: s32;
}

ThreadBasicInformation :: 0;
CURRENT_THREAD_HANDLE  :: cast(*void) -2;
TEB_THREAD_LOCAL_STORAGE_POINTER_OFFSET :: 0x58; // x64 TEB.ThreadLocalStoragePointer

NtQueryInformationThread :: (ThreadHandle: *void, ThreadInformationClass: u32, ThreadInformation: *void, ThreadInformationLength: u32, ReturnLength: *u32) -> s32 #foreign ntdll;

main :: () {
  set_cwd_to_exe_location();

  unpacked := alloc(PAYLOAD_UNPACKED_SIZE);

  decompressor: *void;
  ok := CreateDecompressor(COMPRESS_ALGORITHM_LZMS, null, *decompressor);
  if ok == 0 {
    print("clipman packer: decompressor creation failed\n");
    return;
  }
  defer CloseDecompressor(decompressor);

  compressed_data  := payload.data + size_of(u64);
  compressed_count := payload.count - size_of(u64);

  bytes_written: u64;
  ok = Decompress(decompressor, compressed_data, xx compressed_count, unpacked, xx PAYLOAD_UNPACKED_SIZE, *bytes_written);
  if ok == 0 || bytes_written != xx PAYLOAD_UNPACKED_SIZE {
    print("clipman packer: decompression failed (got %, wanted %)\n", bytes_written, PAYLOAD_UNPACKED_SIZE);
    return;
  }

  launch_ok := run_pe_from_memory(cast(*u8) unpacked);
  if !launch_ok print("clipman packer: in-memory launch failed\n");
}

run_pe_from_memory :: (pe: *u8) -> bool {
  if read_u16(pe, 0) != 0x5a4d return false; // MZ

  nt := read_u32(pe, 0x3c);
  if read_u32(pe, nt) != 0x00004550 return false; // PE\0\0

  coff := nt + 4;
  number_of_sections := read_u16(pe, coff + 2);
  size_of_optional_header := read_u16(pe, coff + 16);

  opt := coff + 20;
  if read_u16(pe, opt) != 0x20b return false; // PE32+

  entry_rva       := read_u32(pe, opt + 16);
  preferred_base  := read_u64(pe, opt + 24);
  size_of_headers := read_u32(pe, opt + 60);
  size_of_image   := read_u32(pe, opt + 56);

  image := cast(*u8) W.VirtualAlloc(null, xx size_of_image, W.MEM_RESERVE | W.MEM_COMMIT, W.PAGE_READWRITE);
  if !image return false;

  memcpy(image, pe, size_of_headers);

  section := opt + xx size_of_optional_header;
  for 0 .. number_of_sections-1 {
    virtual_size    := read_u32(pe, section + 8);
    virtual_address := read_u32(pe, section + 12);
    raw_size        := read_u32(pe, section + 16);
    raw_pointer     := read_u32(pe, section + 20);

    if raw_size > 0 {
      memcpy(image + virtual_address, pe + raw_pointer, raw_size);
    }

    section += 40;
  }

  delta := cast(s64) image - cast(s64) preferred_base;
  if delta != 0 {
    if !apply_relocations(image, opt, delta) return false;
  }

  if !resolve_imports(image, opt) return false;
  if !initialize_tls(image, opt) return false;

  protect_sections(image, pe, opt, xx size_of_optional_header, number_of_sections);

  EntryProc :: #type () -> void;
  entry := cast(EntryProc) (image + entry_rva);
  entry();

  return true;
}

apply_relocations :: (image: *u8, opt: u32, delta: s64) -> bool {
  reloc_rva  := read_u32(image, opt + 112 + IMAGE_DIRECTORY_ENTRY_BASERELOC*8 + 0);
  reloc_size := read_u32(image, opt + 112 + IMAGE_DIRECTORY_ENTRY_BASERELOC*8 + 4);
  if reloc_rva == 0 || reloc_size == 0 return delta == 0;

  cursor := reloc_rva;
  end := reloc_rva + reloc_size;
  while cursor < end {
    page_rva := read_u32(image, cursor + 0);
    block_size := read_u32(image, cursor + 4);
    if block_size < 8 break;

    count := (block_size - 8) / 2;
    entry := cursor + 8;
    for 0 .. count-1 {
      item := read_u16(image, entry + it*2);
      typ := item >> 12;
      off := item & 0x0fff;
      if typ == IMAGE_REL_BASED_DIR64 {
        patch := cast(*u64) (image + (page_rva + xx off));
        patch.* = xx (cast(s64) patch.* + delta);
      }
    }

    cursor += block_size;
  }

  return true;
}

initialize_tls :: (image: *u8, opt: u32) -> bool {
  tls_rva  := read_u32(image, opt + 112 + IMAGE_DIRECTORY_ENTRY_TLS*8 + 0);
  tls_size := read_u32(image, opt + 112 + IMAGE_DIRECTORY_ENTRY_TLS*8 + 4);
  if tls_rva == 0 || tls_size == 0 return true;

  // PE TLS directory fields are VAs, not RVAs. apply_relocations() has already
  // fixed them up for this manually mapped image.
  start_raw            := read_u64(image, tls_rva + 0);
  end_raw              := read_u64(image, tls_rva + 8);
  address_of_index     := read_u64(image, tls_rva + 16);
  address_of_callbacks := read_u64(image, tls_rva + 24);
  size_of_zero_fill    := read_u32(image, tls_rva + 32);

  // This image is being mapped as the effective main executable.  In a normal
  // process the main EXE's static TLS index is 0.  Do not use TlsAlloc here:
  // that allocates Win32 dynamic TLS, but MSVC/C TLS reads through
  // TEB.ThreadLocalStoragePointer[_tls_index].
  tls_index := PAYLOAD_STATIC_TLS_INDEX;
  (cast(*u32) address_of_index).* = tls_index;

  raw_size := end_raw - start_raw;
  block_size := raw_size + xx size_of_zero_fill;
  if block_size {
    tls_block := alloc(xx block_size);
    memset(tls_block, 0, xx block_size);
    if raw_size memcpy(tls_block, cast(*void) start_raw, xx raw_size);
    if !set_static_tls_value_for_current_thread(tls_index, tls_block) return false;
  }

  if address_of_callbacks {
    Callback :: #type (module: *void, reason: u32, reserved: *void) -> void #c_call;
    callback_ptr := cast(**void) address_of_callbacks;
    while callback_ptr.* {
      callback := cast(Callback) callback_ptr.*;
      callback(image, W.DLL_PROCESS_ATTACH, null);
      callback_ptr += 1;
    }
  }

  return true;
}

set_static_tls_value_for_current_thread :: (tls_index: u32, tls_block: *void) -> bool {
  info: THREAD_BASIC_INFORMATION;
  status := NtQueryInformationThread(CURRENT_THREAD_HANDLE, ThreadBasicInformation, *info, size_of(THREAD_BASIC_INFORMATION), null);
  if status < 0 || !info.TebBaseAddress return false;

  vector := (cast(***void) (info.TebBaseAddress + TEB_THREAD_LOCAL_STORAGE_POINTER_OFFSET)).*;
  if !vector return false;

  (vector + tls_index).* = tls_block;
  return true;
}

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
        ordinal := cast(*u8) (thunk_value & 0xffff);
        proc = W.GetProcAddress(module, ordinal);
      } else {
        import_by_name := image + thunk_value;
        proc = W.GetProcAddress(module, import_by_name + 2);
      }
      if !proc return false;

      (cast(*u64) (image + thunk)).* = cast(u64) proc;
      lookup += 8;
      thunk += 8;
    }

    desc += 20;
  }

  return true;
}

protect_sections :: (image: *u8, pe: *u8, opt: u32, size_of_optional_header: u16, number_of_sections: u16) {
  section := opt + xx size_of_optional_header;
  for 0 .. number_of_sections-1 {
    virtual_size    := read_u32(pe, section + 8);
    virtual_address := read_u32(pe, section + 12);
    raw_size        := read_u32(pe, section + 16);
    characteristics := read_u32(pe, section + 36);

    size := ifx virtual_size != 0 then virtual_size else raw_size;
    if size {
      old: u32;
      protect := section_protection(characteristics);
      W.VirtualProtect(image + virtual_address, xx size, protect, *old);
    }

    section += 40;
  }
}

section_protection :: (characteristics: u32) -> u32 {
  executable := (characteristics & IMAGE_SCN_MEM_EXECUTE) != 0;
  readable   := (characteristics & IMAGE_SCN_MEM_READ)    != 0;
  writable   := (characteristics & IMAGE_SCN_MEM_WRITE)   != 0;

  if executable {
    if writable return W.PAGE_EXECUTE_READWRITE;
    return W.PAGE_EXECUTE_READ;
  }

  if writable return W.PAGE_READWRITE;
  if readable return W.PAGE_READONLY;
  return W.PAGE_NOACCESS;
}

read_u16 :: (base: *u8, offset: u32) -> u16 { return (cast(*u16) (base + offset)).*; }
read_u32 :: (base: *u8, offset: u32) -> u32 { return (cast(*u32) (base + offset)).*; }
read_u64 :: (base: *u8, offset: u32) -> u64 { return (cast(*u64) (base + offset)).*; }

set_cwd_to_exe_location :: () {
  system :: #import "System";
  set_working_directory(String.path_strip_filename(system.get_path_of_running_executable()));
}

get_payload_unpacked_size :: () -> s64 {
  text := File.read_entire_file(Pack.PAYLOAD_PATH);
  assert(text.count >= size_of(u64), "Missing packed payload. Build first.jai in release mode so it can create the packed payload.");
  size := (cast(*u64) text.data).*;
  return xx size;
}
