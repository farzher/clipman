/* -farzher September 13, 2021
  Alternative to Ditto

  i want an alternative so that i can encrypt the database file.

  this code may not compile properly because i added a bunch of hacks
  to built-in jai modules to support features like clipboard copy events
*/

#run build();

build :: () {
  w := compiler_create_workspace("Target Program");
  options := get_build_options();
  set_build_options_dc(.{do_output=false});

  isrelease :: #run get_build_options().optimization_level == .RELEASE;


  // build for debug or release
  #if !isrelease { // debug
    options.output_path = "bin/";
    options.backend = .X64;
    options.x64_options.enable_register_allocation = true;
  } else { // -release
    options.output_path = "release/";
    options.output_executable_name = "clipman";
    set_optimization_level(*options, 2, 0);
    options.stack_trace = false;
    #run disable_runtime_console();
  }


  { // -impor_dir ./modules
    import_path: [..] string;
    array_add(*import_path, "./modules");
    array_add(*import_path, ..options.import_path);
    options.import_path = import_path;
  }

  // done setting options
  set_build_options(options, w);



  compiler_begin_intercept(w);

  add_build_file(tprint("%/src/main.jai", #filepath), w);

  // waiting for our exe to finish so we can set its icon
  while true {
    message := compiler_wait_for_message();
    if !message continue;
    if message.workspace != w continue;
    if message.kind == .COMPLETE break;
  }
  compiler_end_intercept(w);

  // set exe icon
  exe_path  := tprint("%1%2.exe", options.output_path, options.output_executable_name);
  icon_path := "bin/tray.ico";
  set_icon_by_filename(exe_path, icon_path);

  // delete .pdb if release
  #if isrelease  file_delete("release/clipman.pdb");
}





#import "Basic";
#import "Compiler";
#import "Windows_Resources";
#import "File";
