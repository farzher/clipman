my_window: Window_Type;
window_width  : s32 = 1920;
window_height : s32 = 1080;

render_width  : s32 = 1920*2;
render_height : s32 = 1080*2;

main :: () {
    #if OS == .WINDOWS {
        Windows.SetProcessDPIAware();

        // Windows is very bad at thread-switching by default unless you do this. Sad.
        Windows :: #import "Windows";
        Windows.timeBeginPeriod(1);
    }

    my_window = create_window(window_width, window_height, "A Window");

    Simp.simp_init(my_window, window_width, window_height, render_width, render_height);
    
    my_init_fonts();
    
    quit := false;
    while !quit {
        Input.update_window_events();

        for Input.get_window_resizes() {
            if it.window == my_window {
                should_reinit := (it.width != window_width) || (it.height != window_height);
/*                
                window_width  = it.width;
                window_height = it.height;
  */              
                render_width  = window_width;
                render_height = window_height;
                
                Simp.update_window(my_window, window_width, window_height, render_width, render_height);
                if should_reinit my_init_fonts();  // Resize the font for the new window size.
            }
        }

        for Input.events_this_frame {
            if it.type == .QUIT then quit = true;

            if it.type == {
              case .KEYBOARD;
                if it.key_pressed && it.key_code == .ESCAPE {
                    quit = true;
                }
            }
        }

        draw_one_frame();
        
        sleep_milliseconds(10);
        reset_temporary_storage();
    }
}

draw_one_frame :: () {
    Simp.clear_render_target(.15, .08, .08, 1);
    
    Simp.set_shader_for_color();

    time := get_time();
    
    // This is our own code to set up a rotating square:
    {
        b := cast(float)window_height / 10;
        p: Vector2;
        p.x = cast(float)(window_width  / 2);
        p.y = cast(float)(window_height / 2);

        theta := cast(float) fmod(time, TAU);    

        ct := cos(theta);
        st := sin(theta);
        
        w := make_vector2(b*ct, b*st);
        h := make_vector2(b*st, -b*ct);

        p0 := p - w - h;
        p1 := p + w - h;
        p2 := p + w + h;
        p3 := p - w + h;

        a :: 1.0;
        c0 := Vector4.{1, 0, 0, a};
        c1 := Vector4.{0, 1, 0, a};
        c2 := Vector4.{0, 0, 1, a};
        c3 := Vector4.{1, 1, 1, a};
        
        Simp.immediate_quad(p0, p1, p2, p3, c0, c1, c2, c3);
    }

    // Draw some text.
    {
        // Do a bunch of wacky math to figure out the text color.
        theta := cast(float) fmod(time*3, TAU);    
        color: Vector4;
        color.x = cos(theta)*.5+.5;
        Clamp(*color.x, 0, 1);
        color.y = 1;
        color.z = sin(theta)*.5+.5;
        Clamp(*color.z, 0, 1);
        color.w = 1;

        // Now, to draw the text:
        text := "Simp!";
        
        // We could just call Simp.draw_text to draw text! But we want to know the width
        // so that we can center the text, and to find the width, we have to do all the
        // text layout. So it makes sense just to draw the prepared text after that,
        // so there's a special routine, "draw_prepared_text", that draws the thing
        // you just prepared and got the width of.
        
        text_width := Simp.prepare_text(my_font, text);
        
        text_x := (window_width - text_width) / 2;
        text_y := window_height/2 - my_font.character_height/4;

        Simp.draw_prepared_text(my_font, text_x, text_y, color);
    }
    
    Simp.swap_buffers(my_window);
}

my_init_fonts :: () {
    // So that we can load our font, set to path of running executable.
    // @Incomplete: Pack a default font into Simp.

    if !working_directory_set {
        path := path_strip_filename(get_path_of_running_executable());
        set_working_directory(path);
        working_directory_set = true;
    }
    
    pixel_height := window_height / 24;

    // @Cleanup: Don't have path + name be separate.
    my_font = Simp.get_font_at_size(".", "OpenSans-BoldItalic.ttf", pixel_height);
    assert(my_font != null);
}

working_directory_set := false;

my_font: *Simp.Dynamic_Font;

Simp  :: #import "Simp";
Input :: #import "Input";

// @CompilerBug: This doesn't work.
// #import "Simple_Render_Framework"(.SOFTWARE);

#import "Window_Creation";

#import "Basic";
#import "Math";
#import "System";  // For get_path_of_running_executable. @Cleanup.
#import "String";  // For path_strip_filename. @Cleanup.


#run {
    #if OS == .WINDOWS {
        WR :: #import "Windows_Resources";
        WR.disable_runtime_console();
    }
}
