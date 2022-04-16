slider :: (_r: Rect, value: *$T, min_value: T, max_value: T, spinbox_step: T, theme: *Slider_Theme, prefix := "", suffix := "", identifier: s64 = 0, loc := #caller_location) -> bool { 
    #assert (T == float) || (T == float64) || is_integer_type(T);

    hash  := get_hash(loc, identifier);
    state, created := find_or_create_state(*table_slider, hash);

    if created set_initial_value(state, << value);

    text: string;
    if !state.inputting_text {
        #if (T == float64) || (T == float32) {
            text = tprint("%1%2%3", prefix, formatFloat(<<value, trailing_width=theme.decimals, zero_removal=.NO), suffix);
        } else {
            text = tprint("%1%2%3", prefix, <<value, suffix);
        }
    }

    font := theme.foreground.font;
    if !font  font = get_default_font_at_size(_r.h *.65);

    text_width, text_height := text_size(font, text);

    body_rect := _r;  // We will probably cut the spinbox off here later...!
    status := get_status_flags(body_rect);

    changed := false;
    if theme.text_editable {
        // Let's do it when the user clicks anywhere in the slider, not just the text.

        focus := has_focus(body_rect);
        down  := focus && (mouse_button_left_state & .DOWN);

        if (status & .OVER) && (mouse_button_right_state & .START) && !state.inputting_text { // @Incomplete: || ui.mouse_button_left_double_click) {
            // Do something here about focus. For now we require the user to handle it.ui.force_focus = true;
            // focus = true;
            state.inputting_text = true;
            input := grab_text_input(state);

            s := tprint("%", <<value);
            set_text(input, s);
            activate(input);
            changed = true;
        }

        input: *Text_Input;
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
                
                #if (T == float64) || (T == float32) {
                    result, success := string_to_float(text);
                    if success {
                        set_and_maybe_clamp(result, value, min_value, max_value, theme.clamp_text_input_low, theme.clamp_text_input_high);
                        return true;
                    }
                } else {
                    result, success := string_to_int(text);
                    if success {
                        set_and_maybe_clamp(result, value, min_value, max_value, theme.clamp_text_input_low, theme.clamp_text_input_high);
                        return true;
                    }
                }
                
            }
            
            return false;
        }
    }

    if theme.use_spinboxes {
        spinbox_rect: Rect = ---;
        spinbox_rect, body_rect = cut_right(body_rect, 2 * theme.spinbox_button_width * body_rect.h);

        // Since we changed body_rect, re-get the status.
        status = get_status_flags(body_rect);

        button_theme := theme.spinbox_theme;

        up_rect, down_rect := cut_right(spinbox_rect, spinbox_rect.w * .5);

        result := <<value;
        button_theme.rectangle_shape.rounding_flags = Rectangle_Shape.Rounding_Flags.NORTHWEST | .SOUTHWEST;
        pressed_down, state_down := button(down_rect, "", *button_theme, xx hash);  // Use current location.
        button_theme.rectangle_shape.rounding_flags = Rectangle_Shape.Rounding_Flags.NORTHEAST | .SOUTHEAST;
        pressed_up, state_up     := button(up_rect,   "", *button_theme, xx hash);  // Use current location.

        triangle_margin := up_rect.w * 0.1;

        draw_procs.set_shader_for_color();

        {
            p0, p1, p2, p3 := get_quad(down_rect);
            p4 := to_vec3(lerp(p0, p3, .5));
            p4.x += triangle_margin;
            p5 := to_vec3(p1);
            p5.x -= triangle_margin;
            p5.y += triangle_margin;
            p6 := to_vec3(p2);
            p6.x -= triangle_margin;
            p6.y -= triangle_margin;

            draw_arrow(state_down, p4, p5, p6, *button_theme);
        }
        {
            p0, p1, p2, p3 := get_quad(up_rect);
            p4 := to_vec3(lerp(p1, p2, .5));
            p4.x -= triangle_margin;
            p5 := to_vec3(p0);
            p5.x += triangle_margin;
            p5.y += triangle_margin;
            p6 := to_vec3(p3);
            p6.x += triangle_margin;
            p6.y -= triangle_margin;

            draw_arrow(state_up, p4, p5, p6, *button_theme);
        }

        
        if pressed_up    result += spinbox_step;
        if pressed_down  result -= spinbox_step;

        if pressed_up || pressed_down {
            set_and_maybe_clamp(result, value, min_value, max_value, theme.clamp_text_input_low, theme.clamp_text_input_high);
        }
    }
    
    started_sliding := false;
    if status & .PRESSED /* @Incomplete && !ui.slider_input_mode*/ {
        // Started dragging. We can do some visual thing here...

        // Anything else could have changed this value, so, when we start sliding, set the initial value
        // so that we know how clamping should behave.
        set_initial_value(state, <<value);
        started_sliding = true;
    }

    dt := current_dt;

    sliding_t_target := 0.0;
    value_denom := max_value - min_value;
    if !value_denom  value_denom = 1;
    t := (cast(float)(<<value - min_value)) / value_denom;

    if state.sliding {
        if !(mouse_button_left_state & .DOWN) {
            state.sliding = false;
            changed = true;
        }
    } else {
        if status & .PRESSED {
            state.sliding = true;
            state.sliding_is_relative = theme.sliding_is_relative;  // Can become relative later by pressing shift.
            state.accumulated_delta_for_int_slider = 0;
        }
    }

    surface_margin := body_rect.h * min(theme.surface_margin, .49);
    surface_margin = floor(surface_margin + .5);
    
    slowing_t_target := 0.0;
    if state.sliding {
        sliding_t_target = 1;

        relative_slide_factor := theme.relative_slide_factor;

        shift_state := ui_get_button_state(.SHIFT);
        if !theme.sliding_becomes_relative_by_pressing_shift  shift_state = 0;  // Just disable shift.
        
        if shift_state & .DOWN {
            // @Responsiveness: slowing_t will be 0 on the first slowing frame, which is generally bad for feeling reactive.
            relative_slide_factor  = theme.relative_slide_factor_modified;
            state.sliding_is_relative = true;

            slowing_t_target = 1;
        }

        denom := body_rect.w - 2*surface_margin;
        if !denom denom = 1;

        if state.sliding_is_relative {
            // Relative slider motion.
            //
            // The deal with allowing you to stay outside if you start outside is, hey, if you
            // typed a manual value into the thing that is outside the range because you need it to be,
            // well, it is a bummer if the slider kills that value as soon as you drag it a little.
            // So we give you the option to continue unclamped.
            //

            initial := get_initial_value(state, T);
            started_inside := (initial >= min_value) && (initial <= max_value);

            delta := mouse_delta_x_float * relative_slide_factor;
            #if (T == float64) || (T == float32) {
                t += delta / denom;
                
                if started_inside || theme.do_clamp_if_we_are_relative_dragging_but_started_outside_the_clamp_range {
                    Clamp(*t, 0, 1);
                }

                <<value = lerp(min_value, max_value, t);
            } else {
                // For integer types:
                // Accumulate delta until we get enough for an integer value, then subtract it off.
                quantum := (1.0 / value_denom) * denom;
                state.accumulated_delta_for_int_slider += delta;

                if state.accumulated_delta_for_int_slider <= -quantum {
                    state.accumulated_delta_for_int_slider += quantum;
                    <<value -= 1;
                } else if state.accumulated_delta_for_int_slider >= quantum {
                    state.accumulated_delta_for_int_slider -= quantum;
                    <<value += 1;
                }

                if started_inside || theme.do_clamp_if_we_are_relative_dragging_but_started_outside_the_clamp_range {
                    Clamp(value, min_value, max_value);
                }
            }
        } else {
            // Absolute motion.
            
            t = (mouse_x_float - body_rect.x - 1) / denom;
            t = saturate(t);
        
            #if (T == float64) || (T == float32) {
                <<value = lerp(min_value, max_value, t);
            } else {
                // Integer types.
                // If you give us min_value and max_value that are out of range, we will just truncate.
                <<value = cast(T)(0.5 + lerp(cast(float)min_value, cast(float)max_value, t));
                value_denom := max_value - min_value;
                if !value_denom  value_denom = 1;
                t = cast(float)(<<value - min_value) / value_denom;
            }
        }
    }

    // We already placed the rect ... we don't want to widen the placement,
    // as that would move other widgets. But, we want to enlarge the whole bar
    // in-place.
    if state.slowing_t {
        dy := em(.25, font) * state.slowing_t;
        body_rect.y -= dy;
        body_rect.h += 2*dy;
    }
    
    qrect := body_rect;
    qrect.x += surface_margin;
    qrect.y += surface_margin;
    qrect.h -= 2*surface_margin;
    qrect.w = (body_rect.w - 2*surface_margin) * cast(float) t;

    #if T == int {
        if qrect.w == 0 qrect.w = 1;
    }

    state.sliding_t = move_toward(state.sliding_t, sliding_t_target, dt * 5);  // @Theme

    if slowing_t_target {
        state.slowing_t = move_toward(state.slowing_t, slowing_t_target, dt * 4.5);  // @Theme
    } else {
        state.slowing_t = move_toward(state.slowing_t, slowing_t_target, dt * 15);  // @Theme
    }

    fg_status := get_status_flags(qrect);
    if state.sliding  { fg_status |= .OVER; status |= .OVER; }
    fg_changed := changed;
    bg_changed := changed; 
    fg_pressed_factor, fg_over_factor := update_production_value_button(qrect, fg_changed, *state.foreground, fg_status, *theme.foreground);
    bg_pressed_factor, bg_over_factor := update_production_value_button(body_rect, bg_changed, *state.background, status, *theme.background);
    
    sliding_t := state.sliding_t;
    
    fg_color, fg_frame_color, fg_frame_thickness := get_colors_and_thickness_for_button(*theme.foreground, *state.foreground, fg_over_factor, fg_pressed_factor);
    bg_color, bg_frame_color, bg_frame_thickness := get_colors_and_thickness_for_button(*theme.background, *state.background, bg_over_factor, bg_pressed_factor);

    draw_procs.set_shader_for_color();

    if bg_color.w || bg_frame_color.w {
        rounded_rectangle(body_rect, theme.foreground.rectangle_shape, bg_color, bg_frame_color, bg_frame_thickness);
    }

    if fg_color.w || fg_frame_color.w {
        rounded_rectangle(qrect,     theme.background.rectangle_shape, fg_color, fg_frame_color, fg_frame_thickness);
    }
    
    draw_procs.immediate_flush();
    label_from_prepared_text(body_rect, font, *theme.foreground.label_theme);

    return cast(bool)(status & .DOWN);
}

