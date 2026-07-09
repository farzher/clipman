#if true { // encryption
  sqlite3       :: #library,no_dll "win/sqlcipher_static"; // SQLCipher static lib, built by src/modules/sqlcipher/build_sqlcipher_static.bat
  bcrypt        :: #library,system "bcrypt"; // SQLCipher static provider uses Windows CNG
  BCryptGenRandom :: (hAlgorithm: *void, pbBuffer: *void, cbBuffer: u32, dwFlags: u32) -> s32 #foreign bcrypt;
  force_link_system_libs :: () { BCryptGenRandom(null, null, 0, 0); }
  sqlite3_key   :: (db: *sqlite3db, pkey: *void, nkey: s32) -> s32 #foreign sqlite3;
  sqlite3_rekey :: (db: *sqlite3db, pkey: *void, nkey: s32) -> s32 #foreign sqlite3;
} else {
  sqlite3       :: #library "win/sqlite3";
}

sqlite3_libversion        :: () -> *u8 #foreign sqlite3;
sqlite3_sourceid          :: () -> *u8 #foreign sqlite3;
sqlite3_libversion_number :: () -> s32 #foreign sqlite3;

sqlite3_open              :: (filename: *u8, **sqlite3db) -> s32 #foreign sqlite3;
sqlite3_close             :: (db: *sqlite3db) -> s32 #foreign sqlite3;

sqlite3_prepare_v2        :: (db: *sqlite3db, sql: *u8, maxbytesofsql: s32, **sqlite3_stmt, pzTail: **u8) -> s32 #foreign sqlite3;
sqlite3_step              :: (stmt: *sqlite3_stmt) -> s32 #foreign sqlite3;
sqlite3_column_text       :: (stmt: *sqlite3_stmt, s32) -> *u8 #foreign sqlite3;
sqlite3_column_blob       :: (stmt: *sqlite3_stmt, s32) -> *void #foreign sqlite3;
sqlite3_column_bytes      :: (stmt: *sqlite3_stmt, s32) -> s32 #foreign sqlite3;
sqlite3_column_int        :: (stmt: *sqlite3_stmt, s32) -> s32 #foreign sqlite3;
sqlite3_column_int64      :: (stmt: *sqlite3_stmt, s32) -> s64 #foreign sqlite3;
sqlite3_finalize          :: (stmt: *sqlite3_stmt) -> s32 #foreign sqlite3;
sqlite3_exec              :: (db: *sqlite3db, sql: *u8, cb: (notused: *void, argc: s32, argv: **u8, azcolname: **u8)->s32 #c_call, *void, errmsg: **u8) -> s32 #foreign sqlite3;

sqlite3_bind_int          :: (stmt: *sqlite3_stmt, s32, s32) -> s32 #foreign sqlite3;
sqlite3_bind_int64        :: (stmt: *sqlite3_stmt, s32, s64) -> s32 #foreign sqlite3;
sqlite3_bind_text         :: (stmt: *sqlite3_stmt, index: s32, str: *u8, strlen: s32, *void) -> s32 #foreign sqlite3;

sqlite3_errmsg            :: (db: *sqlite3db) -> *u8 #foreign sqlite3;

sqlite3db    :: struct {};
sqlite3_stmt :: struct {};
SQLITE_OK    :: 0;
SQLITE_ROW   :: 100;
SQLITE_DONE  :: 101;
