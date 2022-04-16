//
// To Do:
//
// GetDesktopWindow/GetClientRect, getting desktop resolution on Windows and Linux.
//
// * Don't require ui_init to be called.
// * Make it so that you don't need to init Text_Input.
// * Example of not using Simp (Draw_Procs pluggability test).
// * Frame-rate dependence when dragging the Text_Input selection outside the margins. (Also, want themed speed control.)
//
// * I hate that function called "slice". Do something about it.
// * Make DPI-Aware easy.
// * Error-checking that makes sure all scrollable regions are finished, all scissors are popped, etc.
//

#module_parameters ()(Type_Indicator: Type = void);

// Here are some global fields that control size, that you can update
// any time you want between calls to GetRect widgets.
// If you don't ever set them, they will be set from defaults in per_frame_update.
// See the comment on Size_Computation in themes.jai for ways you would use these.


set_global_rounding_radius_in_pixels :: (value: float) {
    global_rounding_radius_in_pixels        = value;
    global_rounding_radius_in_pixels_is_set = true;
}

set_global_frame_thickness_in_pixels :: (value: float) {
    global_frame_thickness_in_pixels        = value;
    global_frame_thickness_in_pixels_is_set = true;
}

set_global_divider_thickness_in_pixels :: (value: float) {
    global_divider_thickness_in_pixels        = value;
    global_divider_thickness_in_pixels_is_set = true;
}

set_global_initial_divider_position_in_pixels :: (value: float) {
    global_initial_divider_position_in_pixels        = value;
    global_initial_divider_position_in_pixels_is_set = true;
}
    
#scope_module

global_rounding_radius_in_pixels := 9.0;
global_rounding_radius_in_pixels_is_set := false;

global_frame_thickness_in_pixels := 4.0;
global_frame_thickness_in_pixels_is_set := false;

global_divider_thickness_in_pixels := 4.0;
global_divider_thickness_in_pixels_is_set := false;

global_initial_divider_position_in_pixels := 32.0;
global_initial_divider_position_in_pixels_is_set := false;


#load "label.jai";
#load "button.jai";
#load "checkbox.jai";
#load "slider.jai";
#load "text_input.jai";
#load "dropdown.jai";
#load "color_picker.jai";
#load "number_input.jai";
#load "scrollable_region.jai";
#load "slidable_region.jai";
#load "text_display.jai";

#load "themes.jai";
#load "state.jai";

#import "Basic";
#import "Input";
#import "Hash_Table";
#import "Math";
#import "String";  // Used in Text_Input.
#import "Unicode"; // Used in Text_Input.
#import "Pool";

#if Type_Indicator == void {
    USE_SIMP :: true;
    Simp :: #import "Simp";
    Window_Creation :: #import "Window_Creation";  // Just for Window_Type. Should that be a module parameter?

    Window_Type  :: Window_Creation.Window_Type;
    Font         :: Simp.Dynamic_Font;
    Font_Effects :: Simp.Font_Effects;
    Texture      :: Simp.Texture;
} else {
    USE_SIMP :: false;
    Window_Type  :: Type_Indicator.Window_Type;
    Font         :: Type_Indicator.Font;
    Font_Effects :: Type_Indicator.Font_Effects;
    Texture      :: Type_Indicator.Texture;
    #assert(false);  // Non-Simp UI not yet handled!
}

scissor_stack: [..] Rect;

first_mouse_update := true;
mouse_x, mouse_y: s32;
mouse_x_float, mouse_y_float: float;
mouse_delta_x_float, mouse_delta_y_float: float;

mouse_button_left_state:  Key_Current_State;
mouse_button_right_state: Key_Current_State;
shift_key_state:          Key_Current_State;

last_current_time := FLOAT64_INFINITY;
current_time: float64;
current_dt:   float;

render_target_width:  s32;
render_target_height: s32;

map_radiobox_full:  *Texture;
map_radiobox_empty: *Texture;
map_checkbox_full:  *Texture;
map_checkbox_empty: *Texture;
map_mode_circle:    *Texture;
map_mode_rgb:       *Texture;
map_mode_hsv:       *Texture;
map_mode_numbers:   *Texture;

