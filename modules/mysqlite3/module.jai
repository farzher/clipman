#import "sqlite3";
#import "mybasic";

#module_parameters(id: string = ""); // so we can load multiple db at the same time

db: *sqlite3db;

open :: (filename: *u8) -> err: bool {
  // TODO: if the file doesn't exist it creates a db for you and does not error. this isn't always what i want
  err : bool = xx sqlite3_open(filename, *db);
  if err then mylog("open error:", to_string(sqlite3_errmsg(db)));
  return err;
}
close :: () {
  sqlite3_close(db);
}
key :: (password: string) {sqlite3_key(db, password.data, xx password.count); }
rekey :: (password: string) {sqlite3_rekey(db, password.data, xx password.count); }

select :: (sql: *u8, binds: .. Any) -> *sqlite3_stmt {

  res: *sqlite3_stmt;

  sqlite3_prepare_v2(db, sql, -1, *res, null);

  for binds {
    if it.type.type == {
      case .INTEGER;
        intinfo := cast(*Type_Info_Integer) it.type;
        isint := intinfo.runtime_size == 8 && intinfo.signed;
        assert(isint, "must be an int");

        set_int(res, it_index+1, <<cast(*int)   it.value_pointer);
      case .STRING;     set_str(res, it_index+1, <<cast(*string)it.value_pointer);
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
  errcode := sqlite3_step(res);
  success := true;
  if errcode != SQLITE_OK && errcode != SQLITE_ROW && errcode != SQLITE_DONE {
    success = false;
    mylog(to_string(sqlite3_errmsg(db)));
    mylog(to_string(sql));
  }
  free(res);
  return success;
}



set_str :: (res: *sqlite3_stmt, i: int, str: string) {sqlite3_bind_text(res, xx i, to_c_string(str, tallocator), xx str.count, null); }
set_int :: (res: *sqlite3_stmt, i: int, v: int) {sqlite3_bind_int64(res, xx i, v); }
get_int :: (res: *sqlite3_stmt, coli: int) -> int {return sqlite3_column_int64(res, xx coli); }
get_txt :: (res: *sqlite3_stmt, coli: int) -> string {return alloc_string(to_string(sqlite3_column_text(res, xx coli))); }
get_str :: (res: *sqlite3_stmt, coli: int) -> string {
  str := alloc_string(sqlite3_column_bytes(res, xx coli));
  memcpy(str.data, sqlite3_column_blob(res, xx coli), str.count);
  return str;
}
free :: (res: *sqlite3_stmt) {sqlite3_finalize(res); }



for_expansion :: (res: *sqlite3_stmt, body: Code, flags: For_Flags) #expand {
  `it_index := 0;
  `it := res;
  while sqlite3_step(res) == SQLITE_ROW { defer `it_index += 1;
    #insert body;
  }
  free(res);
}














alloc_string :: (tmp: string, allocator: Allocator = .{}) -> string {
  str := alloc_string(tmp.count, allocator);
  memcpy(str.data, tmp.data, tmp.count);
  return str;
}
to_c_string :: (s: string, allocator: Allocator = .{}) -> *u8 {
  result : *u8 = alloc(s.count + 1, allocator);
  memcpy(result, s.data, s.count);
  result[s.count] = 0;
  return result;
}




// // #import "Hash_Table";

// exec :: (sql: string) -> err: bool {;
//   err := !!sqlite3_exec(db, to_c_string(sql), callback, null, null);
//   if err {
//     mylog("exec error:", to_string(sqlite3_errmsg(db)));
//     mylog(sql);
//   }
//   return err;
// }
// callback :: (notused: *void, argc: s32, argv: **u8, azcolname: **u8) -> s32 #c_call {
//   ctx: Context;
//   push_context ctx {
//     print("hi from callback\n");
//   }
//   return 0;
// }

// // Row :: Table(string, string);
// // exec :: (sql: string) -> results: [..] Row, err: bool {;
// //   // push_tallocator();
// //   rows: [..] Row;
// //   remember_allocators(*rows);
// //   // array_reserve(*rows, 10);

// //   err := !!sqlite3_exec(db, to_c_string(sql), callback, *rows, null);
// //   if err {
// //     mylog("exec error:", to_string(sqlite3_errmsg(db)));
// //     mylog(sql);
// //   }

// //   return rows, err;
// // }
// // callback :: (_rows: *void, argc: s32, argv: **u8, azcolname: **u8) -> s32 #c_call {
// //   rows := cast(*[..]Row) _rows;
// //   ctx: Context;
// //   push_context ctx {

// //     // push_tallocator();
// //     row: *Row = array_add(rows);
// //     // row.allocator = rows.allocator;
// //     // row.allocator_data = rows.allocator_data;
// //     init(row);

// //     for i: 0 .. argc-1 {
// //       colname := to_string(azcolname[i]);
// //       value := ifx argv[i] then to_string(argv[i]) else "NULL";
// //       table_add(row, colname, value);
// //     }

// //   }
// //   return 0;
// // }

