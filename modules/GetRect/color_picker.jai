//
// To Do:
//
// Square-to-circle warp option on sphere picker.
// Dark / light options on circle picker.
// Nicer-looking dot product sphere option on circle picker.
// 

MAX_STASHED_COLORS :: 10;

Color_Pick_Mode :: enum {
    HSV_CIRCLE  :: 0;
    HSV_SLIDERS :: 1;
    RGB_SLIDERS :: 2;
    TYPE_INS    :: 3;
}

color_picker :: (r: Rect, input_and_output_color_rgb: *Vector3, theme: *Color_Picker_Theme = null, identifier: s64 = 0, loc := #caller_location) -> (applied: bool) {
    if !theme  theme = *default_panel_theme.color_picker_theme;

    ipad_x := floor(r.w * theme.horizontal_padding + .5);
    ipad_y := floor(r.w * theme.vertical_padding   + .5);

    top, non_top           := cut_top(r, ipad_y);
    left_margin, remainder := cut_left(non_top, ipad_x);
    right_margin, middle   := cut_right(remainder, ipad_x);

    istashed_color_width := floor(r.w * theme.stashed_color_width + .5);    
    stashed_color_area, left2 := cut_right(middle, istashed_color_width);

    junk, circle_plus_extra := cut_right(left2, floor(r.w * theme.margin_between_color_input_and_stashed_colors + .5));

    circle_area_width  := circle_plus_extra.w;
    circle_area_height := circle_area_width;
    
    circle_area, junk2 := cut_top(circle_plus_extra, circle_area_height);

    junk3, controls_area := cut_top(middle, circle_area_height + ipad_y);
    
    {
        background := *theme.background;
        // Draw the background.
        draw_procs.set_shader_for_color(true);
        rounded_rectangle(r, background.shape, background.color, background.frame_color);
    }

    hash   := get_hash(loc, identifier);
    state, created := find_or_create_state(*table_color_picker, hash);

    set_overall_text_input_owner(state);  // So we can stop using the text input when a number field, with a different state structure, uses it. This is a dumb hack that can go away later when we have global organization.
    defer unset_overall_text_input_owner(state);
    
    circle_r0 := circle_area.w * (theme.inner_circle_diameter) * .5;
    circle_r1 := circle_area.w * (theme.outer_circle_diameter) * .5;
    
    if created {
        state.original_rgb_color = << input_and_output_color_rgb;
        set_current_color_rgb(state, theme, state.original_rgb_color);

        for theme.initial_stashed_colors  array_add(*state.stashed_colors, it);
    }
    
    status := get_status_flags(circle_area);
/*
    if (status & .OVER) && (mouse_button_right_state & .START) {
        state.color_pick_mode += xx 1;
        if state.color_pick_mode > xx enum_highest_value(Color_Pick_Mode)  state.color_pick_mode = xx 0;
    }
*/

    dt := current_dt;
    update_animation_values(state, dt); // Note: We could have faster responsiveness if we do a separate update then draw cycle, or if we do special bumping of variables when e.g. button presses happen...
    
    if state.color_pick_mode == {
      case .HSV_CIRCLE;
        draw_hsv_circle (circle_area, theme, state, circle_r0, circle_r1);
      case .HSV_SLIDERS;
        draw_hsv_sliders(circle_area, theme, state);
      case .RGB_SLIDERS;
        draw_rgb_sliders(circle_area, theme, state);
      case .TYPE_INS;
        draw_type_ins   (circle_area, theme, state);
    }

    //
    // Draw output swatches...
    // 
    ypad := 0.0;  // @theme padding

    button_height := controls_area.h * .2;  // @Theme: Hardcoded
    buttons_area, controls_lower := cut_top(controls_area, controls_area.h * .2);  // @Theme: Hardcoded
    
    swatch_y0 := buttons_area.y;
    applied := false;  // We will return this.
    
    {
        //bottom_button_width := (my_width - 4 * cp_xpad) / 3;
        bottom_button_width := (buttons_area.w - 3 * ipad_x) / 2;

        x0a := buttons_area.x;
        x0b := x0a + bottom_button_width;
        //x1a := x0b + cp_xpad;
        //x1b := x1a + iswatch_width;
        //x2a := x1b + cp_xpad;
        x2a := x0b + ipad_x;
        x2b := x2a + bottom_button_width;

        original, original_over, original_down, original_text := get_color_watch_colors(theme, state.original_rgb_color);
        current,  current_over,  current_down,  current_text  := get_color_watch_colors(theme, state.current_rgb_color);

        revert_theme := theme.apply_and_revert_button_theme;
        revert_theme.surface_color         = original;
        revert_theme.surface_color_over    = original_over;
        revert_theme.surface_color_down    = original_down;
        revert_theme.text_color            = original_text;
        
        apply_theme := theme.apply_and_revert_button_theme;
        apply_theme.surface_color          = current;
        apply_theme.surface_color_over     = current_over;
        apply_theme.surface_color_down     = current_over;
        apply_theme.text_color             = current_text;

        revert_area := get_rect(x0a, swatch_y0, bottom_button_width, button_height);
        sub_hash := get_hash(#location(), 0);
        revert_hash := combine_hashes(hash, sub_hash);
        if button(revert_area, theme.revert_string, *revert_theme, xx sub_hash, loc) {
            set_current_color_rgb(state, theme, state.original_rgb_color);
//            transfer_color_to_selection(panel);
        }

        sub_hash = get_hash(#location(), 0);
        revert_hash = combine_hashes(hash, sub_hash);

        apply_area := revert_area;
        apply_area.x += revert_area.w * 1.1; // @Theme
        if button(apply_area, theme.apply_string, *apply_theme, xx sub_hash, loc) {
            state.original_rgb_color      = state.current_rgb_color;
            << input_and_output_color_rgb = state.current_rgb_color;

            applied = true;
        }

        stash_theme := *theme.stash_button_theme;
        stash_area := cut_top(stashed_color_area, button_height);
        stash_area.y = apply_area.y;

        sub_hash = get_hash(#location(), 0);
        revert_hash = combine_hashes(hash, sub_hash);
        pressed_stash, state_stash := button(stash_area, "", stash_theme, xx sub_hash, loc);
        if pressed_stash {
            stash_color(state, state.current_rgb_color);
        }
        
        {
            triangle_margin := stash_area.w * 0.25;
            p0, p1, p2, p3 := get_quad(stash_area);
            p4 := to_vec3(lerp(p2, p3, .5));
            p4.y -= triangle_margin;
            p5 := to_vec3(p0);
            p5.x += triangle_margin;
            p5.y += triangle_margin;
            p6 := to_vec3(p1);
            p6.x -= triangle_margin;
            p6.y += triangle_margin;

            draw_arrow(state_stash, p4, p5, p6, stash_theme);
        }
    }

    
    sa := stashed_color_area;
    {
        //
        // Draw stashed colors.
        //

        stash_y1 := sa.y + sa.h;
        stash_y0 := circle_area.y;

        dy := stash_y1 - stash_y0;
        button_occupancy_ratio := 0.9;
        margin := floor(dy * (1 - button_occupancy_ratio) / cast(float)(MAX_STASHED_COLORS - 1) + 0.5);
        button_size_y := floor((dy * button_occupancy_ratio) / MAX_STASHED_COLORS + 0.5);

        region_x0 := sa.x;
        region_width := sa.w;
        
        button_width := sa.w;
        button_x0 := region_x0 + (region_width - button_width) * .5;
        button_x1 := button_x0 + button_width;
        
        draw_procs.set_shader_for_color(true);
        
        top_y := stash_y1;
        alpha := 1.0;
        shape := theme.stashed_colors_shape;
        for state.stashed_colors {
            x0 := button_x0;
            y0 := top_y - button_size_y;
            x1 := button_x1;
            y1 := top_y;

            can_see := true;  // @Incomplete

            color_rect := get_rect(x0, y0, x1-x0, y1-y0);
            color_status := get_status_flags(color_rect);
            if can_see && (color_status & .OVER) {
                m := margin;
                
                backing_rect := expand(color_rect, margin);
                color := v4(.5, .1, .1, 1);  // @Incomplete @Theme
                rounded_rectangle(backing_rect, shape, color, whiten(color, .5)); // @Theme

                if mouse_button_left_state & .START {
                    set_current_color_rgb(state, theme, it);
                    // @Incomplete note_color_changes(panel, true);
                }
            }
            
            c := v4(it.x, it.y, it.z, alpha);
            {
                h, s, v := rgb_to_hsv(it.x, it.y, it.z);
                if v > .5 {
                    v = .35;
                } else {
                    v = .65;
                }

                Clamp(*v, 0, 1);
                r, g, b := hsv_to_rgb(h, s, v);
                frame_color_rgb := v4(r, g, b, alpha);
                
                rounded_rectangle(color_rect, shape, c, frame_color_rgb); // @Theme
            }
            
            top_y -= button_size_y;
            top_y -= margin;
        }
    }

    vpad := button_height * .7;
    _junk, mode_switch_area := cut_top(controls_lower, vpad);
    draw_mode_switch_buttons(state, theme, hash, loc, mode_switch_area);
    return applied;
}

set_current_color_hsv :: (state: *Color_Picker_State, hsv: Vector3, update_zoom_hue := true) {
    state.current_hsv_color = hsv;

    theta := hsv.x * (TAU / 360);
    state.ring_point = v2(cos(theta), sin(theta));

    if update_zoom_hue state.zoom_hue_center = hsv.x;
}

set_current_color_rgb :: (state: *Color_Picker_State, theme: *Color_Picker_Theme, rgb: Vector3, update_hsv := true, maintain_h := FLOAT32_INFINITY, update_disc_point := true) {
    state.current_rgb_color = rgb;

    if update_hsv {
        hsv: Vector3 = ---;
        hsv.x, hsv.y, hsv.z = rgb_to_hsv(rgb.x, rgb.y, rgb.z);

        // Wrap hsv.x into the range desired by theme.
        while hsv.x < theme.slider_hue_min  hsv.x += 360;
        //    while hsv.x > theme.slider_hue_max  hsv.x -= 360;

        // Prefer the lower value on the slider, if there's more than 360 degrees...!
        // The max check above is redundant with this I guess, so it's commented out.
        while hsv.x - theme.slider_hue_min > 360  hsv.x -= 360;

        if maintain_h != FLOAT32_INFINITY {
            // If we drag onto black or white, maintain continuity
            // in saturation and value, and just poke the lightness,
            // so that as you drag around you don't lose state.
            // This is just here because set_current_color_rgb does the hsv computation;
            // if we farmed that computation out to somewhere else, maybe the check
            // would go there.
            hsv.x = maintain_h;
        }
        
        set_current_color_hsv(state, hsv);
    }

    if update_disc_point {
        // We provide the option to not update the disc point, so that
        // while the user is actually moving the disc point around, we let them
        // go wherever they want around the circumference; we don't want to 
        // introduce numerical error by recomputing it, and we also don't want to
        // snap to the edges of arcs (to fix singularities) while the user is
        // freely moving.
        state.disc_point = backsolve_disc_point_from_rgb(state, rgb);
    }
    
    stop_grabbing_text_input(state);  // Don't reflect incorrect values that may be in the text field if the user clicks on a color, etc.
}

backsolve_disc_point_from_rgb :: (state: *Color_Picker_State, rgb: Vector3) -> Vector2 {
    // We need to put the disc point in the right place for a given hsv color!

    h, s, v := rgb_to_hsv(rgb.x, rgb.y, rgb.z);
    point := backsolve_disc_point_from_hsv(state, h, s, v);
    return point;
}

EPSILON :: 0.0001;
backsolve_disc_point_from_hsv_warp :: (h: float, s: float, v: float) -> Vector2 {
    // Find the full radial vector out to the square.
    x := s;
    y := v;
    if x < .5 x = -1;
    else x = 1;

    if y < .5 y = -1;
    else y = 1;

    len_total := sqrt(x*x + y*y);
    if len_total < EPSILON return .{0, 0};

    p := v2((s*2-1)/len_total, (v*2-1)/len_total);
    return p;
}

backsolve_disc_point_from_hsv :: (state: *Color_Picker_State, h: float, s: float, v: float) -> Vector2 {
    if state.circle_picker_in_warped_mode {
        return backsolve_disc_point_from_hsv_warp(h, s, v);
    }
    
    // Some colors are not represented on the current disc!
    // To push them into disc space, we add an epsilon for now, which is kind of gross.
    // This doesn't affect the stored color though (unless you click on the disc, which
    // would anyway only give you something that is inside disc gamut!)

    if s < EPSILON {
        if v == 0  return .{0, -1};                 // Bottom middle for black.
        if v == 1  return unit_vector(v2(-1, +1));  // Upper-left corner for white.

        s += EPSILON;
    }
    
    if s > 1 - EPSILON {
        if v == 0  return .{0, -1};                 // Bottom middle for black.
        if v == 1  return unit_vector(v2(+1, +1));  // Upper-right corner for saturated color.

        s -= EPSILON;
    }

    if v < EPSILON      v = EPSILON;
    if v > 1 - EPSILON  v = 1 - EPSILON;
    
    
    // s := sin(tx * TAU * .25);
    // tx * TAU * .25 = asin(s);
    // tx = asin(s) * 4 / TAU;

    Clamp(*s, 0, 1);
    tx := asin(s) * (4.0 / TAU);
    // state.disc_point.x = tx;

    Clamp(*v, 0, 1);
    ty := asin(v) * (4.0 / TAU);

    alpha := 4 * (tx - .5) * (tx - .5);
    beta  := 4 * (ty - .5) * (ty - .5);

    one_minus_ab := 1 - alpha*beta;
    if one_minus_ab <= 0 {   // @Cleanup: These all should be covered by the cases that happen on entry, but leaving it here just in case ... !
        if v < .5  return .{0, -1};  // Bottom middle for black.
        if s < .5  return unit_vector(v2(-1, -1));  // Upper-left corner for white.
        return unit_vector(v2(+1, +1));  // Upper-right corner for saturated color.
    }
    
    ux_squared := (alpha - alpha*beta) / one_minus_ab;

    Clamp(*ux_squared, 0, 1);
    ux := sqrt(ux_squared);
    
    uy := (ty - .5) * 2 * sqrt(1 - ux_squared);
    // state.disc_point.y = ty;

    // @Hack: We lose the sign of ux in all this math, which means
    // it can be simplified / done better? But we reconstruct it just
    // because we know which side it's on due to s.

    if tx < .5  ux = -ux;
    
    // @Incomplete: toggled_s_t, toggled_v_t need to be handled.

    return v2(ux, uy);
}

/* @Incomplete
set_original_color_rgb :: (using panel: *Color_Panel, rgb: Vector3) {
    set_current_color_rgb(panel, rgb);
    original_rgb_color = current_rgb_color;
}
*/

hsl_to_argb :: (hsl: Vector3) -> Vector4 {
    r, g, b := hsl_to_rgb(hsl.x, hsl.y, hsl.z);
    return make_vector4(r, g, b, 1);
}

hsv_to_argb :: (hsv: Vector3) -> Vector4 {
    r, g, b := hsv_to_rgb(hsv.x, hsv.y, hsv.z);
    return make_vector4(r, g, b, 1);
}

#scope_file

Slider_Index :: enum s32 {
    HUE        :: 0;
    HUE_ZOOMED :: 1;
    SATURATION :: 2;
    LIGHTNESS  :: 3;
    RED        :: 4;
    GREEN      :: 5;
    BLUE       :: 6;
}

color_slider :: (r: Rect, index: Slider_Index, input_color: Vector3, value: *float, dragging: *bool, dragging_t: float, alpha: float, theme: *Color_Picker_Theme, state: *Color_Picker_State) -> changed: bool {
    // input_color is hsv, rgb, or whatever we want to use for that particular slider.
    draw_procs.set_shader_for_color(true);

    NUM_SEGMENTS :: 36; // Divisible by 6 so that we hit the extrema of the H function.
    last_p0, last_p1: Vector2 = ---;
    _last_color: Vector4 = ---;

    status := get_status_flags(r);
    if status & .OVER {
        if mouse_button_left_state & .START {
            << dragging = true;
        }
    }

    left_\arrow_tip: Vector3 = ---;
    right_arrow_tip: Vector3 = ---;
    arrow_color:     Vector4 = ---;

    changed := false;

    if r.h {
        // ix, iy := current_mouse_x, current_mouse_y;
        drag_y := mouse_y_float;

        t := (drag_y - r.y) / r.h;
        Clamp(*t, 0, 1);

        pip_t := << value;
        dx := r.w * .1;
        dy := dx;
        k := 0.5;

        k   = lerp(k, 1, dragging_t);
        dx *= lerp(1, 2, dragging_t);
        dy *= lerp(1, 2, dragging_t);

        if <<dragging  {
            pip_t = t;

            // Side effects:
            << value = t;
            changed = true;
        }        

        pa := v3(r.x,       r.y + pip_t * r.h, 0);
        pb := v3(r.x + r.w, r.y + pip_t * r.h, 0);
        
        color := v4(k, k, k, 1);
        arrow_color = color;
        
        p0 := pa;
        p1 := p0 + v3(-dx, dy * .5, 0);
        p2 := p1 + v3(0, -dy, 0);

        p3 := pb;
        p4 := p3 + v3(dx, dy * .5, 0);
        p5 := p4 + v3(0, -dy, 0);

        draw_procs.immediate_triangle(p0, p1, p2, color, color, color);
        draw_procs.immediate_triangle(p3, p4, p5, color, color, color);

        left_\arrow_tip = p0;
        right_arrow_tip = p3;
    }

    for i: 0..NUM_SEGMENTS - 1 {
        t := i / cast(float)(NUM_SEGMENTS - 1);

        p0 := v2(r.x,       r.y + t * r.h);
        p1 := v2(r.x + r.w, r.y + t * r.h);

        r, g, b: float;
        if index == {
          case .HUE;
            h := lerp(theme.slider_hue_min, theme.slider_hue_max, t);
            r, g, b = hsv_to_rgb(h, 1, 1);
          case .HUE_ZOOMED;
            dhue := theme.hue_range_in_zoomed_slider * .5;
            low  := state.zoom_hue_center - dhue;
            high := state.zoom_hue_center + dhue;
            h := lerp(low, high, t);
            r, g, b = hsv_to_rgb(h, 1, 1);
          case .SATURATION;
            r, g, b = hsv_to_rgb(input_color.x, t, .5);
          case .LIGHTNESS;
            r, g, b = hsv_to_rgb(input_color.x, input_color.y, t);
          case .RED;
            r = t;
            g = input_color.y;
            b = input_color.z;
          case .GREEN;
            r = input_color.x;
            g = t;
            b = input_color.z;
          case .BLUE;
            r = input_color.x;
            g = input_color.y;
            b = t;
        }
        
        color   := v4(r, g, b, alpha);
        
        if (i != 0) {
            draw_procs.immediate_triangle(to_vec3(last_p0), to_vec3(last_p1), to_vec3(p1), _last_color, _last_color, color);
            draw_procs.immediate_triangle(to_vec3(last_p0), to_vec3(p1), to_vec3(p0), _last_color, color, color);
        }

        last_p0 = p0;
        last_p1 = p1;
        _last_color = color;
    }

    if index == 0 {
        //
        // Draw calipers...?!
        //

        hue_range := (theme.slider_hue_max - theme.slider_hue_min);
        if hue_range >= 0 {
            caliper_range    := theme.hue_range_in_zoomed_slider;
            caliper_distance := (caliper_range / hue_range) * r.h * .5;

            hue_denom := theme.slider_hue_max - theme.slider_hue_min;
            if !hue_denom hue_denom = 1;
            zoom_hue_y := r.y + ((state.zoom_hue_center - theme.slider_hue_min) / hue_denom) * r.h;
            yy := floor(zoom_hue_y + .5);  // Round to integers since these are thin and look goofy otherwise.
            h := r.w * .025;  // @Theme ... the thickness of the caliper bar.

            y_top    := yy + caliper_distance;
            y_bottom := yy - caliper_distance;

            alpha_top    := 1.0;
            alpha_bottom := 1.0;
            fade_margin  := h*8;

            fade_zone_top    := r.y + r.h - fade_margin;
            fade_zone_bottom := r.y + fade_margin;
            
            h_denom := fade_margin;
            if !h_denom  h_denom = 1;
            excess_top := y_top - fade_zone_top;
            if excess_top >= 0 {
                alpha_top = 1 - (excess_top / h_denom);
                Clamp(*alpha_top, 0, 1);
            }

            excess_bottom := fade_zone_bottom - y_bottom;
            if excess_bottom >= 0 {
                alpha_bottom = 1 - (excess_bottom / h_denom);
                Clamp(*alpha_bottom, 0, 1);
            }
            
            color_inactive := Vector4.{.05, .05, .05, 1};  // @Theme
            color_active   := Vector4.{1, 1, 1, 1};  // @Theme
            color := lerp(color_inactive, color_active, state.dragging_in_h_t);

            q0 := left_arrow_tip;
            q0.y = y_top;

            q1 := right_arrow_tip;
            q1.y = y_top;

            q2 := q1 + v3(0, h, 0);
            q3 := q0 + v3(0, h, 0);

            ct := color;  // "color top";
            ct.w = alpha_top;
            draw_procs.immediate_triangle(q0, q1, q2, ct, ct, ct);
            draw_procs.immediate_triangle(q0, q2, q3, ct, ct, ct);


            r0 := left_arrow_tip;
            r0.y = y_bottom;

            r1 := right_arrow_tip;
            r1.y = y_bottom;

            r2 := r1 + v3(0, -h, 0);
            r3 := r0 + v3(0, -h, 0);

            cb := color;  // "color bottom";
            cb.w = alpha_bottom;
            draw_procs.immediate_triangle(r0, r1, r2, cb, cb, cb);
            draw_procs.immediate_triangle(r0, r2, r3, cb, cb, cb);
        }
    }

    draw_procs.immediate_flush();

    
    focus := has_focus(r);
    down  := focus && (mouse_button_left_state & .DOWN);
    
    // Don't disable dragging until after we draw ... so we get at least
    // one update if we do an intra-frame click.
    if <<dragging {
        if !down {
            << dragging = false;
        }
    }

    return changed;
}


color_rectangle :: (r: Rect, input_color: Vector3, value_x: *float, value_y: *float, dragging: *bool, dragging_t: float, alpha: float, theme: *Color_Picker_Theme, state: *Color_Picker_State) -> changed: bool {
    // input_color is hsv, rgb, or whatever we want to use for that particular slider.
    draw_procs.set_shader_for_color(true);

    status := get_status_flags(r);
    if status & .OVER {
        if mouse_button_left_state & .START {
            << dragging = true;
        }
    }

    NUM_SEGMENTS :: 36; // Divisible by 6 so that we hit the extrema of the H function.
    {
        // Draw a square now!
        r22 := sqrt(2.0) * .5;  // @Speed!

        STRIPS :: 20;
        dt := 1 / cast(float)STRIPS;
        x_min := r.x;
        x_max := r.x + r.w;
        y_min := r.y;
        y_max := r.y + r.h;

        h := input_color.x;
        for j: 0..STRIPS-1 {
            y0 := lerp(y_min, y_max, j*dt);
            y1 := lerp(y_min, y_max, (j+1)*dt);

            for i: 0..STRIPS-1 {
                x0 := lerp(x_min, x_max, i*dt);
                x1 := lerp(x_min, x_max, (i+1)*dt);

                // s0..3 are circle-stretched points, without the center added.
                q0 := v3(x0, y0, 0);  
                q1 := v3(x1, y0, 0);  
                q2 := v3(x1, y1, 0);  
                q3 := v3(x0, y1, 0);  

                s0 := (i*dt);
                s1 := ((i+1)*dt);
                v0 := (j*dt);
                v1 := ((j+1)*dt);
                
                hsv0 := v3(h, s0, v0);
                hsv1 := v3(h, s1, v0);
                hsv2 := v3(h, s1, v1);
                hsv3 := v3(h, s0, v1);

                c0 := hsv_to_argb(hsv0);
                c1 := hsv_to_argb(hsv1);
                c2 := hsv_to_argb(hsv2);
                c3 := hsv_to_argb(hsv3);
                
                draw_procs.immediate_triangle(q0, q1, q2, c0, c1, c2);
                draw_procs.immediate_triangle(q0, q2, q3, c0, c2, c3);
            }
        }
    }

    changed := false;
    rectangle_point := v2(state.current_hsv_color.y, state.current_hsv_color.z);

    {
        w := r.w;
        h := r.h;
        if w && h && <<dragging {
            rectangle_point.x = (mouse_x_float - r.x) / w;
            rectangle_point.y = (mouse_y_float - r.y) / w;

            Clamp(*rectangle_point.x, 0, 1);
            Clamp(*rectangle_point.y, 0, 1);
            
            << value_x = rectangle_point.x;
            << value_y = rectangle_point.y;
            changed = true;
        }
    }

    {
        pos := rectangle_point * r.w + v2(r.x, r.y);
        draw_2d_dragging_marker(pos, r.w*.2, state.dragging_in_hsv_rectangle_t);
    }
    
    focus := has_focus(r);
    down  := focus && (mouse_button_left_state & .DOWN);
    
    // Don't disable dragging until after we draw ... so we get at least
    // one update if we do an intra-frame click.
    if <<dragging {
        if !down {
            << dragging = false;
        }
    }

    return changed;
}

draw_hsv_sliders :: (area: Rect, theme: *Color_Picker_Theme, state: *Color_Picker_State) {
    w := area.w;
    bar_width := w / 7;

    between_width := bar_width * .9;
    left_margin := 0.5 * (w - (4 * bar_width + 2.25 * between_width));

    if state.hsv_picker_in_rectangle_mode {
        bar_width *= .7;
        between_width *= .7;
        left_margin = 0;
    }
    
    hsv_color := state.current_hsv_color;
    
    bar_x := area.x + left_margin;
    bar_y := area.y + w * .03;
    bar_height := w * .97;

    bar_x         = floor(bar_x + .5);
    bar_y         = floor(bar_y + .5);
    bar_width     = floor(bar_width + .5);
    bar_height    = floor(bar_height + .5);
    between_width = floor(between_width + .5);
    left_margin   = floor(left_margin + .5);
    
    alpha := 1.0;

    hue_before_modifications := hsv_color.x;

    area_status := get_status_flags(area);
    if (area_status & .OVER) && (mouse_button_right_state & .START) {
        state.hsv_picker_in_rectangle_mode = !state.hsv_picker_in_rectangle_mode;
    }

    //
    // extra_wrapped_hue is here because, when we have positioned the hue calipers
    // so that the zoomed area crosses past the primary hue bar (index 0)'s range,
    // we could use the zoom bar to move the primary hue cursor outside the range.
    // When this happens, rather than drawing the arrows out in space, we wrap
    // them down to the earlier repeat position. But we don't want to wrap the
    // actual current hue value, because that would affect the zoom bar probably.
    // (Although maybe that approach is fine, since it is the kind of thing video
    // games do when the asteroid spaceship crosses the screen boundary or whatever,
    // so maybe it wouldn't be disruptive, but I am a bit too tired to think about
    // that right now, so this is how we are doing it.  -jblow, 24 June 2021.
    //
    extra_wrapped_hue := hue_before_modifications; 
    while extra_wrapped_hue < theme.slider_hue_min  extra_wrapped_hue += 360;
    while extra_wrapped_hue > theme.slider_hue_max  extra_wrapped_hue -= 360;

    hue_denom := theme.slider_hue_max - theme.slider_hue_min;
    if !hue_denom hue_denom = 1;
    h := (extra_wrapped_hue - theme.slider_hue_min) / hue_denom;
    r := get_rect(bar_x, bar_y, bar_width, bar_height);
    
    changed_unzoomed_hue := color_slider(r, .HUE, hsv_color, *h, *state.dragging_in_h, state.dragging_in_h_t, alpha, theme, state);
    changed_hsv := changed_unzoomed_hue;
    if changed_unzoomed_hue {
        hsv_color.x = lerp(theme.slider_hue_min, theme.slider_hue_max, h);
    }

    dhue := theme.hue_range_in_zoomed_slider * .5;
    hue_zoom_low  := state.zoom_hue_center - dhue;
    hue_zoom_high := state.zoom_hue_center + dhue;
    hue_zoom_denom := (hue_zoom_high - hue_zoom_low);
    if !hue_zoom_denom  hue_zoom_denom = 1;
    h_zoom := (hue_before_modifications - hue_zoom_low) / hue_zoom_denom;
    
    r.x += bar_width + between_width * .25;
    changed_zoomed_version := color_slider(r, .HUE_ZOOMED, hsv_color, *h_zoom, *state.dragging_in_h_zoom, state.dragging_in_h_zoom_t, alpha, theme, state);
    changed_hsv |= changed_zoomed_version;
    if changed_zoomed_version {
        hsv_color.x = lerp(hue_zoom_low, hue_zoom_high, h_zoom);
    }

    if state.hsv_picker_in_rectangle_mode {
        margin := between_width*.5;

        x0 := r.x + bar_width + margin;
        
        w := (area.x + area.w - x0);
        
        rectangle_area: Rect;
        rectangle_area.x = x0;
        rectangle_area.w = w;
        rectangle_area.h = w;
        rectangle_area.y = r.y + (r.h - w) * .5;

        changed_hsv |= color_rectangle(rectangle_area, hsv_color, *hsv_color.y, *hsv_color.z, *state.dragging_in_hsv_rectangle, state.dragging_in_hsv_rectangle_t, alpha, theme, state);
    } else {
        r.x += bar_width + between_width;
        changed_hsv |= color_slider(r, .SATURATION, hsv_color, *hsv_color.y, *state.dragging_in_s, state.dragging_in_s_t, alpha, theme, state);
        
        r.x += bar_width + between_width;
        changed_hsv |= color_slider(r, .LIGHTNESS, hsv_color, *hsv_color.z, *state.dragging_in_l, state.dragging_in_l_t, alpha, theme, state);
    }
    
    if changed_hsv {
        // We have to manually set current_color_rgb for the rgb_color to update. Sigh!
        set_current_color_hsv(state, hsv_color, changed_unzoomed_hue);
        r, g, b := hsv_to_rgb(hsv_color.x, hsv_color.y, hsv_color.z);
        set_current_color_rgb(state, theme, v3(r, g, b), update_hsv = false);
    }
}

draw_rgb_sliders :: (area: Rect, theme: *Color_Picker_Theme, state: *Color_Picker_State) {
    // @Copypasta from draw_hsv_sliders; maybe we could recombine them.
    
    w := area.w;
    bar_width := w / 7;
    between_width := bar_width * .9;
    left_margin := 0.5 * (w - (3 * bar_width + 2 * between_width));
    
    bar_x := area.x + left_margin;
    bar_y := area.y + w * .03;
    bar_height := w * .97;

    bar_x         = floor(bar_x + .5);
    bar_y         = floor(bar_y + .5);
    bar_width     = floor(bar_width + .5);
    bar_height    = floor(bar_height + .5);
    between_width = floor(between_width + .5);
    left_margin   = floor(left_margin + .5);
    
    alpha := 1.0;

    rgb := state.current_rgb_color;
    r := get_rect(bar_x, bar_y, bar_width, bar_height);
    
    changed_r   := color_slider(r, .RED,   rgb, *rgb.x, *state.dragging_in_r, state.dragging_in_r_t, alpha, theme, state);
    changed_rgb := changed_r;

    r.x += bar_width + between_width;
    changed_rgb |= color_slider(r, .GREEN, rgb, *rgb.y, *state.dragging_in_g, state.dragging_in_g_t, alpha, theme, state);
    
    r.x += bar_width + between_width;
    changed_rgb |= color_slider(r, .BLUE,  rgb, *rgb.z, *state.dragging_in_b, state.dragging_in_b_t, alpha, theme, state);

    if changed_rgb {
        set_current_color_rgb(state, theme, rgb);
    }
}

draw_type_ins :: (area: Rect, theme: *Color_Picker_Theme, state: *Color_Picker_State) {
    text_top_y := area.y + area.h;
    button_height := area.h * .2;  // @Theme: Hardcoded

    NUM_COLUMNS :: 2;
    middle_margin := area.w * .1;
    column_width := (area.w - middle_margin) / NUM_COLUMNS;
    column1, rhs := cut_left(area, column_width);
    middle, column2 := cut_left(rhs, middle_margin);
    
    label_theme := theme.type_ins_label_theme;
    label_theme.alignment = .Right;  // @Theme
    input_theme := theme.type_ins_input_theme;
    input_theme.alignment = .Left;  // @Theme
    
    if !label_theme.font {
        // If they didn't supply a font in the label theme,
        // try to auto-pick a size that fits with the formatting
        // that we want.
        //
        // Heuristic: We want our font to have about 4 character heights fit in the horizontal space,
        // which would be more than 4 characters horizontally for Arabic
        // numerals and Latin text labels. Really we want to say
        // "at what font size would the following text fit into this space,"
        // but we don't have that functionality right now; maybe we should
        // add it.
        //
        // This kind of thing tends to vary a lot from font to font, so it is hard
        // to do something generic here... except, we can vet that whatever default
        // font we pack in behaves reasonably here.

        NUM_CHARACTER_HEIGHTS :: 4.5;
        font := get_default_font_at_size(column_width / NUM_CHARACTER_HEIGHTS);
        label_theme.font = font;
        input_theme.font = font;
    }
    
    text: string;
    
    line_height := cast(float)label_theme.font.character_height;
    top_pad := line_height; // @Theme

    label_rect, input_rect: Rect = ---;
    LABEL_RATIO :: 0.18;
    
    //
    // RGB readout.
    //
    c := state.current_rgb_color;
    ir := to_u8(c.x);  // The number_inputs can change c.*, so, compute ir, ig, ib first.
    ig := to_u8(c.y);
    ib := to_u8(c.z);
    hsv_color := state.current_hsv_color;
    
    r := cut_top(column1, line_height);
    r.y -= top_pad;

    label_rect, input_rect = cut_left(r, r.w * LABEL_RATIO);
    text = tprint("%", formatFloat(c.x, trailing_width=3, zero_removal=.NO));
    label(label_rect, "R",  *label_theme);
    changed_r := number_input(input_rect, text, *c.x, 0, 1, *input_theme);
    r.y -= line_height;

    label_rect, input_rect = cut_left(r, r.w * LABEL_RATIO);
    text = tprint("%", formatFloat(c.y, trailing_width=3, zero_removal=.NO));
    label(label_rect, "G",  *label_theme);
    changed_g := number_input(input_rect, text, *c.y, 0, 1, *input_theme);
    r.y -= line_height;

    label_rect, input_rect = cut_left(r, r.w * LABEL_RATIO);
    text = tprint("%", formatFloat(c.z, trailing_width=3, zero_removal=.NO));
    label(label_rect, "B",  *label_theme);
    changed_b := number_input(input_rect, text, *c.z, 0, 1, *input_theme);
    r.y -= line_height;

    //
    // Do another RGB that goes from 0-255.
    // 
    r.y -= line_height;  // Extra blank line.

    label_rect, input_rect = cut_left(r, r.w * LABEL_RATIO);
    text = tprint("%", ir);
    label(label_rect, "R",  *label_theme);
    changed_ir := number_input(input_rect, text, *ir, 0, 255, *input_theme);
    r.y -= line_height;

    label_rect, input_rect = cut_left(r, r.w * LABEL_RATIO);
    text = tprint("%", ig);
    label(label_rect, "G",  *label_theme);
    changed_ig := number_input(input_rect, text, *ig, 0, 255, *input_theme);
    r.y -= line_height;

    label_rect, input_rect = cut_left(r, r.w * LABEL_RATIO);
    text = tprint("%", ib);
    label(label_rect, "B",  *label_theme);
    changed_ib := number_input(input_rect, text, *ib, 0, 255, *input_theme);
    r.y -= line_height;

    
    //
    // HSV readout.
    //

    // In the rest of the code, we let the value of hsv_color.x go negative,
    // because we want to remember where the cursor was
    // if it wraps off the bottom or top due to zoom, etc ... we do not want it
    // to pop! (Recall that, at least right now, the hue slider goes more than
    // 360 degrees, so we want to remember where on that slider you were!)
    
    printed_h := hsv_color.x;
    while printed_h < 0    printed_h += 360;
    while printed_h > 360  printed_h -= 360;

    
    r = cut_top(column2, line_height);
    r.y -= top_pad;

    label_rect, input_rect = cut_left(r, r.w * LABEL_RATIO);
    text = tprint("%", formatFloat(printed_h, trailing_width=1, zero_removal=.ONE_ZERO_AFTER_DECIMAL));
    while text && (text[text.count-1] == #char " ") text.count -= 1;  // Chop trailing spaces because trailing_width means format spacing as well as number of zeroes... hmm maybe we should rethink that.
    label(label_rect, "H",  *label_theme);
    changed_h := number_input(input_rect, text, *hsv_color.x, -360, 720, *input_theme);
    r.y -= line_height;

    label_rect, input_rect = cut_left(r, r.w * LABEL_RATIO);
    text = tprint("%", formatFloat(hsv_color.y * 100, trailing_width=1, zero_removal=.ONE_ZERO_AFTER_DECIMAL));
    label(label_rect, "S",  *label_theme);
    changed_s := number_input(input_rect, text, *hsv_color.y, 0, 100, *input_theme);
    r.y -= line_height;

    label_rect, input_rect = cut_left(r, r.w * LABEL_RATIO);
    text = tprint("%", formatFloat(hsv_color.z * 100, trailing_width=1, zero_removal=.ONE_ZERO_AFTER_DECIMAL));
    label(label_rect, "V",  *label_theme);
    changed_l := number_input(input_rect, text, *hsv_color.z, 0, 100, *input_theme);
    r.y -= line_height;

    changed_hsv := (changed_h | changed_s | changed_l);

    if changed_r | changed_g | changed_b {
        set_current_color_rgb(state, theme, c);
    }
    
    if changed_ir | changed_ig | changed_ib {
        rgb := state.current_rgb_color;
        if changed_ir  rgb.x = (ir / 255.0);
        if changed_ig  rgb.y = (ig / 255.0);
        if changed_ib  rgb.z = (ib / 255.0);

        set_current_color_rgb(state, theme, rgb);
    }

    if changed_h | changed_s | changed_l {
        // We multiplied by 100 to give percentages, so divide by 100
        // to convert back if they changed. Kind of a weird hack, but okay.
        hsv := hsv_color;
        if changed_s  hsv_color.y *= .01;
        if changed_l  hsv_color.z *= .01;
        r, g, b := hsv_to_rgb(hsv.x, hsv.y, hsv.z);
        set_current_color_rgb(state, theme, v3(r, g, b));
    }

    r.y -= line_height * 2;
    label_rect, input_rect = cut_left(r, r.w * LABEL_RATIO);
    hex := ((cast(u32) ir) << 16) | ((cast(u32) ig) << 8) | ib;
    text = tprint("%", formatInt(hex, base=16, minimum_digits=6));
    label(label_rect, "#",  *label_theme);
    changed_hex := number_input(input_rect, text, *hex, 0, 0xffffff, *input_theme, parse_proc=parse_hex);
    if changed_hex {
        r := ((hex & 0xff0000) >> 16) / 255.0;
        g := ((hex & 0x00ff00) >>  8) / 255.0;
        b :=  (hex & 0x0000ff)        / 255.0;
        set_current_color_rgb(state, theme, v3(r, g, b));
    }
    
    r.y -= line_height;
}

parse_hex :: (s: string) -> (u32, bool) {
    result, success := string_to_int(s, base=16);
    return clamp_to_another_integer_type(result, u32), true;
}


draw_hsv_circle :: (r: Rect, theme: *Color_Picker_Theme, state: *Color_Picker_State, circle_r0: float, circle_r1: float) {
    NUM_SEGMENTS :: 100;

    w  := circle_r1 * 2;
    r0 := circle_r0;
    r1 := circle_r1;

    center := make_vector2(r.x + r.w * 0.5, r.y + r.w * 0.5);

    status := get_status_flags(r);
    if (status & .OVER) && (mouse_button_right_state & .START) {
        state.circle_picker_in_warped_mode = !state.circle_picker_in_warped_mode;
        rgb := state.current_rgb_color;
        state.disc_point = backsolve_disc_point_from_rgb(state, rgb);
    }
    
    draw_procs.set_shader_for_color(true);

    {
        // In case the window resized, the rect changed, etc, refigure the ring point.

        p := unit_vector(state.ring_point) * (r0 + r1) * .5;
        state.ring_point = p;
    }
    
    update_ring_point(state, center, r0, r1);

    last_p0, last_p1: Vector2 = ---;
    last_color: Vector4 = ---;

    alpha := 1.0;

    for i: 0..NUM_SEGMENTS - 1 {
        t := i / cast(float)(NUM_SEGMENTS - 1);

        radians := TAU * t;
        degrees: = 360.0 * t;
        dir := v2(cos(radians), sin(radians));

        p0 := center + dir * r0;
        p1 := center + dir * r1;

        h := degrees;
        s := 1.0;
        v := 0.9;

        r, g, b := hsv_to_rgb(h, s, v);
        color   := v4(r, g, b, alpha);
        
        if (i != 0) {
            draw_procs.immediate_triangle(to_vec3(last_p0), to_vec3(last_p1), to_vec3(p1), last_color, last_color, color);
            draw_procs.immediate_triangle(to_vec3(last_p0), to_vec3(p1), to_vec3(p0), last_color, color, color);
        }

        last_p0 = p0;
        last_p1 = p1;
        last_color = color;
    }

    disc_r := circle_r0 * theme.inner_disc_radius;
    ir := 1.0;
    if disc_r ir = 1.0/disc_r;

    update_disc_point(state, center, disc_r);
    
    h := (360 / TAU) * atan2(state.ring_point.y, state.ring_point.x);
    if h < 0  h += 360;

    center3 := to_vec3(center);

    draw_circle_at :: (center: Vector2, r: float, N: s32, color: Vector4) {
        if !N return;
        
        dtheta := TAU / N;

        p0 := v3(center.x, center.y, 0);
        
        // @Speed: Factor apart the loop below to save the previous points.
        for i: 0..N-1 {
            theta0 := dtheta * i;
            theta1 := dtheta * (i+1);

            ct0 := cos(theta0);
            st0 := sin(theta0);
            ct1 := cos(theta1);
            st1 := sin(theta1);

            p1 := v3(center.x + ct0 * r, center.y + st0 * r, 0);
            p2 := v3(center.x + ct1 * r, center.y + st1 * r, 0);
        
            draw_procs.immediate_triangle(p0, p1, p2, color, color, color);
        }
    }
    
    if state.circle_picker_in_warped_mode {
        // Draw the mickey mouse ears.
        rgb_white     := Vector4.{1, 1, 1, 1};

        r, g, b := hsv_to_rgb(h, 1, 1);
        rgb_saturated := v4(r, g, b, 1);

        m_white, m_saturated, radius := get_mickey_mouse_ears();

        NUM_TRIANGLES :: 12;
        draw_circle_at(m_white     * disc_r + center, radius * disc_r, NUM_TRIANGLES, rgb_white);
        draw_circle_at(m_saturated * disc_r + center, radius * disc_r, NUM_TRIANGLES, rgb_saturated);
    }
    
    value_vector      := unit_vector(make_vector3(0, 1, 0));
    saturation_vector := unit_vector(make_vector3(1, -1, 0));
        
    {
        // Draw a square now!
        r22 := sqrt(2.0) * .5;  // @Speed!

        STRIPS :: 50;
        dt := 1 / cast(float)STRIPS;
        x_min := - r22 * disc_r;
        x_max := + r22 * disc_r;
        y_min := - r22 * disc_r;
        y_max := + r22 * disc_r;

        for j: 0..STRIPS-1 {
            y0 := lerp(y_min, y_max, j*dt);
            y1 := lerp(y_min, y_max, (j+1)*dt);

            for i: 0..STRIPS-1 {
                x0 := lerp(x_min, x_max, i*dt);
                x1 := lerp(x_min, x_max, (i+1)*dt);

                // s0..3 are circle-stretched points, without the center added.
                s0 := circle_stretch(x0, y0);
                s1 := circle_stretch(x1, y0);
                s2 := circle_stretch(x1, y1);
                s3 := circle_stretch(x0, y1);

                // @Speed: Factor out the ir.
                hsv0, hsv1, hsv2, hsv3: Vector3 = ---;
                if state.circle_picker_in_warped_mode {
                    hsv0 = make_hsv_warp_from_square_point(h, i*dt, j*dt);
                    hsv1 = make_hsv_warp_from_square_point(h, (i+1)*dt, j*dt);
                    hsv2 = make_hsv_warp_from_square_point(h, (i+1)*dt, (j+1)*dt);
                    hsv3 = make_hsv_warp_from_square_point(h, i*dt, (j+1)*dt);
                } else {
                    hsv0 = make_hsv(state, h, s0*ir);
                    hsv1 = make_hsv(state, h, s1*ir);
                    hsv2 = make_hsv(state, h, s2*ir);
                    hsv3 = make_hsv(state, h, s3*ir);
                }
                
                c0 := hsv_to_argb(hsv0);
                c1 := hsv_to_argb(hsv1);
                c2 := hsv_to_argb(hsv2);
                c3 := hsv_to_argb(hsv3);
                
                // q0..3 are the points we render. Just the circle points plus the center.
                q0 := s0 + center3;
                q1 := s1 + center3;
                q2 := s2 + center3;
                q3 := s3 + center3;
                
                draw_procs.immediate_triangle(q0, q1, q2, c0, c1, c2);
                draw_procs.immediate_triangle(q0, q2, q3, c0, c2, c3);
            }
        }
    }

    //
    // Update colors.
    {
        p := to_vec3(state.disc_point);
        hsv: Vector3;
        if state.circle_picker_in_warped_mode {
            hsv = make_hsv_warp_from_disc_point(h, p.x, p.y);
        } else {
            hsv = make_hsv(state, h, p);
        }
        
        r, g, b := hsv_to_rgb(hsv.x, hsv.y, hsv.z);
        set_current_color_rgb(state, theme, v3(r, g, b), maintain_h=h, update_disc_point=false);
    }

    draw_procs.immediate_flush();


    //
    // Draw the cursor for the ring point.
    //

    {
        dir   := unit_vector(state.ring_point);

        triangle_extension_distance: float;
        apex_height: float;
        triangle_border_width: float;
        border_color := v4(.05, .05, .05, .3); // @Theme
        triangle_color: Vector4;
        
        {
            triangle_scale := lerp(.7, 1, state.dragging_in_ring_t);
            k := lerp(.05, 1, state.dragging_in_ring_t);  // Used for foreground color.
            
            triangle_color = v4(k, k, k, 1);    // @Theme
            
            apex_height = circle_r1 * .12 * triangle_scale;  // @Theme
            base_halfwidth := apex_height * .6;  // @Theme
            
            triangle_border_width       = .25 * base_halfwidth;  // @Theme
            triangle_extension_distance = apex_height * lerp(.2, .45, state.dragging_in_ring_t);      // @Theme
            
            triangle_apex := center + (circle_r1 + triangle_extension_distance - apex_height) * dir;

            draw_bordered_triangle(triangle_apex, apex_height, base_halfwidth, triangle_border_width, dir, triangle_color, border_color);
        }
        
        rectangle_retraction_distance := triangle_extension_distance * .38; // @Theme
        rectangle_halfwidth := apex_height * .3; // @Theme
        rectangle_height    := apex_height * .35; // @Theme
        rectangle_border_width := triangle_border_width * .6; // @Theme
        rectangle_base := center + (circle_r0 - rectangle_retraction_distance) * dir;
        rectangle_apex := rectangle_base + rectangle_height * dir;

        {            
            strut := v2(-dir.y, dir.x);
            b := rectangle_halfwidth;
            p0 := rectangle_base - strut * b;
            p1 := rectangle_base + strut * b;
            p2 := p1 + dir * rectangle_height;
            p3 := p0 + dir * rectangle_height;

            bb := rectangle_border_width;
            bx := strut * bb;
            by := dir * bb;
            
            barycenter := (p0 + p2) * .5;
            q0 := p0 - bx - by;
            q1 := p1 + bx - by;
            q2 := p2 + bx + by;
            q3 := p3 - bx + by;

            inner := border_color;
            outer := border_color;
            outer.w = 0;
            
            // Quads around the rectangle, for a border shadow:
            draw_procs.immediate_triangle(to_vec3(p0), to_vec3(q0), to_vec3(q1), inner, outer, outer);
            draw_procs.immediate_triangle(to_vec3(p0), to_vec3(q1), to_vec3(p1), inner, outer, inner);

            draw_procs.immediate_triangle(to_vec3(p1), to_vec3(q1), to_vec3(q2), inner, outer, outer);
            draw_procs.immediate_triangle(to_vec3(p1), to_vec3(q2), to_vec3(p2), inner, outer, inner);

            draw_procs.immediate_triangle(to_vec3(p2), to_vec3(q2), to_vec3(q3), inner, outer, outer);
            draw_procs.immediate_triangle(to_vec3(p2), to_vec3(q3), to_vec3(p3), inner, outer, inner);

            draw_procs.immediate_triangle(to_vec3(p3), to_vec3(q3), to_vec3(q0), inner, outer, outer);
            draw_procs.immediate_triangle(to_vec3(p3), to_vec3(q0), to_vec3(p0), inner, outer, inner);

            // The actual rectangle:
            draw_procs.immediate_triangle(to_vec3(p0), to_vec3(p1), to_vec3(p2), triangle_color, triangle_color, triangle_color);
            draw_procs.immediate_triangle(to_vec3(p0), to_vec3(p2), to_vec3(p3), triangle_color, triangle_color, triangle_color);
        }
    }
    
    //
    // Draw the color marker for the disc point.
    //
    {
        w   := r.w * .15;
        pos := center + state.disc_point * disc_r;
            
        draw_2d_dragging_marker(pos, w, state.dragging_in_disc_t);
    }
}

draw_2d_dragging_marker :: (pos: Vector2, w: float, dragging_t: float) {
    j := lerp(1, .05, dragging_t);
    k := lerp(.05, 1, dragging_t);
    triangle_scale := lerp(.24, .35, dragging_t);
    
    color := v4(k, k, k, 1);    // @Theme
    border_color := v4(j, j, j, .3); // @Theme
    
    apex_height := w * .5 * triangle_scale;  // @Theme
    base_halfwidth := apex_height * .6;  // @Theme
    triangle_distance_from_center := w * .6 * triangle_scale; // @Theme
    
    border_width       := lerp(.7 * base_halfwidth, .45 * base_halfwidth, dragging_t);
    triangle_apex_N := pos + make_vector2(0, triangle_distance_from_center);
    triangle_apex_S := pos + make_vector2(0, -triangle_distance_from_center);
    triangle_apex_E := pos + make_vector2(triangle_distance_from_center, 0);
    triangle_apex_W := pos + make_vector2(-triangle_distance_from_center, 0);
    
    draw_bordered_triangle(triangle_apex_N, apex_height, base_halfwidth, border_width, .{0, 1},  color, border_color);
    draw_bordered_triangle(triangle_apex_S, apex_height, base_halfwidth, border_width, .{0, -1}, color, border_color);
    draw_bordered_triangle(triangle_apex_E, apex_height, base_halfwidth, border_width, .{1, 0},  color, border_color);
    draw_bordered_triangle(triangle_apex_W, apex_height, base_halfwidth, border_width, .{-1, 0}, color, border_color);
}

draw_bordered_triangle :: (apex: Vector2, apex_height: float, base_halfwidth: float, triangle_border_width: float, dir: Vector2, color: Vector4, border_color: Vector4) {
    strut := v2(-dir.y, dir.x);

    theta := atan(apex_height / triangle_border_width);  // Angle of a corner of the triangle.
    border_extension_distance := triangle_border_width / sin(theta * .5); // How far to go away from the barycenter to put the border around the triangle.

    //        triangle_base := center + (circle_r1 + triangle_extension_distance) * dir;
    //        apex := triangle_base - apex_height * dir;
    triangle_base := apex + apex_height * dir;

    {
        p0 := triangle_base + strut * base_halfwidth;
        p1 := apex;
        p2 := triangle_base - strut * base_halfwidth;

        barycenter := (p0 + p1 + p2) * (1/3.0);
        q0 := p0 + unit_vector(p0 - barycenter) * border_extension_distance;
        q1 := p1 + unit_vector(p1 - barycenter) * border_extension_distance;
        q2 := p2 + unit_vector(p2 - barycenter) * border_extension_distance;

        inner := border_color;
        outer := border_color;
        outer.w = 0;

        // The outline shadow:
        draw_procs.immediate_triangle(to_vec3(p0), to_vec3(q0), to_vec3(q1), inner, outer, outer);
        draw_procs.immediate_triangle(to_vec3(p0), to_vec3(q1), to_vec3(p1), inner, outer, inner);

        draw_procs.immediate_triangle(to_vec3(p1), to_vec3(q1), to_vec3(q2), inner, outer, outer);
        draw_procs.immediate_triangle(to_vec3(p1), to_vec3(q2), to_vec3(p2), inner, outer, inner);

        draw_procs.immediate_triangle(to_vec3(p2), to_vec3(q2), to_vec3(q0), inner, outer, outer);
        draw_procs.immediate_triangle(to_vec3(p2), to_vec3(q0), to_vec3(p0), inner, outer, inner);

        // The actual main triangle:
        draw_procs.immediate_triangle(to_vec3(p0), to_vec3(p1), to_vec3(p2), color, color, color);
    }
}

update_ring_point :: (state: *Color_Picker_State, center: Vector2, r0: float, r1: float) {
    // If we aren't doing anything, bail out early.
    if !(state.dragging_in_ring || (mouse_button_left_state & .START)) return;
    
    pos := make_vector2(mouse_x_float, mouse_y_float);
    pos -= center;

    clamped := pos;

    len := length(clamped);
    orig_len := len;

    Clamp(*len, r0, r1);
    normalize_or_zero(*clamped);
    clamped *= len;

    inside := true;
    if len != orig_len  inside = false;

    //
    // @Cleanup: We should not need all these can_see if input is grabbed when someone
    // is moving the window...
    //
    if inside && !state.dragging_in_ring {
        can_see := true;//  @Incomplete
        if can_see && (mouse_button_left_state & .START) {
            state.dragging_in_ring = true;
        }
    }

    if state.dragging_in_ring {
        state.ring_point = clamped;
        normalize_or_zero(*state.ring_point);
        state.ring_point *= (r0 + r1) * 0.5;
        
        if mouse_button_left_state & .DOWN {
            // note_color_changes(panel, false);
        } else {
            state.dragging_in_ring = false;
            // note_color_changes(panel, true);
        }
    }
}

map :: (p: float, ss: float, se: float, ds: float, de: float) -> float {
    return ds + (p-ss)*(de-ds)/(se-ss);
}

shade :: (_pos: Vector2, dir: float) -> float {
    pos := rotate(_pos, dir);
    h := cos(pos.x);
    return map(pos.y, h, -h, 0.0, 1.0);
}

make_hsv_warp_from_square_point :: (h: float, x: float, y: float) -> Vector3 {
    result := v3(h, x, y);
    return result;
}

make_hsv_warp_from_disc_point :: (h: float, x: float, y: float) -> Vector3 {
    // Find the full radial vector out to the square.
    sx := x;
    sy := y;
    if sx < 0 sx = -1;
    else sx = 1;

    if sy < 0 sy = -1;
    else sy = 1;

    total_len := sqrt(sx*sx+sy*sy);
    
    // Multiply by (len / radius), but radius is 1, so...

    p := v3(h, (x*total_len + 1) * .5, (y*total_len + 1) * .5);  // Map from [-1, 1] to [0, 1].
    Clamp(*p.y, 0, 1);
    Clamp(*p.z, 0, 1);
    return p;
}
                    
make_hsv :: (state: *Color_Picker_State, h: float, p: Vector3) -> Vector3 {
    u := p;
    saturate :: (f: float) -> float {
        if f < 0 return 0;
        if f > 1 return 1;
        return f;
    }
    
    y_range := sqrt(saturate(1 - u.x*u.x));
    x_range := sqrt(saturate(1 - u.y*u.y));

    tx := 0.0;
    if x_range  tx = (u.x / x_range) * .5 + .5;

    ty := 0.0;
    if y_range  ty = (u.y / y_range) * .5 + .5;

    Clamp(*tx, 0, 1);
    Clamp(*ty, 0, 1);

    s := sin(tx * TAU * .25);
    v := sin(ty * TAU * .25);

    s = lerp(s, s*s, state.toggled_s_t);
    v = lerp(v, v*v, state.toggled_v_t);

    return make_vector3(h, s, v);
}

image_quad_centered_at :: (pos: Vector2, w: float, h: float, color: Vector4) {
    p0 := v2(pos.x-w*.5, pos.y-w*.5);
    p1 := p0;
    p3 := p0;
    p1.x += w;
    p3.y += h;

    p2 := p1;
    p2.y += h;

    draw_procs.immediate_quad(p0, p1, p2, p3, color);
}


get_color_watch_colors :: (theme: *Color_Picker_Theme, rgb: Vector3) -> (rgba: Vector4, over: Vector4, pressed: Vector4, text: Vector4) {
    // white_zone := values_are_close(rgb, .{1,1,1}, 0.2);
    luminance := dot_product(rgb, .{.299, .587, .114});
    white_zone := (luminance > .65);
    
    over:     Vector4 = ---;
    pressed:  Vector4 = ---;
    text:     Vector4 = ---;

    if white_zone {
        k := .85;
        c := rgb * k;
        d := 0.15;

        over    = darken(v4(c.x, c.y, c.z, 1), d);
        pressed = darken(v4(c.x, c.y, c.z, 1), .3);
        text    = .{w=1};  // @Theme
    } else {
        k := 1.25;
        c := rgb * k;
        w := 0.15;

        Clamp(*c.x, 0, 1);
        Clamp(*c.y, 0, 1);
        Clamp(*c.z, 0, 1);

        over    = whiten(v4(c.x, c.y, c.z, 1), w);
        pressed = whiten(v4(c.x, c.y, c.z, 1), .3);
        text    = .{1,1,1,1};  // @Theme
    }

    color := v4(rgb.x, rgb.y, rgb.z, 1);
    return color, over, pressed, text;
}

update_disc_point :: (state: *Color_Picker_State, center: Vector2, radius: float) {
    // if !buttons_active  return;
    if !radius return;
    
    pos := v2(mouse_x_float, mouse_y_float);
    delta := pos - center;
    len_orig := length(delta);
    len := len_orig;
    inside := (len_orig <= radius);
    disc_point := delta / radius;
    
    // If we are inside a mickey mouse ear, don't clamp the radius.
    if state.circle_picker_in_warped_mode && !inside {
        center_white, center_saturated, ear_radius := get_mickey_mouse_ears();

        distance_white     := distance(disc_point, center_white)     - ear_radius;
        distance_saturated := distance(disc_point, center_saturated) - ear_radius;
        distance_main      := length(disc_point) - 1;

        if (distance_white < distance_main) && (distance_white <= distance_saturated) {
            // Clamp the disc point to the white ear.
            disc_point = center_white;
            inside = true;
        } else if (distance_saturated < distance_main) && (distance_saturated <= distance_white) {
            // Clamp the disc point to the saturated ear.
            disc_point = center_saturated;
            inside = true;
        }
    }

    if !inside {
        Clamp(*len, 0, radius);
        disc_point = unit_vector(delta) * (len / radius);
    }
    
    if inside && !state.dragging_in_disc {
        if mouse_button_left_state & .START {
            state.dragging_in_disc = true;
        }
    }

    if state.dragging_in_disc {
        if radius {
            state.disc_point = disc_point;
        }
        
        if mouse_button_left_state & .DOWN {
            // note_color_changes(panel, false);
        } else {
            // note_color_changes(panel, true);
            state.dragging_in_disc = false;
        }
    }
}

get_triangle_vertices :: (r: Rect, circle_r0: float) -> (Vector2, Vector2, Vector2) {
    tr := circle_r0;

    theta := TAU / 3.0;
    p0 := v2(tr, 0);
    p1 := v2(cos(theta) * tr, sin(theta) * tr);
    p2 := v2(cos(2*theta) * tr, sin(2*theta) * tr);

    return p0, p1, p2;
}

stash_color :: (using state: *Color_Picker_State, color: Vector3) {
    for stashed_colors {
        // Maybe we should use colors_are_very_close for consistency.
        if distance(it, color) == 0  return;
    }

    if stashed_colors.count >= MAX_STASHED_COLORS {
        array_ordered_remove_by_index(*stashed_colors, 0);
    }

    array_add(*stashed_colors, color);
}


#scope_file

// #import "Sloppy_Math";  // For values_are_close.

/*
Packed down tiny GLSL version of hsv2rgb... hmm!

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
*/
fract :: inline (x: float) -> float { return x - floor(x); }

hsv_to_rgb :: (cx: float, cy: float, cz: float) -> (r: float, g: float, b: float) {
    cx /= 360.0;
    p: Vector3;
    p.x = abs(fract(cx + 1)     * 6 - 3) - 1;
    p.y = abs(fract(cx + 2/3.0) * 6 - 3) - 1;
    p.z = abs(fract(cx + 1/3.0) * 6 - 3) - 1;

    Clamp(*p.x, 0, 1);
    Clamp(*p.y, 0, 1);
    Clamp(*p.z, 0, 1);

    p.x = lerp(1, p.x, cy);
    p.y = lerp(1, p.y, cy);
    p.z = lerp(1, p.z, cy);
    
    return cz * p.x, cz * p.y, cz * p.z;
}

/*
Old version we got off the internet that has a big switch statement.
hsv_to_rgb :: (h: float, s: float, v: float) -> (r: float, g: float, b: float) {
    if s < 0 {       // < is bogus, just shuts up warnings
        return v, v, v;
    }
    
    hh := h;
    if hh >= 360  hh = 0;
    hh /= 60;

    i := cast(s32) hh;
    ff := hh - xx i;
    p := v * (1 - s);
    q := v * (1 - s * ff);
    t := v * (1 - s * (1 - ff));

    if i == {
    case 0; return v, t, p;
    case 1; return q, v, p;
    case 2; return p, v, t;
    case 3; return p, q, v;
    case 4; return t, p, v;
    case 5; #through;
    case;   return v, p, q;
    }
}
*/

rgb_to_hsv :: (r: float, g: float, b: float) -> (h: float, s: float, v: float) {
    rgb_min := min(r, min(g, b));
    rgb_max := max(r, max(g, b));

    if rgb_max == 0  return 0, 0, 0;

    v := rgb_max;

    delta := rgb_max - rgb_min;
    
    s := delta / rgb_max;
    if s == 0 {  // This covers the case when rgb_max == rgb_min, so we don't worry about dividing by 0 below.
        return 0, 0, v;
    }

    h: float = ---;
    K :: (43/255.0);
    if rgb_max == r
        h = 0 + K * (g - b) / delta;
    else if rgb_max == g
        h = (85/255.0) + K * (b - r) / delta;
    else
        h = (171/255.0) + K * (r - g) / delta;

    return h*360, s, v;
}

circle_stretch :: (x: float, y: float) -> Vector3 {
    len := get_inscribed_square_intersector_length(x, y);

    factor := 1.0;
    if len > 0.0001  factor = 1 / len;  // We should never need this epsilon since the length does not get remotely that low.

    result: Vector3;
    result.x = x * factor;
    result.y = y * factor;
    return result;
}

get_inscribed_square_intersector_length :: (x: float, y: float) -> float {
    // Beacause of 8-fold symmetry, just put us into the first octant and go.
    // There, we are intersecting with the line x == root2 / 2.
    x = abs(x);
    y = abs(y);
    
    if y > x  Swap(*x, *y);
    if x < .0001  return 1;  // Avoid the singularity!
    
    len := sqrt(.5 + .5 * (y*y)/(x*x));
    return len;
}

update_animation_values :: (using state: *Color_Picker_State, dt: float) {
    UP_RATE   :: 9.0;
    DOWN_RATE :: 3.0;

    animate(*dragging_in_h_t, dragging_in_h, dt, UP_RATE, DOWN_RATE);
    animate(*dragging_in_h_zoom_t, dragging_in_h_zoom, dt, UP_RATE, DOWN_RATE);
    animate(*dragging_in_s_t, dragging_in_s, dt, UP_RATE, DOWN_RATE);
    animate(*dragging_in_l_t, dragging_in_l, dt, UP_RATE, DOWN_RATE);

    animate(*dragging_in_r_t, dragging_in_r, dt, UP_RATE, DOWN_RATE);
    animate(*dragging_in_g_t, dragging_in_g, dt, UP_RATE, DOWN_RATE);
    animate(*dragging_in_b_t, dragging_in_b, dt, UP_RATE, DOWN_RATE);

    animate(*dragging_in_ring_t, dragging_in_ring, dt, UP_RATE, DOWN_RATE);
    animate(*dragging_in_disc_t, dragging_in_disc, dt, UP_RATE, DOWN_RATE);

    animate(*dragging_in_hsv_rectangle_t, dragging_in_hsv_rectangle, dt, UP_RATE, DOWN_RATE);

    animate(*toggled_s_t, toggled_s, dt, UP_RATE, DOWN_RATE);
    animate(*toggled_v_t, toggled_v, dt, UP_RATE, DOWN_RATE);
    
//    animate(*hue_zoom_t, hue_zooming, dt, UP_RATE, DOWN_RATE);
}

animate :: (f: *float, condition: bool, dt: float, up_rate: float, down_rate: float) {
    if condition  { <<f = move_toward(<<f, 1, dt * up_rate); }
    else          { <<f = move_toward(<<f, 0, dt * down_rate); }
}


draw_mode_switch_buttons :: (state: *Color_Picker_State, theme: *Color_Picker_Theme, hash: u64, loc: Source_Code_Location, area: Rect) {
    NUM_BUTTONS :: 4;
    button_width := area.w / (NUM_BUTTONS+1);
    button_height := button_width;

    side_margin := (area.w - NUM_BUTTONS * button_width) * .5;

    buttons_strip := cut_top(area, button_height);
    junk, buttons_area := cut_left(buttons_strip, side_margin);

    r: Rect;
    remainder := buttons_area;
    for 0..NUM_BUTTONS-1 {
        r, remainder = cut_left(remainder, button_width);
        sub_hash := get_hash(#location(), it);
        button_hash := combine_hashes(hash, sub_hash);

        texture: *Texture;
        if it == 0  texture = map_mode_circle;
        if it == 1  texture = map_mode_hsv;
        if it == 2  texture = map_mode_rgb;
        if it == 3  texture = map_mode_numbers;
        pressed := button(r, "", *theme.mode_switch_button_theme, xx button_hash, loc, texture=texture);
        if pressed {
            stop_grabbing_text_input(state);
            state.color_pick_mode = xx it;
        }
    }
}



/*
get_hsv :: (p0: Vector2, p1: Vector2, p2: Vector2, p: Vector2, h: float) -> Vector3 {
    result: Vector3 = ---;
    result.x = h;

    dx := p.x - p2.x;

    ty: float;
    if p.y > p0.y {
        ty = (p.y - p1.y) / (p0.y - p1.y);
    } else {
        ty = (p.y - p2.y) / (p0.y - p2.y);
    }

    stride_x := ty * (p0.x - p2.x);

    if stride_x {
        result.y = dx / stride_x;
    } else {
        result.y = 0;
    }

    result.z = (p.y - p2.y) / (p1.y - p2.y);

    Clamp(*result.y, 0, 1);
    Clamp(*result.z, 0, 1);

    return result;
}

*/

to_u8 :: (f: float) -> u8 {
    ival: s32 = cast(s32) floor(f * 255 + .5);

    Clamp(*ival, 0, 255);  // Just in case we had some float out-of-rangeness...!
    
    return cast,no_check(u8) ival;
}    

get_mickey_mouse_ears :: () -> (center_white: Vector2, center_saturated: Vector2, radius: float) {
    r22 := sqrt(2.0) * .5;  // @Speed!
    return v2(-r22, r22)*1.05, v2(r22, r22)*1.05, .08;
}

