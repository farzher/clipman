/* -farzher September 13, 2021
  Alternative to Ditto

  i want an alternative so that i can encrypt the database file.

  this code may not compile properly because i added a bunch of hacks
  to built-in jai modules to support features like clipboard copy events
*/

#run build();
// #run run();

run :: () {
  build(actually_build=false);
  add_build_string("#run main();", w);
}

w: Workspace;
build :: (actually_build := true) {
  w = compiler_create_workspace("Target Program");
  options := get_build_options();


  // build for debug or release
  #if 1 { // -x64
    // options.backend = .X64;
    // options.x64_options.enable_register_allocation = true;
  } else { // -release
    set_optimization_level(*options, 2, 0);
    options.stack_trace = false;
    // #run disable_runtime_console();
  }


  { // -impor_dir ./modules
    import_path: [..] string;
    array_add(*import_path, "./modules");
    array_add(*import_path, ..options.import_path);
    options.import_path = import_path;
  }

  { // rename the exe
    // options.output_executable_name = "main";
    options.output_path = "bin/";
  }

  set_build_options(options, w);



  if actually_build then compiler_begin_intercept(w);

  add_build_file(tprint("%/src/main.jai", #filepath), w);

  // // if options.optimization_level == .RELEASE then #run disable_runtime_console();
  // // todo doesn't work because the #run always runs
  // #run () {
  //   options := get_build_options();
  //   if options.optimization_level == .RELEASE then disable_runtime_console();
  // };

  set_build_options_dc(.{do_output=false});

  if !actually_build then return;

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
  icon_path := tprint("%1%2.ico", options.output_path, "tray");
  set_icon_by_filename(exe_path, icon_path);


}





#import "Basic";
#import "Compiler";
#import "Windows_Resources";
#import "Ico_File";
String :: #import "String";