set_initial_value :: (state: *Slider_State, value: $T) {
    #assert(T == float64) || (T == float32) || is_integer_type(T);  // @Incomplete: We will want to support all int types.
    #if T == float64  state.initial_value_float64 = value;
    #if T == float32  state.initial_value_float32 = value;
    else { << cast(*T) *state.initial_value_int = value; } // Integer type.
}

get_initial_value :: (state: *Slider_State, $T: Type) -> T {
    #assert(T == float64) || (T == float32) || is_integer_type(T);  // @Incomplete: We will want to support all int types.
    #if T == float64  return state.initial_value_float64;
    else #if T == float32  return state.initial_value_float32;
    else return << cast(*T) *state.initial_value_int; // Integer type.

    assert(false);
    return 0;
}


set_and_maybe_clamp :: (new_value: $ValueType, pointer: *$T, min_value: T, max_value: T, clamp_low: bool, clamp_high: bool) {
    is_int :: #run is_integer_type(T);
    #if is_int {
        // Clamping the input value to T's range, if necessary.
        // Somewhat redundant with theme.clamp*, except, those options might be disabled!

        t_value := clamp_to_another_integer_type(new_value, T);
    } else {
        t_value := cast(T) new_value;  // float64 to float32, maybe.
    }

    if clamp_low   t_value = max(min_value, t_value);
    if clamp_high  t_value = min(max_value, t_value);
    
    <<pointer = t_value;
}    


