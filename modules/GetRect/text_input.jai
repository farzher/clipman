#import "Clipboard"; // Maybe only import this if someone actually uses Text_Input?

Text_Input :: struct {
    text: string;

    entered := false;
    escaped := false;
    shift_plus_enter_was_pressed := false;

    MAX_BUFFER_SIZE :: 8000;
    input_buffer: [MAX_BUFFER_SIZE] u8;
    command_history: [..] string;
    
    initted := false;
    active  := false;

    last_keypress_time: float64;

    insert_point := 0;
    command_history_index := 0;

    last_saved_input: string;
    cursor_tracking_mouse := false;

    last_text_x := -1.0;

    selection: Selection;

    did_initial_mouse_click_so_check_for_deadzone_change := false;
    
    // Auto-completion stuff below:
    
    auto_complete : Auto_Complete;
    auto_complete_data : *void = null;  // @@ Wouldn't it be nice to have closures?

    tab_pressed := false;
    completion_change_time: float64;
    
    match_array     : [] string;
    match_length    : int;
    match_selection : int;
    longest_match   : int = -1;
}


my_draw_text :: (font: *Font, x: s64, y: s64, text: string, color: Vector4, effects: Font_Effects = 0) {
    assert(font != null);  // Any substitution with the default font must have been done by the caller.
    draw_procs.prepare_text(font, text, effects);
    draw_procs.draw_prepared_text(font, x, y, color, effects);
}

init :: (using input: *Text_Input) {
    text.data  = input_buffer.data;
    text.count = 0;
    insert_point = 0;
    
    initted = true;
}

clamp_insert_point :: (using input: *Text_Input) {
    Clamp(*insert_point, 0, text.count);
}

/*
set_bounds :: (input: *Text_Input, x0: float, y0: float, x1: float, y1: float) {
    input.last_text_x = -1;

    input.x0 = cast(int) x0;
    input.y0 = cast(int) y0;
    input.x1 = cast(int) x1;
    input.y1 = cast(int) y1;
}
*/

handle_event :: (using input: *Text_Input, rect: Rect, event: Event) {
    if !initted  init(input);

    if !active {
        check_for_activating_event(input, rect, event);
        return;
    }
    
    using Event_Type;

    if event.type == TEXT_INPUT {
        utf8_text := character_utf32_to_utf8(event.utf32);
        defer free(utf8_text);

        insert_text(input, utf8_text);
    } else if event.type == KEYBOARD {
        last_keypress_time = current_time;

        key := event.key_code;
        using Key_Code;
        
        if event.key_pressed {
            if event.ctrl_pressed {
                if key == {
                    case xx #char "A"; select_all(input);
                    case INSERT;       copy_selection_to_clipboard(input, false);
                    case xx #char "C"; copy_selection_to_clipboard(input, false);
                    case xx #char "X"; copy_selection_to_clipboard(input, true);
                    case xx #char "V"; insert_clipboard_at_cursor(input);

                    case ARROW_LEFT;   move_cursor_left_by_word  (input, event.shift_pressed); return;
                    case ARROW_RIGHT;  move_cursor_right_by_word (input, event.shift_pressed); return;
                }
            }

            if event.shift_pressed {
                if key == {
                    case DELETE;       copy_selection_to_clipboard(input, true);
                    case INSERT;       insert_clipboard_at_cursor(input);
                }
            }
            
            if key == {
                case ARROW_LEFT;   move_cursor_left         (input, event.shift_pressed);
                case ARROW_RIGHT;  move_cursor_right        (input, event.shift_pressed);
                case HOME;         move_cursor_to_beginning (input, event.shift_pressed);
                case END;          move_cursor_to_end       (input, event.shift_pressed);
                
                // case ARROW_DOWN;   navigate_history_forward (input);
                // case ARROW_UP;     navigate_history_backward(input);
                
                case BACKSPACE;    backspace_from_cursor(input);
                case DELETE;       delete_from_cursor   (input);
                
                case ENTER;        press_enter(input, event.shift_pressed);
                case TAB;          press_tab  (input, event.shift_pressed);
                
                case ESCAPE;       escaped = true;
                
                case MOUSE_BUTTON_LEFT;
                    status := get_status_flags(rect);
                    if status & .OVER {
                        start_selecting(input);
                    }
            }
        } else {  // !pressed
            if key == MOUSE_BUTTON_LEFT {
                cursor_tracking_mouse = false;
            }
        }
    }
}

