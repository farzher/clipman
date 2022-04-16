// To be filled in.
base_checkbox :: (_r: Rect, text: string, selected: bool, theme: *Checkbox_Theme = null, identifier: s64 = 0, loc := #caller_location) -> bool {
    r := _r;
    hash  := get_hash(loc, identifier);
    state := find_or_create_state(*table_checkbox, hash);

    if !theme  theme = *default_panel_theme.checkbox_theme;
    
    label_theme := theme.label_theme;
    font := label_theme.font;
    if !font {
        font = get_default_font_at_size(r.h*.65);
        label_theme.font = font;
    }

    text_width, text_height := text_size(font, text);
    box_size := text_height - 1;

    w := r.w;
    h := r.h;
    
    status := get_status_flags(r);
    box_x := r.x;
    box_y := r.y + floor((h - box_size + 1) / 2);

    vibration := 0.0;
    {
        // Compute vibration if we have recently been perturbed.
        if state.action_duration_2 >= 0 {
            theta := TAU * 3 * state.action_duration_2;
            ct := sin(theta);

            damp := 1 - state.action_duration_2/2.3;
            Clamp(*damp, 0, 1);
            damp *= damp;
            if damp == 0  state.action_duration_2 = -1;

            vibration = box_size * ct * .05 * damp;
        }
    }
    
    button_theme := theme.button_theme;  // Copy this so we can change colors due to being selected.
    button := *button_theme;

    {
        // Update selected_t and modify button and text colors for the selected item.
        target := ifx selected then 1.0 else 0.0;

        denom := button.press_duration;
        if !denom denom = 1;
        rate   := ifx selected then 1.0/denom else 1.0;
        
        dt := current_dt;
        state.selected_t = move_toward(state.selected_t, target, dt * rate);  // Actually, let this be slow, so that the color change due to being pressed dominates the experience.

        button.surface_color = lerp(button.surface_color, theme.button_color_selected, state.selected_t);
        button.text_color       = lerp(button.text_color, theme.text_color_selected,   state.selected_t);
    }
    
    //
    // The bitmap part:
    //
    
    b := box_size + vibration;
    center_x := box_x + box_size * .5;
    center_y := box_y + box_size * .5;

    image: *Texture;
    if theme.is_radio_button {
        image = ifx selected then map_radiobox_full else map_radiobox_empty;
    } else {
        image = ifx selected then map_checkbox_full else map_checkbox_empty;
    }
    
    image_rect := get_rect(center_x-b*.5, center_y-b*.5, b, b);

    changed := cast(bool)(status & .PRESSED);
    over_factor, pressed_factor := update_production_value_button(image_rect, changed, *state.base, status, button);

    image_color := lerp(button.surface_color, button.surface_color_over,  over_factor);
    image_color  = lerp(image_color,          button.surface_color_down,  state.down_effect_t);
    image_color  = lerp(image_color,          button.surface_color_flash, pressed_factor);
    
    draw_procs.set_shader_for_images(image);
    {
        p0, p1, p2, p3 := get_quad(image_rect);
        draw_procs.immediate_quad(p0, p1, p2, p3, image_color);
        draw_procs.immediate_flush();
    }
    

    // If we are going from unselected to selected, then make selected_t be at least as high as pressed_factor,
    // so that by the time we reach the
    
    //
    // The text part:
    //
    r.x += box_size;
    r.w -= box_size;

    text_color := lerp(button.text_color, button.text_color_over,    over_factor);
    text_color  = lerp(text_color,        button.text_color_pressed, pressed_factor);
    label_theme.text_color = text_color;

    label(r, text, *label_theme);  // @Speed: Text was already prepped, we could tell that somehow.

    return changed;
}

checkbox_flags :: (r: Rect, text: string, flags: *$Enum, flag_value: Enum, theme: *Checkbox_Theme = null, identifier: s64 = 0, loc := #caller_location) -> bool {
    value := ((<<flags) & flag_value) != 0;     // @@ Operator precedence!
    if base_checkbox(r, text, value, theme, identifier, loc) {
        <<flags ^= flag_value;
        return true;
    }
    
    return false;
}

