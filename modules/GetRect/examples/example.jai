//
// This is an example of how to use GetRect.
//
// GetRect is in its period of initial creation and is still evolving quickly.
// One important thing to know is, there is no notion of global focus yet,
// so we do some manual focus wrangling in here. We'll clean that up eventually.
//
// Also, this demo will be made cosmetically nicer in the end. Right now it just
// demonstrates how to do the various types of controls, but ultimately the goal
// is that GetRect does not look ugly by default, unlike many other UI systems.
//

#import "GetRect";  // Other imports are below, but the point of this example is to use GetRect so this #import goes here.

//
// This example was copied from modules/Simp/examples/example.jai.
// It will continue to diverge over time, probably.
//

SCALE :: 1;  // I use this during development to quickly make the window real big.

my_window: Window_Type;
window_width  : s32 = 1920*SCALE;
window_height : s32 = 1080*SCALE;

render_width  : s32 = 1920*SCALE;
render_height : s32 = 1080*SCALE;

current_time: float64;
last\  _time: float64;

scroll_value: float;
scroll_value_dragdrop_region: float;

dropped_files: [..] string;

// Data values that we manipulate with the widgets:

Grocery_Info :: struct {
    name: string;
    should_get := false;
}

groceries: [..] Grocery_Info;

spells: [..] string;  // We make a radio button of which spell to cast.
current_spell := -1;

// @Incomplete: Comment why these are necessary and/or fix the mess? (This is one frame lagged).
Text_Input_And_Rect :: struct {
    input: Text_Input;
    rect:  Rect;
}

all_text_inputs: [..] *Text_Input_And_Rect;

// In order to demonstrate input focus, we have two text inputs.
input_a: Text_Input_And_Rect;
input_b: Text_Input_And_Rect;
input_c: Text_Input_And_Rect;

input_teas: Text_Input_And_Rect;

Damage_Resistance :: enum_flags u16 {
    PIERCING;
    SLASHING;
    CRUSHING;
    BLUNT;
    ELECTRICAL :: 0x40;
    MAGIC;
    POISON;
    ELEMENTAL;
    EMOTIONAL;
}

damage_resistance: Damage_Resistance;

awesome_theme_names :: string.["Blood Vampire", "Very Dark", "Chai Juice", "Peach Panther", "Emotional Damage", "Rays of Sunshine", "THEMERUNKNOWN'S THEMEGROUNDS", "Chaos!!!!"];

teas :: string.["Earl Gray", "Singapore Breakfast", "Bengal Spice", "Hot Cinnamon Spice", "Tie Guanyin", "Lapsang Souchong", "Royal Pu-Erh", "Chai Juice", "Snore and Peace", "Genmaicha", "Jasmine Pearls", "Sencha", "Gyokuro", "White Claw", "Rooibos", "Alishan Oolong"];

TEXT_FIELD_1 :: #string DONE
I thence
Invoke thy aid to my adventurous song,
That with no middle flight intends to soar
Above th' Aonian mount, while it pursues
Things unattempted yet in prose or rhyme.
And chiefly thou, O Spirit, that dost prefer
Before all temples th' upright heart and pure,
Instruct me, for thou know'st; thou from the first
Wast present, and, with mighty wings outspread,
Dove-like sat'st brooding on the vast Abyss,
And mad'st it pregnant: what in me is dark
Illumine, what is low raise and support;
That, to the height of this great argument,
I may assert Eternal Providence,
And justify the ways of God to men.
DONE

slider_float_value: float = 27.02;
slider_int_value  : s32 = 3;

current_theme: s32 = 0;

picked_color: Vector3 = .{.1, .8, .6};

// @Cleanup: Get rid of the need for begins_with_count?
begins_with_count :: (str: string, prefix: string) -> int {
    for 0..prefix.count-1 {
        if it >= str.count || str[it] != prefix[it] return it;
    }
    
    return prefix.count;
}

auto_complete_teas :: (input: string, data: *void) -> (results: [] string, longest_match_length: int) {
    results: [..] string;

    longest_match_length := 0;
    for teas {
        count := begins_with_count(it, input);
        if count == input.count {
            array_add(*results, it);
            longest_match_length = max(longest_match_length, input.count);
        }

        longest_match_length = max(longest_match_length, count);
    }

    return results, longest_match_length;
}

deactivate_all_other_inputs :: (input: *Text_Input) {
    for other: all_text_inputs {
        if other.input.active && (*other.input != input) {
            deactivate(*other.input);
        }
    }

    // :GeneralWidget
    // Because we don't yet have global input handling, for now we do this thing
    // where GetRect has a Text_Input it uses for various stuff. Eventually we won't
    // have to do a kludge like this in the user program.

    if input != *input_for_general_widget_use  deactivate(*input_for_general_widget_use);
}