#scope_export


// @Temporary: Since in general you only want one input active,
// we are just going to use a common one for now. But this means we will be dumping
// any temporary string as we switch back and forth. Long-term this may not be good,
// maybe we will want to instantiate separate Text_Inputs for different widgets, or ... ??
input_for_general_widget_use: Text_Input;
last_rect_for_general_widget_use: Rect;
input_being_used_by: *void;  // A pointer to the state record.
overall_text_input_owner: *void;

grab_text_input :: (used_by: *void) -> *Text_Input {
    if input_being_used_by != used_by {
        input_being_used_by = used_by;
        input_for_general_widget_use.entered = false;
    }

    if !input_for_general_widget_use.initted  init(*input_for_general_widget_use);

    return *input_for_general_widget_use;
}

stop_grabbing_text_input :: (used_by: *void) {
    assert(used_by != null);
    
    if (input_being_used_by == used_by) || (overall_text_input_owner == used_by) {
        input_being_used_by = null;
        input_for_general_widget_use.entered = false;
    }
}

set_overall_text_input_owner :: (p: *void) {
    // Used for hierarchical text input ownership. This is a dumb hack
    // that will go away later when we have global state management.
    //    -jblow, 25 June 2021.

    overall_text_input_owner = p;
}

unset_overall_text_input_owner :: (p: *void) {
    // See comment on set_overall_text_input_owner.
    assert(overall_text_input_owner == p);
    overall_text_input_owner = null;
}

has_active_text_input :: (used_by: *void, rect: Rect) -> *Text_Input {
    if input_being_used_by == used_by {
        last_rect_for_general_widget_use = rect;
        return *input_for_general_widget_use;
    }
    
    return null;
}

Draw_Procs :: struct {  // Not yet used, but the idea is that you can substitute these rather than using Simp.
    texture_load_from_memory: (texture: *Texture, memory: [] u8, srgb: bool, build_mipmaps: bool) -> bool;
    set_scissor:   (x0: s32, y0: s32, x1: s32, y1: s32);
    clear_scissor: ();

    set_shader_for_color:  (enable_blend := false);
    set_shader_for_images: (texture: *Texture);

    prepare_text:       (font: *Font, text: string, effects: Font_Effects = 0) -> s64;
    draw_prepared_text: (font: *Font, x: s64, y: s64, text_color: Vector4, effects: Font_Effects = 0);

    get_mouse_pointer_position: (window: Window_Type, right_handed: bool) -> (x: int, y: int, success: bool);
    
    get_font_at_size:   (memory: [] u8, pixel_height: int) -> *Font;
    
    immediate_triangle:  (p0: Vector3, p1: Vector3, p2: Vector3, c0 := Vector4.{1,1,1,1}, c1 := Vector4.{1,1,1,1}, c2 := Vector4.{1,1,1,1}, uv0 := Vector2.{}, uv1 := Vector2.{}, uv2 := Vector2.{}, normal := Vector3.{z=1});
    immediate_quad:  (p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, color := Vector4.{1,1,1,1}, uv0 := Vector2.{0,0}, uv1 := Vector2.{1,0}, uv2 := Vector2.{1,1}, uv3 := Vector2.{0, 1});
    immediate_flush: ();
}

default_panel_theme: Panel_Theme;
draw_procs: Draw_Procs;

Status_Flags :: enum u32 {
    OVER     :: 0x01;
    FOCUS    :: 0x02;
    DOWN     :: 0x04;
    PRESSED  :: 0x08;
//    RELEASED :: 0x10;
}

Text_Alignment :: enum u8 {
    Left   :: 0;
    Center :: 1;
    Right  :: 2;
}


Rect :: struct {
    x, y: float;
    w, h: float;
}

KNUTH_GOLDEN_RATIO_64 :: 11400714819323198485;