check_for_activating_event :: (input: *Text_Input, r: Rect, event: Event) {
    //
    // We get here when we are not active, but need to check for a click
    // to see whether we should become active.
    //
    if event.type != .KEYBOARD              return;
    if !event.key_pressed                   return;
    if event.key_code != .MOUSE_BUTTON_LEFT return;

    status := get_status_flags(r);
    if status & .OVER {
        input.active = true;
        start_selecting(input);
    }
}

refresh_input_from_history :: (using input: *Text_Input) {
    Clamp(*command_history_index, 0, command_history.count);

    if command_history_index == command_history.count {
        set_input(input, last_saved_input);
    } else {
        set_input(input, command_history[command_history_index]);
    }
}

set_input :: (using input: *Text_Input, _s: string) {
    if !initted  init(input);

    s := _s;
    if s.count >= input_buffer.count  s.count = input_buffer.count-1;  // Not sure why the -1; maybe it's a mistake.
    
    memcpy(input_buffer.data, s.data, s.count);
    text.count   = s.count;
    insert_point = s.count;
    update_auto_complete(input);
}

start_text_input :: (text_input: *Text_Input, text: string) {
    reset_all_text_inputs(text_input);  // from editor.jai
    reset(text_input);
    text_input.active = true;
    text_input.auto_complete = null;
    text_input.auto_complete_data = null;
    array_reset(*text_input.match_array);

    if text != "(null)" {
        add_text(text_input, text);
    }
}

activate :: (using input: *Text_Input) {
    active = true;
}

deactivate :: (using input: *Text_Input) {
    active = false;
}

start_selecting :: (using input: *Text_Input) {
    deselect(*selection);
    cursor_tracking_mouse = true;

    // @Robustness: We do not have access to the hash for the widget here,
    // because that is only available in draw (because it depends on the source
    // code location!) We could save the last hash or something ... but, absent
    // that, we cannot do any computations here about the deadzone. So we set
    // a boolean that says to do this stuff in the draw routine. (We would prefer
    // to set that boolean on the state struct if we could get it.)

    // In general, this shows the weird duality between the drawing part of this widget,
    // which is IMGUI-like, and the input and storage parts, which aren't.
    // Maybe we should go IMGUI with the whole thing, in which case the user would
    // pass us a state struct holding the memory, insert point etc each frame?
    // We'll see how this goes, structurally...
    
    did_initial_mouse_click_so_check_for_deadzone_change = true;
}

is_active :: (input: Text_Input) -> bool {
    return input.active;
}

get_result :: (using input: Text_Input) -> string {
    return text;
}

reset :: (using input: *Text_Input) {
    deselect(*selection);
    init(input);

    activate(input);
    entered = false;
    escaped = false;
    shift_pressed = false;    
    cursor_tracking_mouse = false;
    last_text_x = -1;
}

draw_text_input_background :: (r: Rect, theme: *Text_Input_Theme, state: *Text_Input_State, active := false, changed := false) -> (over_factor: float, pressed_factor: float) {
    // So that we can factor this out and use it from other things that don't want to instantiate
    // a text input yet, e.g. Number_Entry.
    
    // @Temporary @Hack? Update_production_value_button only uses button_theme
    // for press_duration... for now.

    // We could consider just using the Button_Theme... or making a duck copy macro!

    button := *theme.button_theme;
    
    // 
    // We piggy-back on update_production_value_button for some factors, but,
    // we interpolate 'active' on our own.
    //
    if active {
        state.active_t = move_toward(state.active_t, 1, button.down_fade_in_speed);
    } else {
        state.active_t = move_toward(state.active_t, 0, button.down_fade_out_speed);
    }
    
    status := get_status_flags(r);
    over_factor, pressed_factor := update_production_value_button(r, changed, state, status, button);

    active_factor := state.active_t;

    surface_color, frame_color, frame_thickness := get_colors_and_thickness_for_button(button, state, over_factor, pressed_factor);
    if surface_color.w {
        draw_procs.set_shader_for_color(true);
        rounded_rectangle(r, button.rectangle_shape, surface_color, frame_color, frame_thickness_override=frame_thickness);
    }

    return over_factor, pressed_factor;
}