main :: () {
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();

        // Windows is very bad at thread-switching by default unless you do this. Sad.
        Windows.timeBeginPeriod(1);
    }

    my_window = create_window(window_width, window_height, "A Window");
    #if OS == .WINDOWS  Windows.DragAcceptFiles(my_window, cast(Windows.BOOL) true);

    Simp.simp_init(my_window, window_width, window_height, render_width, render_height);
    
    my_init_fonts();
    ui_init();

    init(*input_a.input);
    set_text(*input_a.input, "Lord Dimwit Flathead");
    array_add(*all_text_inputs, *input_a);

    init(*input_b.input);
    set_text(*input_b.input, "Flood Control Dam #3");
    array_add(*all_text_inputs, *input_b);

    init(*input_c.input);
    set_text(*input_c.input, "The Troll Room");
    array_add(*all_text_inputs, *input_c);

    init(*input_teas.input);
    set_auto_complete(*input_teas.input, auto_complete_teas, null);
    array_add(*all_text_inputs, *input_teas);
    
    // Add some groceries.

    g := array_add(*groceries);
    g.name = "Apples";
    
    g = array_add(*groceries);
    g.name = "Bananas";
    
    g = array_add(*groceries);
    g.name = "Moon Chips";

    g = array_add(*groceries);
    g.name = "Chai Juice";


    array_add(*spells, "rezrov");
    array_add(*spells, "gondar");
    array_add(*spells, "gnusto");
    array_add(*spells, "aimfiz");

    
    quit := false;
    while !quit {
        current_time = get_time();
        dt := cast(float)(current_time - last_time);
        Clamp(*dt, 0, 0.1);
        last_time = current_time;

        Input.update_window_events();

        for Input.get_window_resizes() {
            if it.window == my_window {
                should_reinit := (it.width != window_width) || (it.height != window_height);
                
                window_width  = it.width;
                window_height = it.height;
                render_width  = window_width;
                render_height = window_height;
                
                Simp.update_window(my_window, window_width, window_height, render_width, render_height);
                if should_reinit my_init_fonts();  // Resize the font for the new window size.
            }
        }
        
        for event: Input.events_this_frame {
            if event.type == .QUIT then quit = true;

            for all_text_inputs {
                handle_event(*it.input, it.rect, event);
                
                if it.input.active {
                    deactivate_all_other_inputs(*it.input);
                }
            }

            // :GeneralWidget
            if input_being_used_by  handle_event(*input_for_general_widget_use, last_rect_for_general_widget_use, event);
            
            if event.type == {
              case .KEYBOARD;
                if event.key_pressed && event.key_code == .ESCAPE {
                    deactivate_all_other_inputs(null);
                }
              case .DRAG_AND_DROP_FILES;
                for dropped_files free(it);
                array_reset(*dropped_files);
                for event.files array_add(*dropped_files, copy_string(it));
            }
        }

        draw_one_frame(dt);
        
        reset_temporary_storage();
        sleep_milliseconds(10);
    }
}

