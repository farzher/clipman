begin_scrollable_region :: (r: Rect, theme: *Scrollable_Region_Theme = null, identifier: s64 = 0, loc := #caller_location) -> (state: *Scrollable_Region_State, inside: Rect) {
    if !theme  theme = *default_panel_theme.scrollable_region_theme;

    rth := render_target_height;

    margin_x := floor(theme.horizontal_margin_size * rth + .5);
    margin_y := floor(theme.vertical_margin_size   * rth + .5);

    if !(theme.margin_flags & .Horizontal)  margin_x = 0;
    if !(theme.margin_flags & .Vertical)    margin_y = 0;

    scrollbar_width := floor(theme.scrollbar_size * rth + .5);
    bar_rect, content_area := cut_right(r, scrollbar_width);

    inside := content_area;
    inside.x += margin_x;
    inside.w -= margin_x*2;
    inside.y += margin_y;
    inside.h -= margin_y*2;

    // Draw the background quad.
    draw_procs.set_shader_for_color(true);
    rounded_rectangle(content_area, theme.region_background.shape, theme.region_background.color, theme.region_background.frame_color);
    
    push_scissor(inside);

    hash   := get_hash(loc, identifier);
    state  := find_or_create_state(*table_scrollable_region, hash);

    state.outer_rect = r;
    state.inner_rect = inside;
    state.bar_rect   = bar_rect;
    
    return state, inside;
}

end_scrollable_region :: (state: *Scrollable_Region_State, max_x: float, min_y: float, scroll_value: *float, theme: *Scrollable_Region_Theme = null) {
    if !theme  theme = *default_panel_theme.scrollable_region_theme;

    pop_scissor();

    inner := state.inner_rect;
    bar   := state.bar_rect;
    status_r   := get_status_flags(inner);
    status_bar := get_status_flags(bar);

    scroll_content_height := max(inner.y + inner.h + <<scroll_value - min_y, inner.h);
    if scroll_content_height <= 0.0  return;
    max_scroll_value := scroll_content_height - inner.h;

    b := floor(bar.w * theme.nib_margin + .5);
    min_nib_height := bar.w * theme.minimum_nib_height;

    // @Incomplete: Control whether bar draws with a style flag.
    draw_bar := true; // bar.w > 2*b && bar.h > 2*b;
    if draw_bar {
        background_color := theme.scrollbar_background.color;
        draw_procs.set_shader_for_color(true);

        trench_rect := bar;
        // trench_rect := get_rect(bar.x + b, bar.y + b, bar.w - 2*b, bar.h - 2*b);
        {
            rounded_rectangle(bar, theme.scrollbar_background.shape, background_color, theme.scrollbar_background.frame_color); // :FrameColor
        
            // p0, p1, p2, p3 = get_quad(trench_rect);
            // draw_procs.immediate_quad(p0, p1, p2, p3, whiten(trench_color, 0.1));
        }
        
        nib_height := min(max(trench_rect.h * (inner.h / scroll_content_height), min_nib_height), trench_rect.h);
        scroll_percent := 0.0;
        if max_scroll_value > 0.0  scroll_percent = <<scroll_value / max_scroll_value;
        nib_top := lerp(trench_rect.y + trench_rect.h, trench_rect.y + nib_height, scroll_percent);
        
        nib_rect := get_rect(trench_rect.x + b, nib_top - nib_height, trench_rect.w - 2*b, nib_height);
        nib_status    := get_status_flags(nib_rect);

        changed := cast(bool)(nib_status & .PRESSED);
        if state.dragging  nib_status |= Status_Flags.OVER | .DOWN; // Even if we go outside the rect, while dragging, have it stay in OVER state.
        over_factor, pressed_factor := update_production_value_button(nib_rect, changed, *state.nib_state, nib_status, *theme.scrollbar_nib_theme);

        nib_surface_color, nib_frame_color, nib_frame_thickness := get_colors_and_thickness_for_button(*theme.scrollbar_nib_theme, *state.nib_state, over_factor, pressed_factor);
        
        trench_status := get_status_flags(trench_rect);

        teleporting := false;
        if (nib_status & .OVER) && (mouse_button_left_state & .START) {
            state.dragging    = true;
            state.teleporting = false;
        } else if (trench_status & .OVER) && (mouse_button_left_state & .START) {
            state.teleporting = true;
            state.dragging    = false;
        }

        if !(mouse_button_left_state & .DOWN) {
            state.dragging    = false;
            state.teleporting = false;
        }
        
        if nib_height < trench_rect.h {
            if state.teleporting {
                // Jump the scroll nib to the cursor.
                p := (trench_rect.y + trench_rect.h - mouse_y_float - nib_height * 0.5) / (trench_rect.h - nib_height);
                <<scroll_value = lerp(0.0, max_scroll_value, p);
            }
            
            if state.dragging {
                // Drag the scroll nib.
                <<scroll_value -= mouse_delta_y_float * max_scroll_value / (trench_rect.h - nib_height);
            }
        }

        {
            rounded_rectangle(nib_rect, theme.scrollbar_nib_theme.rectangle_shape, nib_surface_color, nib_frame_color, frame_thickness_override=nib_frame_thickness); // :FrameColor
        }
    }

    if ((status_r & .OVER) || (draw_bar && (status_bar & .OVER))) && mouse_delta_z {
        dz := mouse_delta_z * (theme.mouse_wheel_increment * render_target_height);
        // Scroll with the mouse wheel.
        <<scroll_value -= dz;
    }

    Clamp(scroll_value, 0.0, max_scroll_value);
}
