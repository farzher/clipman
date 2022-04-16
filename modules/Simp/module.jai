//
// This is a simple framework for drawing graphics that you can use
// for most programs that are not too demanding. Or, you could copy this module
// and customize it to become what you want.
//
// Generally, doing graphics is super complicated and hairy and you have to
// think about a lot of annoying things. This framework is an experiment in asking,
// if you aren't trying to maximize performance, how simple can we make it?
// The answer is going to be, probably still not as simple as we'd like,
// because there is too much innate complication arbitrarily embedded in
// the systems we need to use in order to draw things. But, in graphics a great deal
// of complexity comes from trying to make things as fast as possible, so, we should
// be able to shave most of that off.
//
// One of the biggest problems of modern software is that people think the software
// should always be getting "better" in the sense that it tries to do every little
// thing that everyone wants. But this leads to increasing complexity, step by step.
// It's like playing Go, where, at first just putting a stone here or over there
// seemed like small, uncostly moves that provided big benefits, but now they
// have grown into a huge infrastructure that has to be maintained, and that
// maintenance itself adds more structure, and so much effort needs to be put into
// your understanding that structure that has been built up, and if your understanding
// is too incomplete then the structure will collapse.
//
// So we draw a certain very close boundary over what we are attempting to do here.
// For many simple applications, this module will be enough. Maybe someone can make
// another module called Simp+ that does more, and does introduce more constraints
// on the application, but they are not too bad, and upgrading from Simp to Simp+
// doesn't take much more than an afternoon, or whatnot. But for now we just say,
// there's a line, if your program is inside the line you can use this; once it grows
// outside the line, you probably want to switch to a bigger framework or engine
// that is much more complicated.
//
Render_API :: enum {
    NONE;
    SOFTWARE;
    OPENGL;
    METAL;
}

#module_parameters (render_api := Render_API.OPENGL);

#scope_module

#if OS == .WINDOWS {
    // Maybe we should clean this up and not pull all of Windows into the namespace.
    #import "Windows";
}

#if render_api == .OPENGL {
    #import "GL";

    #load "backend/gl.jai";
}

#if render_api == .METAL {
    #import "Metal";
}     

#import "Basic";
#import "Math";
#import "String";
// #import "Atomics";
#import "Bit_Operations";

// Bitmap loading and saving:
#import "stb_image";
#import "stb_image_write";
#import "stb_image_resize";

#scope_export

simp_init :: (window: Window_Type, window_width: s32, window_height: s32, render_width: s32, render_height: s32, windowed := true, vsync := true) {
    // @Incomplete: Allow people to pass -1 for render_width, height, and get the window client area if needed.
    // @Incopmlete: We should assert that simp_init has not been called, in a user-friendly way, when people try to do other rendering stuff.
    // @Cleanup: Make it so you don't need window_*.
    backend_init(window, window_width, window_height, render_width, render_height, windowed, vsync);
}

draw_text :: (font: *Dynamic_Font, x: s64, y: s64,
              text: string, color := Vector4.{1,1,1,1}, effects: Font_Effects = 0) {
    // @Cleanup: generate_quads should return quads in a threadsafe way?
    prepare_text(font, text);
    generate_quads_for_prepared_text(font, x, y, effects);
    draw_generated_quads(font, color);
}

draw_prepared_text :: (font: *Dynamic_Font, x: s64, y: s64, color := Vector4.{1, 1, 1, 1}, effects: Font_Effects = 0) {
    generate_quads_for_prepared_text(font, x, y, effects);
    draw_generated_quads(font, color);
}

#scope_export 
set_scissor :: (x0: s32, y0: s32, x1: s32, y1: s32) {
    immediate_flush();
    glEnable(GL_SCISSOR_TEST);
    glScissor(x0, y0, cast(u32)(x1-x0), cast(u32)(y1-y0));
}

clear_scissor :: () {
    glDisable(GL_SCISSOR_TEST);
}


//
// Those are the preliminaries. Here are this module's own files:
//

#load "bitmap.jai";
#load "texture.jai";
#load "texture_format.jai";
#load "shader.jai";
#load "immediate.jai";
#load "font.jai";