to_vec3 :: (v2: Vector2) -> Vector3 {
    result: Vector3;
    result.xy = v2;

    return result;
}
    
draw_arrow :: (state: *Button_State, p4: Vector3, p5: Vector3, p6: Vector3, theme: *Button_Theme) {
    ARROW_INTERPOLATION_AMOUNT :: .14;
    s := state.action_duration * 2;
    Clamp(*s, 0, 1);
    t := -4*s*s + 4*s;

    // f(x) = ax**2 + b*x
    // f(0) = 0
    // f(1) = 0  ; a = -b
    // f(.5) = 1 ; a * .25 + b*.5 = 1  a*.25 - a*.5 = 1 ; -.25a = 1; a = -4; b = +4

    // f(x) = -4x**2 + 4x
    new_p5 := lerp(p5, p6, t * ARROW_INTERPOLATION_AMOUNT);
    new_p6 := lerp(p6, p5, t * ARROW_INTERPOLATION_AMOUNT);

    color := lerp(theme.text_color, theme.text_color_over, state.over_effect_t);
    color = lerp(color, theme.text_color_pressed, t);

    ca := color;
    cb := color;  // Could put a gradient on the triangle if we want...!
    draw_procs.immediate_triangle(p4, new_p5, new_p6, ca, cb, cb);
}

