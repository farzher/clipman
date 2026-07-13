#import,dir "sqlcipher";
#import "Basic";
#import,file "mybasic.jai";

BOOL  :: s32;
DWORD :: u32;
DeleteFileA :: (filename: *u8) -> BOOL #foreign kernel32;
CopyFileA   :: (existing_filename: *u8, new_filename: *u8, fail_if_exists: BOOL) -> BOOL #foreign kernel32;
MoveFileExA :: (existing_filename: *u8, new_filename: *u8, flags: DWORD) -> BOOL #foreign kernel32;
GetLastError :: () -> DWORD #foreign kernel32;
MOVEFILE_REPLACE_EXISTING :: 0x00000001;
MOVEFILE_COPY_ALLOWED      :: 0x00000002;

// if you need to open multiple db at the same time, use this module param
// to load a separate instane of this module, which will have a separate db.
#module_parameters(id: string = "");

db: *sqlite3db;
is_encrypted := false;

open :: (filename: *u8) -> err: bool {
  // TODO: if the file doesn't exist it creates a db for you and does not error. this isn't always what i want
  force_link_system_libs();
  err : bool = xx sqlite3_open(filename, *db);
  if err then mylog("open error:", to_string(sqlite3_errmsg(db)));
  return err;
}
close :: () -> bool {
  result := sqlite3_close(db);
  if result != SQLITE_OK {
    mylog("sqlite3_close failed:", result, to_string(sqlite3_errmsg(db)));
    return false;
  }
  return true;
}

open_and_unlock :: (filename: string, password: string = "", remembered_password: string = "") -> bool {
  is_encrypted = false;

  open(temp_c_string(filename));
  if query("select 1 from sqlite_master") return true;

  close();
  open(temp_c_string(filename));

  password_to_try := ifx password then password else remembered_password;
  if password_to_try then key(password_to_try);

  unlocked := query("select 1 from sqlite_master");
  if unlocked is_encrypted = password_to_try != "";
  return unlocked;
}

key :: (password: string) -> bool { return sqlite3_key(db, password.data, xx password.count) == SQLITE_OK; }
rekey :: (password: string) -> bool { return sqlite3_rekey(db, password.data, xx password.count) == SQLITE_OK; }

replace_db_file :: (filename: string, replacement_filename: string) -> bool {
  if !close() return false;

  moved := MoveFileExA(temp_c_string(replacement_filename), temp_c_string(filename), MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED);
  if moved return true;

  move_error := GetLastError();

  // Fallback for cases where rename/replace fails but overwrite-copy is allowed.
  copied := CopyFileA(temp_c_string(replacement_filename), temp_c_string(filename), 0);
  if copied {
    DeleteFileA(temp_c_string(replacement_filename));
    return true;
  }

  mylog("failed to replace database file. MoveFileEx error:", move_error, "CopyFile error:", GetLastError());
  return false;
}

export_and_replace_db :: (filename: string, suffix: string, replacement_password: string) -> bool {
  tmp_filename := tprint("%%", filename, suffix);
  DeleteFileA(temp_c_string(tmp_filename));

  success := query("ATTACH DATABASE ? AS replacement KEY ?", tmp_filename, replacement_password);
  success = success && query("SELECT sqlcipher_export('replacement')");
  success = query("DETACH DATABASE replacement") && success;
  if !success {
    mylog("failed to export replacement database");
    DeleteFileA(temp_c_string(tmp_filename));
    return false;
  }

  replaced := replace_db_file(filename, tmp_filename);
  open(temp_c_string(filename));
  return replaced;
}

encrypt_with_password :: (filename: string, password: string) -> bool {
  // Empty password means remove encryption. SQLCipher can't use rekey("") for
  // this, so export into a new plaintext DB and replace the encrypted file.
  if password.count == 0 {
    if !is_encrypted return true;

    if !export_and_replace_db(filename, ".decrypted", "") {
      is_encrypted = true;
      return false;
    }

    is_encrypted = false;
    return query("select 1 from sqlite_master");
  }

  // Already-encrypted DBs can use SQLCipher's rekey API.
  if is_encrypted {
    success := rekey(password);
    if !success mylog("failed to rekey encrypted database");
    return success;
  }

  // Plaintext -> encrypted must be done by exporting into a new keyed DB.
  if !export_and_replace_db(filename, ".encrypted", password) return false;

  key(password);
  is_encrypted = query("select 1 from sqlite_master");
  return is_encrypted;
}

select :: (sql: *u8, binds: .. Any) -> *sqlite3_stmt {

  res: *sqlite3_stmt;

  sqlite3_prepare_v2(db, sql, -1, *res, null);

  for binds {
    if it.type.type == {
      case .INTEGER;
        intinfo := cast(*Type_Info_Integer) it.type;
        isint := intinfo.runtime_size == 8 && intinfo.signed;
        assert(isint, "must be an int");

        set_int(res, it_index+1, (.*)cast(*int)   it.value_pointer);
      case .STRING;     set_str(res, it_index+1, (.*)cast(*string)it.value_pointer);
      case; assert(false, "unknown bind type");
    }
  }

  return res;

}

select_int :: (sql: *u8, binds: .. Any, default := 0) -> int {
  for select(sql, ..binds)  return get_int(it, 0);
  return default;
}

query :: (sql: *u8, binds: .. Any) -> bool {
  res := select(sql, ..binds);
  defer free(res);

  errcode := sqlite3_step(res);
  if errcode == SQLITE_OK || errcode == SQLITE_ROW || errcode == SQLITE_DONE return true;

  mylog(to_string(sqlite3_errmsg(db)));
  mylog(to_string(sql));
  return false;
}

set_str :: (res: *sqlite3_stmt, i: int, str: string) { sqlite3_bind_text(res, xx i, temp_c_string(str), xx str.count, null); }
set_int :: (res: *sqlite3_stmt, i: int, v: int)      { sqlite3_bind_int64(res, xx i, v); }
get_int :: (res: *sqlite3_stmt, coli: int) -> int    { return sqlite3_column_int64(res, xx coli); }
get_txt :: (res: *sqlite3_stmt, coli: int) -> string { return copy_string(to_string(sqlite3_column_text(res, xx coli))); }
get_str :: (res: *sqlite3_stmt, coli: int) -> string {
  str := alloc_string(sqlite3_column_bytes(res, xx coli));
  memcpy(str.data, sqlite3_column_blob(res, xx coli), str.count);
  return str;
}
free :: (res: *sqlite3_stmt) { sqlite3_finalize(res); }

for_expansion :: (res: *sqlite3_stmt, body: Code, flags: For_Flags) #expand {
  `it_index := 0;
  `it := res;
  defer free(res);
  while sqlite3_step(res) == SQLITE_ROW { defer `it_index += 1;
    #insert body;
  }
}