draw :: (using input: *Text_Input, r: Rect, theme: *Text_Input_Theme, identifier: s64 = 0, loc := #caller_location) {
    if !initted  init(input);

    hash  := get_hash(loc, identifier);
    state := find_or_create_state(*table_text_input, hash);

    clamp_insert_point(input);

    x0 := cast(s32) r.x;
    y0 := cast(s32) r.y;
    x1 := cast(s32)(r.x + r.w);
    y1 := cast(s32)(r.y + r.h);


    font := theme.font;
    if !font  font = get_default_font_at_size(r.h*.65);
    
    xpad := em(theme.alignment_pad_ems, font);
    
    push_scissor(r);
    defer pop_scissor();

    status := get_status_flags(r);
    changed := cast(bool)(status & .PRESSED);

    over_factor, pressed_factor := draw_text_input_background(r, theme, state, active, changed);
    effect :: 0;

    active_factor := state.active_t;
    
    text_color       := lerp(theme.text_color, theme.text_color_over,   over_factor);
    text_color        = lerp(text_color,       theme.text_color_pressed, active_factor);

    text_width := draw_procs.prepare_text(font, text, effect);

    // If autocompletion available, take it into account:
    if match_array {
        auto_complete_text := match_array[match_selection];
        text_width = draw_procs.prepare_text(font, auto_complete_text, effect);
    }
    
    vert := theme.text_baseline_vertical_position;
    if vert == FLOAT32_INFINITY {
        vert = default_text_baseline(font, r.h);
    } else {
        vert *= r.h;
    }

    text_x := x0 + xpad;
    text_y := y0 + vert;

    if theme.alignment == {
      case .Center;
        text_x = (x1 + x0) * .5 - text_width * .5;
      case .Right;
        text_x = x1 - xpad - text_width;
      case .Left;
        text_x = x0 + xpad;
    }
    
    if !active state.camera_initted = false;
    if !state.camera_initted {
        state.camera_initted = true;
        state.camera_x = -(text_x - x0);
    }

    width_up_to_insert: s64;
    if active {
        if cursor_tracking_mouse {
            // Update the insert point based on mouse drag;
            // do this before any other logic involving the insert point,
            // and before drawing the cursor!

            // If we are already tracking, just track, even if we move outside the window.
            last_keypress_time = current_time;

            //
            // We need to figure out where in the text the user clicked. We used to do this
            // after rendering the text, so we knew for sure where it was. But this is a little
            // more laggy with regard to where the cursor appears (one frame late!), and
            // it was not helpful with regard to the new deadzone code. :DeadzoneMotion.
            // Now we do this before drawing; we need to know where the text was last frame,
            // though @Robustness, we aren't quite recomputing that here if the user-level code
            // is drawing this text input at different coordinates than it was drawn last frame.
            // (Maybe we should save the positions of all glyphs!)
            //
            // Anyway, we need to recompute the positions of all glyphs based on last_text_x,
            // which is why we use it here. Frame-to-frame feedback is slightly scary, but
            // it makes sense in this case, because hey, this is what the user clicked on.
            //
            last_text_x := state.last_displayed_text_x;
            if last_text_x == FLOAT32_INFINITY  last_text_x = text_x;

            // get_insert_point_for_cursor will re-generate all the glyphs; we could think
            // about re-using them at draw time, but, maybe text_x changes after this,
            // so, it is not guaranteed that we could. (But we could offset them by some
            // horizontal amount... hmm.)
            insert_point = get_insert_point_for_cursor(font, text, last_text_x, mouse_x, effect);

            if selection.active {
                selection.end_character = insert_point;
            } else {
                selection.start_character = insert_point;
                selection.end_character   = insert_point;
                selection.active = true;
            }
        }
        
        // Find the x coordinate of the insert point.
        s_up_to_insert := text;
        s_up_to_insert.count = insert_point;
        width_up_to_insert = draw_procs.prepare_text(font, s_up_to_insert, effect);

        margin := em(theme.text_insert_margin, font);
        Clamp(*margin, 0, 0.49 * r.w);

        alignment_pad := em(theme.alignment_pad_ems, font);
        Clamp(*alignment_pad, 0, 0.49 * r.w);

        insert_x := (x0 - state.camera_x) + width_up_to_insert;
        deadzone_x0 := x0 + margin;
        deadzone_x1 := x1 - margin;

        //
        // :DeadzoneMotion
        //
        // Suppose the user is moving the cursor around, inside text that is wider than
        // the rect used to draw this Text_Input, so that only a portion of the text can
        // be seen at one time. We want to have some margin around the cursor, so that you
        // can see past it on the right or left. That's what theme.text_insert_margin
        // is for.
        //
        // However, what happens if the user clicks to set the insert point such that it is
        // inside this margin? We don't want to move the text to put the insert point into
        // the margin, because that is disorienting to the user, and it results in other bad
        // feedback, like selecting a potentially large region of the text because it moved
        // under the cursor. So, when clicking inside these margins, we shrink the margins
        // so that the cursor is now in the deadzone. Assuming the margin is still nonzero,
        // you still get a bit of context on the side as you scroll; if the cursor scrolls
        // back toward the middle, so that the margin can grow, we grow it. When the margin
        // is restored to its original desired size, we are back to normal.
        //
        if did_initial_mouse_click_so_check_for_deadzone_change {
            did_initial_mouse_click_so_check_for_deadzone_change = false;

            // @Robustness: We are not checking the mouse_x of the actual click point!
            if (insert_x < deadzone_x0) || (insert_x > deadzone_x1) {
                state.shrunken_deadzone_margin = 0;  // Dummy value >= 0 to kick us into shrink mode. Updated below.
            }
        }
        
        if state.shrunken_deadzone_margin >= 0 {
            // If the shrunken margin got bigger, so that it approaches the preferred margin again,
            // let it get bigger. If it meets or exceeds the size of the preferred margin,
            // disable shrinking.
            if insert_x < deadzone_x0 {
                new_margin := insert_x - x0;
                state.shrunken_deadzone_margin = max(state.shrunken_deadzone_margin, new_margin);
            } else if insert_x > deadzone_x1 {
                new_margin := x1 - insert_x;
                state.shrunken_deadzone_margin = max(state.shrunken_deadzone_margin, new_margin);
            }

            if state.shrunken_deadzone_margin >= margin {
                // No need to shrink the margin any more. And turn off shrink mode.
                state.shrunken_deadzone_margin = -1;  // -1 means disable shrink mode.
            } else {
                // Recompute the margin and deadzone.
                deadzone_x0 = x0 + state.shrunken_deadzone_margin;
                deadzone_x1 = x1 - state.shrunken_deadzone_margin;
            }
        }
        
        dx := 0.0;
        if insert_x < deadzone_x0 {
            dx = deadzone_x0 - insert_x;
        } else if insert_x > deadzone_x1 {
            dx = deadzone_x1 - insert_x;
        }

        state.camera_x -= dx;
        
        left_limit  := -alignment_pad;
        right_limit := text_width + alignment_pad - (x1 - x0);
        if theme.alignment == .Left {
            if right_limit < left_limit  right_limit = left_limit;
        } else if theme.alignment == .Right {
            if left_limit > right_limit  left_limit  = right_limit;
        } else if theme.alignment == .Center {
            if right_limit < left_limit {
                mid := (left_limit + right_limit) * .5;
                left_limit = mid;
                right_limit = mid;
            }
        }
        
        Clamp(*state.camera_x, left_limit, right_limit);
        text_x = x0 - state.camera_x;
        state.last_displayed_text_x = text_x;
    }
    
    // Draw the selection if it is active.
    if input.active && nonempty(selection) {
        sx0, sx1 := get_selection_endpoints(font, text, effect, text_x, selection.start_character, selection.end_character);

        sy0 := cast(float) y0;
        sy1 := cast(float) y1;

        p0 := make_vector2(sx0, sy0);
        p1 := make_vector2(sx1, sy0);
        p2 := make_vector2(sx1, sy1);
        p3 := make_vector2(sx0, sy1);
        
        draw_procs.set_shader_for_color(true);
        draw_procs.immediate_quad(p0, p1, p2, p3, theme.selection_color);
        draw_procs.immediate_flush();
    }

    //
    // @Speed: We don't necessarily reuse prepared text here currently, because it's
    // just confusing what is going on with all the autocomplete stuff. But it's possible
    // we could raise the efficiency here.       -jblow, 1 June 2021.
    //
    if active {
        // Draw auto complete hints:
        if match_array {
            auto_complete_text  := match_array[match_selection];
            auto_complete_color := theme.text_color_autocomplete;
            if tab_pressed {
                center := 0.5;
                stride := 0.24;

                theta := 9 * (current_time - completion_change_time);

                // If we are in the first TAU/4, fake up our stride so that
                // we are brighter for longer.

                if theta < TAU * .25 {
                    stride *= 6;
                }
                
                w := cast(float)(cos(theta) * stride + center);
                Clamp(*w, 0, 1);
                
                auto_complete_color.w = w;
            }
            
            my_draw_text(font, xx text_x, xx text_y, auto_complete_text, auto_complete_color, effect);
        }
    }

    if longest_match >= 0 && longest_match < text.count {
        failed_color := theme.text_color_autocomplete_failed;

        my_draw_text(font, xx text_x, xx text_y, text, failed_color, effect);

        match_text := slice(text, 0, longest_match);
        my_draw_text(font, xx text_x, xx text_y, match_text, text_color, effect);
    } else {
        my_draw_text(font, xx text_x, xx text_y, text, text_color, effect);
    }

    // Don't draw cursor if not active.
    if !active return;

    cursor_color := get_cursor_color(input, theme, text_color);
        
    // Draw the cursor.
    // s_up_to_insert @Cutnpaste from above.
    {
        // We computed 'width_up_to_insert' above if active, which we are if we got here.
        cursor_x := text_x + width_up_to_insert;

        // Do not draw wide cursor over auto completion hint.
        max_text_count := text.count;
        if match_array max_text_count = match_array[match_selection].count;

        cw := em(theme.cursor_width_outside_text, font);
        if insert_point < max_text_count {
            cw = em(theme.cursor_width_inside_text, font);
            cursor_x -= cw * .5;
        }
        
        draw_procs.set_shader_for_color(true);
        {
            x0 := cursor_x;
            x1 := x0 + cw;
            y0, y1 := get_y_range(font, text_y);

            y0 = y1 - font.character_height;
            
            p0 := make_vector2(x0, y0);
            p1 := make_vector2(x1, y0);
            p2 := make_vector2(x1, y1);
            p3 := make_vector2(x0, y1);

            draw_procs.immediate_quad(p0, p1, p2, p3, cursor_color);
            draw_procs.immediate_flush();
        }
    }
}