draw_one_frame :: (dt: float) {
    Simp.update_window(my_window, window_width, window_height, render_width, render_height);  // @Cleanup: Just give the window handle?
    Simp.clear_render_target(.15, .11, .11, 1);

    x, y, width, height := get_dimensions(my_window, true);
    ui_per_frame_update(my_window, width, height, current_time);

    button_theme: Button_Theme;  // This will have the default Button_Theme values.
    button_theme.font = button_font; // @Cleanup: We have to manually set a font for now.
    button_theme.enable_variable_frame_thickness = true; 
    // 'k' is some resolution-adjusting unit of distance. Right now it is
    // 1/10 of the screen height, so, 108 pixels at 1920x1080.
    k := render_height * .1;
    r := get_rect(k*.5, 2.1*k, 3*k, k);

    button_theme.label_theme.alignment = .Left;
    pressed := button(r, "Hello, Sailor!", *button_theme);

    r.y -= k;
    button_theme.label_theme.alignment = .Center;
    pressed  = button(r, "there are", *button_theme);

    r.y -= k;
    button_theme.label_theme.alignment = .Right;
    pressed  = button(r, "69,105 leaves.", *button_theme);


    
    checkbox_theme: Checkbox_Theme;
    checkbox_theme.font = button_font; // @Cleanup: We have to manually set a font for now.

    radio_theme: Checkbox_Theme;
    radio_theme.font = button_font; // @Cleanup: We have to manually set a font for now.
    radio_theme.is_radio_button = true;

    r = get_rect(4*k, 1.8*k, 2*k, xx button_font.character_height);
    old_y := r.y;

    // Check Boxes:
    vertical_pad := r.h * .35;
    for * groceries {
        pressed := base_checkbox(r, it.name, it.should_get, *checkbox_theme, it_index);
        it.should_get ^= pressed;
        r.y -= button_font.character_height + vertical_pad;
    }

    // Radio Buttons:
    r = get_rect(6*k, old_y, 2*k, xx button_font.character_height);
    for spells {
        selected := (current_spell == it_index);
        pressed := base_checkbox(r, it, selected, *radio_theme, it_index);
        if pressed current_spell = it_index;
        
        r.y -= button_font.character_height + vertical_pad;
    }

    r = get_rect(8*k, old_y + 5 * (button_font.character_height + vertical_pad), 2*k, xx button_font.character_height);


    //
    // Text Input stuff:
    //

    text_theme: Text_Input_Theme;
    text_theme.font = button_font;
    
    r = get_rect(1*k, 4*k, 5*k, button_font.character_height*1.35);
    input_a.rect = r;
    draw(*input_a.input, r, *text_theme);

    text_theme.alignment = .Center;
    r.y -= button_font.character_height * 1.5;
    input_b.rect = r;
    draw(*input_b.input, r, *text_theme);

    text_theme.alignment = .Right;
    r.y -= button_font.character_height * 1.5;
    input_c.rect = r;
    draw(*input_c.input, r, *text_theme);

    // The teas:
    r = get_rect(3*k, 7*k, 3*k, button_font.character_height*1.35);
    // r.y -= button_font.character_height * 1.5;
    input_teas.rect = r;
    text_theme.alignment = .Left;
    draw(*input_teas.input, r, *text_theme);
    
    //
    // Slider:
    //

    // Float value:
    slider_theme: Slider_Theme;
    slider_theme.foreground.font = button_font;
    r = get_rect(7*k, 7*k, 3*k, button_font.character_height*1.35);
    slider(r, *slider_float_value, 0.0, 60.0, 3.0, *slider_theme, "", "fps");

    // Integer value:
    r.y -= r.h * 1.2;
    slider(r, *slider_int_value, 0, 10, 1, *slider_theme, "number ");


    button_height := render_height * .03;
    
    //
    // Dropdown stuff.
    //
    {
        r = get_rect(13.8*k, 7*k, 2.2*k, button_height);
        dropdown_theme := *default_panel_theme.dropdown_theme;
        dropdown(r, awesome_theme_names, *current_theme, dropdown_theme);
    }

    //
    // Color Picker stuff.
    //
    {
        r = get_rect(13.8*k, .03*k, 3*k, 4*k);
        color_picker_theme := *default_panel_theme.color_picker_theme;
        applied := color_picker(r, *picked_color, color_picker_theme);
    }


    //
    // Slidable Region stuff.
    //

    {
        r = get_rect(7*k, 1*k, 2*k, 5*k);
        
        theme := default_panel_theme.slidable_region_theme;
        theme.orientation = .VERTICAL;
        theme.first_\background.shape.rounding_flags   = Rectangle_Shape.Rounding_Flags.NORTHEAST | .NORTHWEST;
        theme.second_background.shape.rounding_flags   = Rectangle_Shape.Rounding_Flags.SOUTHEAST | .SOUTHWEST;
        theme.first_\background.shape.roundedness_type = .RELATIVE_TO_WIDTH;
        theme.second_background.shape.roundedness_type = .RELATIVE_TO_WIDTH;

        state, left_or_top, right_or_bottom, divider := slidable_region(r, *theme);
        {
            xpad := em(1, button_font);
            ypad := .6 * button_font.character_height;
            
            orig_s := cut_top(left_or_top, ypad);
            junk, s := cut_left(orig_s, xpad);
            
            //
            // Using type_info, we can very quickly generate some checkboxes for
            // any enum_flags type. The loop below is the only code needed!
            //
            info := type_info(Damage_Resistance);
            s.y -= button_font.character_height + vertical_pad;
            for name: info.names {
                value := cast(Damage_Resistance) info.values[it_index];

                checkbox_flags(s, name, *damage_resistance, value, *checkbox_theme, xx value);
                s.y -= button_font.character_height + vertical_pad;
            }
        }
        
            
        switch_to_bottom_rect(state);
        
        {
            // s := get_rect(8*k, 1*k, 5*k, 2*k);
            s := right_or_bottom;
            
            theme := default_panel_theme.slidable_region_theme;
            theme.orientation = .HORIZONTAL;
            theme.divider_theme.rectangle_shape.frame_thickness_type = .RELATIVE_TO_WIDTH;
            theme.divider_theme.rectangle_shape.roundedness_type     = .RELATIVE_TO_WIDTH;

            // Disable drawing the background, since we are already inside a background that is fine.
            theme.first_background .color.w  = 0;
            theme.second_background.color.w = 0;
            theme.first_background .frame_color.w = 0;
            theme.second_background.frame_color.w = 0;

            state, left_or_top, right_or_bottom, divider := slidable_region(s, *theme);
            switch_to_bottom_rect(state);

            {
                //
                // Scrollable Region stuff.
                //

                {
//                    r = get_rect(10.5*k, 4*k, 1.8*k, 3*k);
                    region, inside := begin_scrollable_region(right_or_bottom);

                    NUM_BUTTONS :: 30;
                    // button_height = floor(inside.w * .22 + .5);

                    // @Incomplete: Add the scrolling offset when we have it.
                    // @Incomplete: Scroll value is in pixels, what happens if the screen changes resolution?
                    s := inside;
                    s.y = s.y + s.h - button_height;
                    s.h = button_height;
                    s.y += scroll_value;
                    button_theme.label_theme.alignment = .Center;
                    button_theme.font = null;
                    
                    for 1..NUM_BUTTONS {
                        text := tprint("Button %", it);
                        pressed := button(s, text, *button_theme, it);

                        if  it != NUM_BUTTONS  {
                            s.y -= floor(button_height * 1.1 + 0.5);  // Just so r.y is in the right place for end_scrollable_region().
                        }
                    }

                    end_scrollable_region(region, s.x + s.w, s.y, *scroll_value);
                }
            }
            
            finish(state);
        }

        finish(state);
    }

    {
        //
 	    // Drag and drop scrollable region.
        // Submitted by Jens Frederich.
 	    //
 	    
 	    theme := default_panel_theme.scrollable_region_theme;
 	    theme.region_background.shape.rounding_flags = 0;
 	    
        r = get_rect(9.5*k, 1*k, 4*k, 5*k);
 	    
 	    region, inside := begin_scrollable_region(r, *theme);
 	    
 	    label_height := render_height * .03;
 	    s := inside;
 	    s.y = s.y + s.h - label_height;
 	    s.h = label_height;
 	    s.y += scroll_value_dragdrop_region;
 	    
 	    label_theme: Label_Theme;
 	    label_theme.alignment = .Left;
 	    label_theme.text_color = .{.9, .5, .5, 1};

 	    if dropped_files {
 	  	    for dropped_files {
 	 	        label(s, it, *label_theme);
 	 	        s.y -= floor(label_height * 1.1 + 0.5);
 	 	    }
        } else {
 	 	    label(s, "Drag/drop files will appear here.", *label_theme);
        }
        
 	    end_scrollable_region(region, s.x + s.w, s.y, *scroll_value_dragdrop_region);
    }

    
    //
    // Draw the title over everything:
    //

    label_theme: Label_Theme;
    label_theme.font       = title_font;
    label_theme.text_color = .{.9, .5, .5, 1};
    label_height := title_font.character_height*1.5;
    r = get_rect(0, render_height - label_height, xx render_width, label_height);
    label(r, "Some Widgets", *label_theme);
    
    // :GeneralWidget
    if input_for_general_widget_use.active  deactivate_all_other_inputs(*input_for_general_widget_use);

    //
    // Swap buffers!
    //
    
    Simp.swap_buffers(my_window);
}

