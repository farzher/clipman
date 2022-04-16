// 
// Number_Input has many similarities with slider, and we could think about combining them...
//
number_input :: (_r: Rect, text: string, value: *$T, min_value: T, max_value: T, theme: *Number_Input_Theme, identifier: s64 = 0, loc := #caller_location, parse_proc: (string) -> (T, bool) = null) -> bool {
    r := _r;
    hash  := get_hash(loc, identifier);
    state, created := find_or_create_state(*table_number_input, hash);

    font := theme.font;
    if !font  font = get_default_font_at_size(r.h *.65);

    if !state.inputting_text {
        over_factor, pressed_factor := draw_text_input_background(r, *theme.text_input_theme, *state.text_input_state);
    }
    
    status := get_status_flags(r);

    if (status & .OVER) && (mouse_button_left_state & .START) && !state.inputting_text {
        state.inputting_text = true;

        input := grab_text_input(state);
        set_text(input, text);
        activate(input);
    }

    // @Copypasta from Slider. @Cleanup!!
    body_rect := r;
    input: *Text_Input;
    focus := has_focus(body_rect);
    if state.inputting_text {
        input = has_active_text_input(state, body_rect);
        if (!input) || (!input.active) || !focus  state.inputting_text = false;
    }
    
    if state.inputting_text {
        text_input_theme := theme.text_input_theme;
        if !text_input_theme.font  text_input_theme.font = font;
        
        draw(input, body_rect, *text_input_theme, identifier, loc);

        if input.entered {
            state.inputting_text = false;
            input.entered = false;
            text := input.text;

            // The @Copypasta below looks dumb, but the issue is, string_to_int just returns int,
            // which will generate an error if we make result of type T. Maybe we should call a
            // different routine instead that does the clamping-to-type part of set_and_maybe_clamp... !
            if parse_proc {
                result, success := parse_proc(text);
                if success {
                    set_and_maybe_clamp(result, value, min_value, max_value, theme.clamp_low, theme.clamp_high);
                    return true;
                }
            } else {
                #if (T == float64) || (T == float32) {
                    result, success := string_to_float(text);
                    if success {
                        set_and_maybe_clamp(result, value, min_value, max_value, theme.clamp_low, theme.clamp_high);
                        return true;
                    }
                } else {
                    result, success := string_to_int(text);
                    if success {
                        set_and_maybe_clamp(result, value, min_value, max_value, theme.clamp_low, theme.clamp_high);
                        return true;
                    }
                }
            }            
        }
        
        return false;
    } else {
        label(r, text, *theme.label_theme);
    }
    
    return false;
}