#scope_file

get_cursor_color :: (using input: *Text_Input, theme: *Text_Input_Theme, non_white: Vector4) -> Vector4 {
    white := theme.cursor_color;

    t := cos((current_time - last_keypress_time) * 3);
    t *= t;
    
    color := lerp(non_white, white, cast(float32)t);
    return color;
    
    // return make_vector4(1, 1, 1, 1);
}

get_selection_indices :: (using input: *Text_Input) -> (start: int, end: int) {
    // Maybe we should just have a canonical version of
    // these stored on 'selection'.
    start := selection.start_character;
    Clamp(*start, 0, text.count);

    end   := selection.end_character;
    Clamp(*end, 0, text.count);

	if end < start {
	    Swap(*start, *end);
	}

    return start, end;
}

get_selection :: (using input: *Text_Input) -> string /* Temporary Storage */ {
    if !selection.active return "";

    start, end := get_selection_indices(input);

    _result: string;
    _result.data = text.data + start;
    _result.count = end - start;
    result := copy_temporary_string(_result);
    
    return result;
}

replace_selection :: (using input: *Text_Input, s: string) {
    start, end := get_selection_indices(input);

    pre  := text;
    pre.count = start;
    
    post := text;
    advance(*post, end);

    new_text := join(pre, s, post);
    set_input(input, new_text);

    if !s.count {
        insert_point = start;
        selection.active = false;
    } else {
        selection.start_character = start;
        selection.end_character   = start + s.count;
    }
}    