get_hash :: (loc: Source_Code_Location, identifier: s64) -> u64 {
    // Maybe we should hash the filename pointer in order to better prevent collisions.
    hash := cast(u64) loc.fully_pathed_filename.data * cast,no_check(u64)(loc.line_number + 1) * cast(u64)(identifier + 1);   // Here we are using the filename pointer as a u64, yay.
    return hash;
}

combine_hashes :: (a: u64, b: u64) -> u64 {
    return a * KNUTH_GOLDEN_RATIO_64 + b;
}

expand :: (rect: Rect, amount: float) -> Rect {
    r := rect;
    r.x -= amount;
    r.y -= amount;
    r.w += 2*amount;
    r.h += 2*amount;

    return r;
}

cut_left  :: (rect: Rect, amount: float) -> (left: Rect,  remainder: Rect) {
    remainder := rect;

    remainder.w -= amount;
    remainder.x += amount;
    
    left := rect;
    left.w = amount;

    return left, remainder;
}

cut_right :: (rect: Rect, amount: float) -> (right: Rect, remainder: Rect) {
    remainder := rect;

    remainder.w -= amount;

    right := rect;
    right.x = remainder.x + remainder.w;
    right.w = amount;

    return right, remainder;
}

cut_bottom :: (rect: Rect, amount: float) -> (bottom: Rect, remainder: Rect) {
    remainder := rect;

    remainder.h -= amount;
    remainder.y += amount;

    bottom := rect;
    bottom.h = amount;

    return bottom, remainder;
}

cut_top    :: (rect: Rect, amount: float) -> (top: Rect, remainder: Rect) {
    remainder := rect;

    remainder.h -= amount;

    top := rect;
    top.h = amount;
    top.y = remainder.y + remainder.h;

    return top, remainder;
}


get_status_flags :: (r: Rect) -> Status_Flags {
    x := mouse_x_float;
    y := mouse_y_float;

    status: Status_Flags;
    if !is_visible_in_scissor(x, y) return status;
    
    if (x >= r.x) && (x <= r.x + r.w) && (y >= r.y) && (y <= r.y + r.h) {
        status |= .OVER;

        if mouse_button_left_state & .START {
            status |= .PRESSED;
        }
    }

    return status;
}

require_texture :: (data: [] u8, loc := #caller_location) -> *Texture {
    texture := New(Texture);

    success := Simp.texture_load_from_memory(texture, data);
    if !success {
        log_error("Simp could not process loaded texture data! %\n", loc);
        return null;
    }
    
    return texture;
}

ui_init :: (default_font := u8.[], procs: *Draw_Procs = null) {
    map_radiobox_full  = require_texture(memory_radiobox_full);
    map_radiobox_empty = require_texture(memory_radiobox_empty);
    map_checkbox_full  = require_texture(memory_checkbox_full);
    map_checkbox_empty = require_texture(memory_checkbox_empty);
    map_mode_circle    = require_texture(memory_mode_circle);
    map_mode_rgb       = require_texture(memory_mode_rgb);
    map_mode_hsv       = require_texture(memory_mode_hsv);
    map_mode_numbers   = require_texture(memory_mode_numbers);

    if default_font  default_font_data = default_font;
    else             default_font_data = memory_default_font;
        
    if procs {
        draw_procs = << procs;
    }

    #if USE_SIMP {
        // Ugh, we need to disambiguate an overload from Window_Creation.
        dummy_window: Window_Creation.Window_Type;
        get_mouse :: #procedure_of_call Window_Creation.get_mouse_pointer_position(dummy_window, true);

        p: Vector2 = ---;
        c: Vector4 = ---;
        memory: [] u8;
        imq1 :: #procedure_of_call Simp.immediate_quad(p, p, p, p, c);
        gfas :: #procedure_of_call Simp.get_font_at_size(memory, 1);
        
        {
            using draw_procs;
            if !texture_load_from_memory    texture_load_from_memory   = Simp.texture_load_from_memory;
            if !set_scissor                 set_scissor                = Simp.set_scissor;
            if !clear_scissor               clear_scissor              = Simp.clear_scissor;
            if !set_shader_for_color        set_shader_for_color       = Simp.set_shader_for_color;
            if !set_shader_for_images       set_shader_for_images      = Simp.set_shader_for_images;
            if !prepare_text                prepare_text               = Simp.prepare_text;
            if !draw_prepared_text          draw_prepared_text         = Simp.draw_prepared_text;
            if !get_mouse_pointer_position  get_mouse_pointer_position = get_mouse;
            if !get_font_at_size            get_font_at_size           = gfas;
            if !immediate_triangle          immediate_triangle         = Simp.immediate_triangle;
            if !immediate_quad              immediate_quad             = imq1;
            if !immediate_flush             immediate_flush            = Simp.immediate_flush;
        }
    } else {
        using draw_procs;
        assert(procs != null);  // If you are not using Simp, you need to supply all draw_procs.
        
        assert(texture_load_from_file     != null);
        assert(set_scissor                != null);
        assert(clear_scissor              != null);
        assert(set_shader_for_color       != null);
        assert(set_shader_for_images      != null);
        assert(prepare_text               != null);
        assert(draw_prepared_text         != null);
        assert(get_mouse_pointer_position != null);
        assert(get_font_at_size           != null);
        assert(immediate_triangle         != null);
        assert(immediate_quad             != null);
        assert(immediate_flush            != null);
    }
}