my_init_fonts :: () {
    if !working_directory_set {
        // So that we can load our font, set to path of running executable.
        path := path_strip_filename(get_path_of_running_executable());
        set_working_directory(path);

        working_directory_set = true;
    }
    
    pixel_height := window_height / 24;
    my_font = Simp.get_font_at_size("data", "OpenSans-BoldItalic.ttf", pixel_height);
    assert(my_font != null);

    pixel_height /= 2;
    button_font = Simp.get_font_at_size("data", "OpenSans-BoldItalic.ttf", pixel_height);
    assert(button_font != null);

    pixel_height = window_height / 7;
    title_font = Simp.get_font_at_size("data", "Miama.otf", pixel_height);
//    title_font = Simp.get_font_at_size("data", "OpenSans-BoldItalic.ttf", pixel_height);
}

Font :: Simp.Dynamic_Font;

my_font:     *Font;
button_font: *Font;
title_font:  *Font;

working_directory_set := false;

Simp  :: #import "Simp";
Input :: #import "Input";

// @CompilerBug: This doesn't work.
// #import "Simple_Render_Framework"(.SOFTWARE);

#import "Window_Creation";

#import "Basic";
#import "Math";
#import "System";  // For get_path_of_running_executable. @Cleanup.
#import "String";  // For path_strip_filename. @Cleanup.