nonempty :: (selection: Selection) -> bool {
    return selection.active && (selection.start_character != selection.end_character);
}

#scope_export

sanitize :: (s: string) -> string {
    pieces := break_into_lines(s, " ");
    
    return join(..pieces);
}

seek_left_one_utf8_character :: (s: string, _point: int) -> int {
    point := _point - 1;
    while point > 0 {
        c := s[point];
        if (192 & c) != 128  return point;
        point -= 1;
    }

    return 0;
}

seek_left_one_word :: (s: string, _point: int) -> int { // todo doesn't work
    point := _point - 1;
    if point < 0  return 0;

    stop_on_next_space := s[point] != #char " ";

    while point > 0 {
        c := s[point];
        if !stop_on_next_space && c != #char " "  stop_on_next_space = true;
        if  stop_on_next_space && c == #char " "  return point+1;
        point -= 1;
    }

    return 0;
}

seek_right_one_word :: (s: string, _point: int) -> int { // todo doesn't work
    point := _point;
    if point >= s.count  return s.count;

    stop_on_next_space := s[point] != #char " ";

    while point < s.count {
        c := s[point];
        if !stop_on_next_space && c != #char " "  stop_on_next_space = true;
        if  stop_on_next_space && c == #char " "  return point;
        point += 1;
    }

    return s.count;
}

get_y_range :: (font: *Font, text_y: float) -> (y0: float, y1: float) {
    assert(font != null);
    
    FONT_CURSOR_EXTRA_HEIGHT :: 0.1;  // @Hardcode @Cleanup
    y0 := text_y + font.typical_descender;
    y1 := y0 + font.typical_ascender + FONT_CURSOR_EXTRA_HEIGHT * font.character_height;

    y1 += 1;  // To include the top pixel, rather than limit just before the top pixel.
    
    padding := (y1 - y0) / 8;

    // We tend to need more extra padding on the top than bottom, since most letters don't have descenders.
    y0 -= padding;
    y1 += padding * 2;
    
    return y0, y1;
}