ui_get_button_state :: (key: Key_Code, handle: *void = null) -> Key_Current_State {
    state := input_button_states[key];
    if state {
        // Put this inside 'if state' for speed purposes.
        if !ui_can_see_event(key, handle) return .NONE;
    }

    return state;
}

ui_can_see_event :: (key: Key_Code, handle: *void) -> bool {
    return true;
}

ui_per_frame_update :: (window: Window_Type, _render_target_width: s32, _render_target_height: s32, _current_time: float64) {
    x, y, success := Window_Creation.get_mouse_pointer_position(window, true);  // This should probably be in Simp?
    if success {
        mouse_x = cast(s32) x;
        mouse_y = cast(s32) y;

        if first_mouse_update {
            first_mouse_update = false;  // The deltas are already initialized to zero.
        } else {
            mouse_delta_x_float = cast(float) mouse_x - mouse_x_float;  // mouse_x_float is currently the old value.
            mouse_delta_y_float = cast(float) mouse_y - mouse_y_float;  // mouse_x_float is currently the old value.
        }
        
        mouse_x_float = cast(float) mouse_x;
        mouse_y_float = cast(float) mouse_y;
    }

    mouse_button_left_state  = ui_get_button_state(.MOUSE_BUTTON_LEFT,  null);
    mouse_button_right_state = ui_get_button_state(.MOUSE_BUTTON_RIGHT, null);
    shift_key_state          = ui_get_button_state(.SHIFT, null);

    if last_current_time == FLOAT64_INFINITY {
        current_dt = 0;
    } else {
        current_dt   = cast(float) (_current_time - last_current_time);
    }

    last_current_time = current_time;
    current_time      = _current_time;

    render_target_width  = _render_target_width;
    render_target_height = _render_target_height;

    if !global_rounding_radius_in_pixels_is_set {
        global_rounding_radius_in_pixels = (9 / 2160.0) * render_target_height;
    }

    if !global_frame_thickness_in_pixels_is_set {
        global_frame_thickness_in_pixels = (4 / 2160.0) * render_target_height;
    }

    if !global_divider_thickness_in_pixels_is_set {
        global_divider_thickness_in_pixels = (22 / 2160.0) * render_target_height;
    }

    if !global_initial_divider_position_in_pixels_is_set {
        global_initial_divider_position_in_pixels = .25 * render_target_width;
    }
}

is_visible_in_scissor :: (x: float, y: float) -> bool {
    if !scissor_stack return true;

    top := peek_pointer(scissor_stack);
    return (x >= top.x) && (x <= top.x + top.w) && (y >= top.y) && (y <= top.y + top.h);
}

is_inside :: (x: float, y: float, r: Rect) -> bool {
    return (x >= r.x) && (x <= r.x + r.w) && (y >= r.y) && (y <= r.y + r.h);
}

is_visible_in_scissor :: (using rect: Rect) -> bool {
    return true;  // @Incomplete
}

