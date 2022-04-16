dropdown :: (r: Rect, choices: [] string, current_value_pointer: *s32, theme: *Dropdown_Theme = null, identifier: s64 = 0, loc := #caller_location) {
    if !theme  theme = *default_panel_theme.dropdown_theme;
    
    // r just describes the Rect for the top of the dropdown.
    // The individual elements below are sized according to theme.button_theme.

    // Draw the background behind the primary choice.

    label_current_value := theme.theme_for_current_value.label_theme;

    // Let's avoid an ABC in case the user passes us a dirty value.
    current_string := "";
    current_value := <<current_value_pointer;
    if (current_value >= 0) && (current_value < choices.count) {
        current_string = choices[current_value];
    }

    hash   := get_hash(loc, identifier);
    state  := find_or_create_state(*table_dropdown, hash);


    // Carve off the dropdown indicator from the rest of the button.
    indicator_width := theme.dropdown_indicator_aspect_ratio * r.h;
    r_right, r_left := cut_right(r, indicator_width);

    // @Incomplete: This button hack means the button will update twice as fast, so we need to fix that.
    current := theme.theme_for_current_value;
    current.rectangle_shape.rounding_flags = Rectangle_Shape.Rounding_Flags.NORTHWEST | .SOUTHWEST;
    
    pressed, current_value_state := button(r_left, current_string, *current, identifier, loc);
    current.rectangle_shape.rounding_flags = Rectangle_Shape.Rounding_Flags.NORTHEAST | .SOUTHEAST;
    other_pressed := button(r_right, "", *current, identifier, loc);  // Same identifier and loc so they press simultaneously.

    
    if pressed || other_pressed {
        state.open = !state.open;
    }

    
    triangle_margin := r_right.w * 0.1;

    //
    // Update open_t for drawing arrows, etc.
    //

    dt := current_dt;
    if state.open {
        state.open_t = move_toward(state.open_t, 1, dt * theme.arrow_flip_up_rate);
    } else {
        state.open_t = move_toward(state.open_t, 0, dt * theme.arrow_flip_down_rate);
    }
    
    //
    // Draw the dropdown arrow.
    //
    draw_procs.set_shader_for_color();
    {
        p0, p1, p2, p3 := get_quad(r_right);
        p4 := to_vec3(lerp(p0, p1, .5));
        p4.y += triangle_margin;
        p5 := to_vec3(p2);
        p5.x -= triangle_margin;
        p5.y -= triangle_margin;
        p6 := to_vec3(p3);
        p6.x += triangle_margin;
        p6.y -= triangle_margin;

        p5 = lerp(p5, p4, .6);
        p6 = lerp(p6, p4, .6);

        k := 2.3*triangle_margin;
        p4.y += k;
        p5.y += k;
        p6.y += k;

        if state.open_t {
            theta := cast(float)(state.open_t * TAU * .25);
            barycenter := (p4 + p5 + p6) * (1 / 3.0);

            p4 -= barycenter;
            p5 -= barycenter;
            p6 -= barycenter;

            p4.xy = rotate(p4.xy, theta);
            p5.xy = rotate(p5.xy, theta);
            p6.xy = rotate(p6.xy, theta);

            p4 += barycenter;
            p5 += barycenter;
            p6 += barycenter;
        }
        
        
        draw_arrow(current_value_state, p4, p5, p6, *theme.theme_for_current_value);
    }

    
    choice_theme := *theme.theme_for_each_choice;
    label_each_choice := choice_theme.label_theme;

    // For now, assume the choices are the same height as the current value display.
    s := r;
    s.y -= r.h;

    pick_choice := -1;
    if state.open {
        for choices {
            sub_hash := get_hash(#location(), it_index);
            choice_hash := combine_hashes(hash, sub_hash);

            t := choice_theme;
            if (cast(s32) it_index) == current_value  t = *theme.theme_for_current_choice;
            
            pressed, _, released := button(s, it, t, xx choice_hash, loc);
            s.y -= s.h;

            if released {
                pick_choice = it_index;
            }
        }

        if pick_choice >= 0 {
            state.open = false;
            <<current_value_pointer = cast(s32) pick_choice;
            update_action_durations(current_value_state, *theme.theme_for_current_value, true, 0);
        }
    }
}