Selection :: struct {
    start_line       := -1;
    start_character  : int;

    end_line         := -1;
    end_character    : int;

    active := false;
}

deselect :: (using selection: *Selection) {
    active = false;
}

make_forward_selection :: (old: Selection) -> Selection {
    swap := false;
    if old.start_line > old.end_line {
        swap = true;
    } else if old.start_line == old.end_line {
        if old.start_character > old.end_character {
            swap = true;
        }
    }

    if !swap return old;

    result := old;
    Swap(*result.start_line, *result.end_line);
    Swap(*result.start_character, *result.end_character);

    return result;
}


// Autocomplete stuff:

//
// To add auto-complete to a Text_Input, implement a function of type Auto_Complete and call
// set_auto_complete(). The 'longest_match_length' return value is used by the Text_Input to
// color the text to show how much of what you typed is correct; thus it must represent
// the longest substring match even if that match is not complete (and thus 'results' is empty).
//
Auto_Complete :: #type (str: string, data: *void) -> (results: [] string, longest_match_length: int);

#scope_file

reset_auto_complete :: (using input: *Text_Input) {
    array_reset(*match_array);    // Avoid leaking. @@ Ideally this should happen automatically in the assignment. Assignment could even avoid reallocating memory.

    if auto_complete {
        
        if text match_array, longest_match = auto_complete(text, auto_complete_data);

        get_match_length :: (match_array: []string, n: int) -> int {
            if match_array.count == 0 return 0;
            if match_array.count == 1 return match_array[0].count;

            n -= 1;
            while true {
                n += 1;

                if n == match_array[0].count break;
                c := match_array[0][n];

                // All the matches in match_array have the same from 0 to n-1;
                all_match := true;

                for cmd:match_array {
                    if n >= cmd.count || cmd[n] != c {
                        all_match = false;
                        break;  // @@ Does jai support labeled breaks?
                    }
                }

                if !all_match break;
            }

            return n;
        }

        match_length = get_match_length(match_array, input.text.count);
        match_selection = 0;

        // If our text is an exact match for array[0], then one of the completions
        // is our exact string ... but don't use that as the first completion, since
        // we want to give the user some visual information that other completions
        // exist. So just rotate our selection to the next one.
        if (match_array.count > 1) && (text == match_array[0])  match_selection += 1;
    }
}

// Update matches while trying to preserve the current selection.
update_auto_complete :: (using input: *Text_Input) {
    tab_pressed = false;
    
    if match_array {
        // Try to preserve previous selection.
        last_match := match_array[match_selection];

        reset_auto_complete(input);

        // Restore previous selection.    
        for match_array {
            if it == last_match match_selection = it_index;
        }
    } else {
        // There was no selection, just autocomplete.
        reset_auto_complete(input);
    }
}

// Tab autocompletes up to match_length.
advance_auto_complete :: (using input: *Text_Input, reverse:bool) {
    if match_array {
        new_text := slice(match_array[match_selection], 0, match_length);
        if text != new_text set_input(input, new_text);
        else {
            if reverse{
                match_selection -= 1;
                if (match_selection < 0) match_selection = match_array.count;
            }
            else {
                match_selection += 1;
                if (match_selection == match_array.count) match_selection = 0;
            }
        }
    }
}

// Accept the currently selected match. Returns false if there's nothing to accept, or already accepted.
accept_auto_complete :: (using input: *Text_Input) -> bool {
    if !match_array return false;
    if match_array[match_selection] == text return false;

    set_input(input, match_array[match_selection]);
    return true;
}

#scope_export

set_auto_complete :: (input: *Text_Input, proc: Auto_Complete, data: *void) {
    input.auto_complete      = proc;
    input.auto_complete_data = data;
	reset_auto_complete(input);
}

break_into_lines :: (s: string, between_lines_string := "") -> [] string {
    pieces: [..] string;
    pieces.allocator = __temporary_allocator;
    
    cursor := 0;
    for i: 0..s.count-1 {
        if (s[i] == 10) || (s[i] == 13) {
            to_add: string;
            to_add.data  = s.data + cursor;
            to_add.count = i - cursor;

            if to_add {
                array_add(*pieces, to_add);
                if between_lines_string array_add(*pieces, between_lines_string);
            }
            
            cursor = i + 1;
        }
    }
    
    to_add: string;
    to_add.data  = s.data + cursor;
    to_add.count = s.count - cursor;

    if to_add array_add(*pieces, to_add);

    return pieces;
}
    