set_scissor :: (r: Rect) {
    //
    // @Robustness: We need to think about the definition of set_scissor and
    // who exactly is inside the scissor rectangle. Do we want to be adding the +1
    // here, or should that be in Simp, or ... where?
    //
    //               -jblow, 26 June 2021.
    //
    x0 := cast(s32) r.x;
    y0 := cast(s32) r.y;
    x1 := cast(s32) (r.x + r.w + 1);
    y1 := cast(s32) (r.y + r.h + 1);
    
    Simp.set_scissor(x0, y0, x1, y1);
}

get_rect :: (x: float, y: float, w: float, h: float) -> Rect {
    r: Rect;
    r.x = x;
    r.y = y;
    r.w = w;
    r.h = h;
    
    return r;
}

get_quad :: (using r: Rect, snap_coordinates := false) -> (p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2) {
    p0 := v2(x  , y  );
    p1 := v2(x+w, y  );
    p2 := v2(x+w, y+h);
    p3 := v2(x  , y+h);

    if snap_coordinates {
        p0.x = floor(p0.x + .5);
        p0.y = floor(p0.y + .5);
        p1.x = floor(p1.x + .5);
        p1.y = floor(p1.y + .5);
        p2.x = floor(p2.x + .5);
        p2.y = floor(p2.y + .5);
        p3.x = floor(p3.x + .5);
        p3.y = floor(p3.y + .5);
    }
    
    return p0, p1, p2, p3;
}

intersect :: (a: Rect, b: Rect) -> Rect {
    x := max(a.x, b.x);
    y := max(a.y, b.y);
    w := max(min(a.x+a.w, b.x+b.w) - x, 0);
    h := max(min(a.y+a.h, b.y+b.h) - y, 0);

    rect := get_rect(x, y, w, h);

    return rect;
}
    
push_scissor :: (_rect: Rect) {
    rect := _rect;

    if scissor_stack {
        top := peek_pointer(scissor_stack);
        rect = intersect(<<top, rect);
    }

    set_scissor(rect);
    array_add(*scissor_stack, rect);
}

pop_scissor :: () {
    pop(*scissor_stack);
    
    if scissor_stack {
        r := peek(scissor_stack);
        set_scissor(r);
    } else {
        Simp.clear_scissor();
    }
}

darken :: (color: $T, t: float) -> T {
    #assert (T == Vector3) || (T == Vector4);
   
    result: T;
    result.x = lerp(color.x, 0, t);
    result.y = lerp(color.y, 0, t);
    result.z = lerp(color.z, 0, t);

    #if T == Vector4  result.w = color.w;
    
    return result;
}

whiten :: (color: $T, t: float) -> T {
    #assert (T == Vector3) || (T == Vector4);
    
    result: T;
    result.x = lerp(color.x, 1, t);
    result.y = lerp(color.y, 1, t);
    result.z = lerp(color.z, 1, t);

    #if T == Vector4  result.w = color.w;
    
    return result;
}

em :: (x: float, font: *Font) -> float {
    return font.em_width * x;
}

/*
button_colors :: (theme: *Button_Theme) -> (normal: Vector4, hilit: Vector4) {
    // @Cleanup
    return theme.background_color, theme.background_color_over;
}
*/



move_toward :: (a: float, b: float, amount_increasing: float, amount_decreasing := -1.0) -> float {
    if a > b {
        if amount_decreasing == -1  amount_decreasing = amount_increasing;

        a -= amount_decreasing;
        
        if a < b  a = b;
    } else {
        a += amount_increasing;
        if a > b  a = b;
    }

    return a;
}

// @Speed: We should not use this, since it hides whether text is prepared or not.
text_size :: (font: *Font, text: string) -> (width: float, height: float) {
    // This code all uses ui_text_size but that is not a very good idea, because
    // using the bounding box around text often just looks sucky. We want to get to a point
    // where this procedure is not being used.  -jblow, 29 April 2021.
    w := cast(float)Simp.prepare_text(font, text);
    h := cast(float)font.character_height;

    return w, h;
}