get_selection_endpoints :: (font: *Font, text: string, effect: Font_Effects, text_x: float, start_character: int, end_character: int) -> (x0: float, x1: float) {
    sx0, sx1: float;
    s_up_to_start := text;
    s_up_to_start.count = start_character;

    s_up_to_end := text;
    s_up_to_end.count = end_character;
    
    start_width := draw_procs.prepare_text(font, s_up_to_start, effect);
    end_width   := draw_procs.prepare_text(font, s_up_to_end,   effect);

    sx0 = text_x + start_width;
    sx1 = text_x + end_width;

    return sx0, sx1;
}

get_insert_point_for_cursor :: (font: *Font, text: string, text_x: float, cursor_x: int, effect: Font_Effects, glyphs_prepped := false) -> int {
    // @Temporary: Assume the number of glyphs is equal to the
    // number of characters. Not necessarily true.
    // This ALSO assumes that 'text' is only single-byte characters,
    // which won't last long. But let's just get this working.
    // Eventually, we should expand 'text' to an array of utf32
    // before rendering.  -jblow, 4 February 2017

    if glyphs_prepped {
    } else {
        draw_procs.prepare_text(font, text, effect);
    }        
    
    
    best_byte_offset := -1;
    best_dist := FLOAT32_MAX;

    x := text_x;
    for glyph, index: font.temporary_glyphs {
        dist := abs(cursor_x - x);
        if dist < best_dist  {
            best_dist = xx dist;
            byte_offset := font.temporary_glyphs_byte_offsets[index];
            assert(byte_offset >= 0);
            best_byte_offset = byte_offset;
        }

        // Once dist goes past the minimum and starts increasing,
        // we could early-out, but we are not doing that yet.

        x += xx glyph.advance;
    }

    // Allow ourselves to click beyond the last character.
    dist := abs(cursor_x - x);
    if dist < best_dist  best_byte_offset = text.count;

    return best_byte_offset;
}

//
// We have broken out all the text editing routines into separately-callable
// stuff so that you can call them from your own code without having to go through
// the UI to do so:
//


clear_text :: (input: *Text_Input) {
    input.text.count = 0;
    input.insert_point = 0;
}

set_text :: (input: *Text_Input, s: string) {
    clear_text(input);
    append_text(input, s);
}

append_text :: (using input: *Text_Input, s: string) {
    bytes_available := input_buffer.count - text.count;
    to_copy := min(bytes_available, s.count);
    
    memcpy(input_buffer.data + text.count, s.data, to_copy);
    text.count += to_copy;
    insert_point += to_copy;  // @Hack: Assume insert_point is at the end. If we want this to be more robust, we could just insert at the point here as we do when pasting.

    update_auto_complete(input);
}


insert_text :: (using input: *Text_Input, s: string) -> bool {
    // If there's not enough room, none of the text is inserted. Usually called one character at a time by the text in put handler.
    if text.count + s.count > input_buffer.count return false;  // Not enough room!

    if nonempty(selection) {
        replace_selection(input, "");
    }

    clamp_insert_point(input);
    
    if insert_point < text.count {
        // Copy right-to-left so that we don't wipe out our own text
        // for small inserts. 
        i := text.count;
        while i > insert_point {
            input_buffer[i] = input_buffer[i-s.count];
            i -= 1;
        }
    }

    memcpy(input_buffer.data + insert_point, s.data, s.count);

    text.count   += s.count;
    insert_point += s.count;
    update_auto_complete(input);

    return true;
}

select_all :: (using input: *Text_Input) {
    selection.active = true;
    selection.start_character = 0;
    selection.end_character = text.count;
}    

copy_selection_to_clipboard :: (input: *Text_Input, cut := false) {
    if nonempty(input.selection) {
        sel := get_selection(input);  // This does not make new memory.
        os_clipboard_set_text(sel);
        if cut  replace_selection(input, "");
    }
}

insert_clipboard_at_cursor :: (using input: *Text_Input) {
    // @Cleanup: We should do it like Braid / Witness and
    // pass a 'v' and accompanying flags, and do whatever
    // we need to do to massage the Windows input to be
    // in this form.
    unsanitized_paste_text := os_clipboard_get_text();
    defer free(unsanitized_paste_text);

    paste_text := sanitize(unsanitized_paste_text);
    defer free(paste_text);
    
    if nonempty(selection) {
        replace_selection(input, "");
    }
    
    if text.count + paste_text.count <= input_buffer.count {
        pre := text;
        pre.count = insert_point;

        post: string;
        post.data  = text.data  + insert_point;
        post.count = text.count - insert_point;

        combined := join(pre, paste_text, post);
        defer free(combined);
        set_input(input, combined);

        insert_point = pre.count + paste_text.count;
    }
}

move_cursor_left :: (using input: *Text_Input, want_selection := false) {
    if nonempty(selection) && !want_selection {
        insert_point = min(selection.start_character, selection.end_character);
        selection.active = false;
        return;
    }

    reset_or_begin_selection(input, want_selection);
    
    prev_point := seek_left_one_utf8_character(text, insert_point);
    insert_point = prev_point;
    clamp_insert_point(input);
    
    update_selection_after_cursor_movement(input);
}

move_cursor_right :: (using input: *Text_Input, want_selection := false) {
    if nonempty(selection) && !want_selection {
        insert_point = max(selection.start_character, selection.end_character);
        selection.active = false;
        return;
    }

    reset_or_begin_selection(input, want_selection);

    if insert_point < text.count {
        nbytes := 1 + trailingBytesForUTF8[text[insert_point]];
        insert_point += nbytes;
        clamp_insert_point(input);
    }
    
    update_selection_after_cursor_movement(input);
}

move_cursor_left_by_word :: (using input: *Text_Input, want_selection := false) {
    reset_or_begin_selection(input, want_selection);
    insert_point = seek_left_one_word(text, insert_point);
    update_selection_after_cursor_movement(input);
}

move_cursor_right_by_word :: (using input: *Text_Input, want_selection := false) {
    reset_or_begin_selection(input, want_selection);
    insert_point = seek_right_one_word(text, insert_point);
    update_selection_after_cursor_movement(input);
}

move_cursor_to_beginning :: (using input: *Text_Input, want_selection := false) {
    reset_or_begin_selection(input, want_selection);
    insert_point = 0;
    update_selection_after_cursor_movement(input);
}

move_cursor_to_end :: (using input: *Text_Input, want_selection := false) {
    reset_or_begin_selection(input, want_selection);
    insert_point = input.text.count;
    update_selection_after_cursor_movement(input);
}


navigate_history_backward :: (using input: *Text_Input) {
    // @@ Handle autocomplete navigation.
    selection.active = false;
    if command_history_index == command_history.count {
        if last_saved_input  free(last_saved_input);
        last_saved_input = copy_string(text);
    }
    
    command_history_index -= 1;
    refresh_input_from_history(input);
}

navigate_history_forward :: (using input: *Text_Input) {
    // @@  Handle autocomplete navigation.
    selection.active = false;
    if command_history_index < command_history.count {
        // Only do this if we're not at the end, because
        // we only save your input text when you leave
        // the last line.
        command_history_index += 1;
        refresh_input_from_history(input);
    }
}

backspace_from_cursor :: (using input: *Text_Input) {
    if nonempty(selection) {
        replace_selection(input, "");
    } else if (insert_point <= text.count) && (insert_point >= 1) {
        prev_point := seek_left_one_utf8_character(text, insert_point);
        nbytes := insert_point - prev_point;
        for i: prev_point..text.count-1-nbytes {
            text[i] = text[i+nbytes];
        }

        insert_point -= nbytes;
        text.count   -= nbytes;
        update_auto_complete(input);
    }
}

delete_from_cursor :: (using input: *Text_Input) {
    if nonempty(selection) {
        replace_selection(input, "");
    } else if insert_point < text.count {
        nbytes := 1 + trailingBytesForUTF8[text[insert_point]];
        for i: insert_point..text.count-nbytes-1 {
            text[i] = text[i+nbytes];
        }

        text.count -= nbytes;
        update_auto_complete(input);
    }
}

press_enter :: (using input: *Text_Input, shift_pressed := false) {
    handled := false;
    if tab_pressed {
        handled = accept_auto_complete(input);
    }
    
    entered = true;
    shift_plus_enter_was_pressed = shift_pressed;

    copy := copy_string(text);  // @Investigate
    if text  array_add(*command_history, copy);  // Don't add blank lines.
    command_history_index += 1;
}

press_tab :: (using input: *Text_Input, shift_pressed := false) {
    completion_change_time = current_time;

    if !tab_pressed {
        tab_pressed = true;
    } else {
        advance_auto_complete(input, reverse=shift_pressed);
        tab_pressed = true;  // This must happen after advance_auto_complete since that resets it indirectly.
    }
}

#scope_file

reset_or_begin_selection :: (using input: *Text_Input, do_begin: bool) {
    if do_begin {
        if !selection.active {
            selection.active          = true;
            selection.start_character = insert_point;
            selection.end_character   = insert_point;
        }
    } else {
        selection.active = false;
    }
}

update_selection_after_cursor_movement :: (using input: *Text_Input) {
    if selection.active selection.end_character = insert_point;
}