has_focus :: (rect: Rect) -> bool {
    return true;  // This is just a dummy for now!
}


#scope_module

v2 :: make_vector2;
v3 :: make_vector3;
v4 :: make_vector4;

// Arrays into which we will load the bitmaps at compile-time.
// Doing this in a somewhat awkward way because that is just how things work right now:
memory_radiobox_full, memory_radiobox_empty, memory_checkbox_full, memory_checkbox_empty, memory_default_font, memory_mode_circle, memory_mode_hsv, memory_mode_rgb, memory_mode_numbers :: #run get_global_data();

Default_Font_Info :: struct {
    pixel_height: int;
    font: *Font;
}

default_font_data: [] u8;
default_font_at_size: [..] Default_Font_Info;

get_default_font_at_size :: (fsize: float) -> *Font {
    assert(default_font_data.count != 0);
    pixel_height := cast(int) floor(fsize + .5);

    // @Speed: Could use a hash table if we think the user will have many default font instantiations.
    for default_font_at_size {
        if it.pixel_height == pixel_height  return it.font;
    }
    
    font := draw_procs.get_font_at_size(default_font_data, pixel_height);
    info := array_add(*default_font_at_size);
    info.pixel_height = pixel_height;
    info.font         = font;

    return font;
}

get_float_parameter :: (r: Rect, type: Size_Computation, local: float, global: float, override: float = FLOAT32_INFINITY) -> float {
    if override != FLOAT32_INFINITY {
        local  = override;
        global = override;
    }
    
    result: float;
    if #complete type == {
      case .RELATIVE_TO_HEIGHT;
        result = r.h * local;
      case .RELATIVE_TO_WIDTH;
        result = r.w * local;
      case .ABSOLUTE_FROM_THEME_FIELD;
        result = local;
      case; assert(false); #through;
      case .ABSOLUTE_FROM_GLOBAL;
        result = global;
    }

    return result;
}

#scope_file


global_data :: (filename: string) -> (memory: [] u8, success: bool) {
    #import "Compiler";  // We are not currently restricting this to compile-time, hmm.
    #import "File";      // We should do that somehow.

    full_name := tprint("%/data/%", #filepath, filename);

    file_data, success := read_entire_file(full_name);
    if !success {
        compiler_report(tprint("Compile-time loading of '%' failed!\n", full_name), mode=.ERROR);
        return .[], false;
    }
    
    defer free(file_data.data);
    memory := add_global_data(cast([] u8)file_data, .READ_ONLY);
    return memory, true;
}

get_global_data :: () -> [] u8, [] u8, [] u8, [] u8, [] u8, [] u8, [] u8, [] u8, [] u8 {
    success: bool;
    all_success := true;
    
    radiobox_full, radiobox_empty, checkbox_full, checkbox_empty, color_marker, mem_default_font, mem_mode_circle, mem_mode_hsl, mem_mode_rgb, mem_mode_numbers: [] u8;
    radiobox_full,  success = global_data("ui_radiobox_full.png");
    all_success &&= success;

    radiobox_empty, success = global_data("ui_radiobox_empty.png");
    all_success &&= success;

    checkbox_full,  success = global_data("ui_checkbox_full.png");
    all_success &&= success;

    checkbox_empty, success = global_data("ui_checkbox_empty.png");
    all_success &&= success;

    mem_default_font, success = global_data("Karla-Regular.ttf");
    all_success &&= success;

    mem_mode_circle, success  = global_data("mode_circle.png");
    all_success &&= success;
    
    mem_mode_hsl, success     = global_data("mode_hsl.png");
    all_success &&= success;

    mem_mode_rgb, success     = global_data("mode_rgb.png");
    all_success &&= success;

    mem_mode_numbers, success = global_data("mode_numbers.png");
    all_success &&= success;
    
    // Hmm, we do not actually use all_success now, we just report_error inside the load routine.

    return radiobox_full, radiobox_empty, checkbox_full, checkbox_empty, mem_default_font, mem_mode_circle, mem_mode_hsl, mem_mode_rgb, mem_mode_numbers;
}

