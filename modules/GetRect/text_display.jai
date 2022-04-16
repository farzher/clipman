Flowable_Text :: struct {
    unflowed_lines: [..] Unflowed_Line;
    flowed_lines:   [..] Flowed_Line;

    num_flowed_lines : s32 = 0;
    flowed_rect: Rect;
}

Unflowed_Line :: struct {
    pieces: [] Unflowed_Line_Piece;
}

Unflowed_Line_Piece :: struct {
    font: *Font;
    effects: Font_Effects;
    text: string;
    color: Vector4;
}

Flowed_Line :: struct {
    pieces: [] Unflowed_Line_Piece;
}

Flowed_Line_Piece :: struct {
    font: *Font;
    effects: Font_Effects;
    text: string;
    color: Vector4;
//    width_in_pixels: s32;
}

text_display :: (r: Rect, text: *Flowable_Text, offset_y: float, line_stride: float, theme: *Text_Display_Theme = null, identifier: s64 = 0, loc := #caller_location) {
    if !theme  theme = *default_panel_theme.text_display_theme;

    hash   := get_hash(loc, identifier);
    state  := find_or_create_state(*table_text_display, hash);

    status := get_status_flags(r);
    state.rect = r;
    state.text = text;
    
    if theme.auto_reflow_text {
        maybe_reflow_text_if_rect_dimensions_changed(text, r);
    }

    y := r.y + r.h + offset_y;

    push_scissor(r);
    visible := peek_pointer(scissor_stack);

    y0 := visible.y;
    y1 := visible.y + visible.h;

    for line: text.unflowed_lines {
        y -= line_stride;

        if y > y1 continue; // Do nothing for this line!
        if y < y0 - line_stride  break;  // No more can be visible!

        x := r.x;
        for piece: line.pieces {
            // @Incomplete: Handle justification using text_origin?
            text_width := cast(float) draw_procs.prepare_text(line.font, line.text, line.effects);

//            text_x, text_y := text_origin(theme, line.font, r, text_width);
            draw_procs.draw_prepared_text(line.font, xx x, xx y, line.color, line.effects);
            x += text_width;
        }
    }
    
    /* Rather than doing this like we do for other widgets, make sure all our events are serialized
       so that a move plus a ctrl-C gets the right stuff, and so forth.

    if state.selecting {
        if mouse_button_left_state & .DOWN {
            update_selection_endpoint_for_mouse_position(mouse_x_float, mouse_y_float);
        } else {
            state.selecting = false;
        }
    } else {
        if mouse_button_left_state & .PRESSED {
            start_selection(state, mouse_x_float, mouse_y_float);
            state.selecting = true;
        }
    }
*/
}

text_display_handle_event :: (state: *Text_Display_State, event: Event) {
    topic := get_current_topic();
    
    if event.type == .KEYBOARD {
        key := event.key_code;
        pressed := cast(bool) event.key_pressed;
        using Key_Code;

        inside := is_inside(mouse_x_float, mouse_y_float, state.rect);
        if inside {
            if pressed && (key == MOUSE_BUTTON_LEFT) {
                start_selection(mouse_x, mouse_y);
                cursor_tracking_mouse = true;
            }
        }

        if (!pressed) && (key == MOUSE_BUTTON_LEFT) {
            if topic.selection.active {
                update_selection_endpoint_for_mouse_position(mouse_x, mouse_y); // @Robustness: Put mouse positions in the actual events and use them here. 
                cursor_tracking_mouse = false;
            }
        }

        if topic.selection.active {
            key := event.key_code;
            if event.ctrl_pressed && (key == xx #char "C" || key == .INSERT) {
                snippets: [..] string;
                snippets.allocator = temp;
                sel := make_forward_selection(topic.selection);

                for i: sel.start_line..sel.end_line {
                    h := *topic.flowed_history[i];
                    line := h.text;

                    if i == sel.start_line {
                        tail := line;
                        advance(*tail, sel.start_character);
                    
                        if sel.start_line == sel.end_line {
                            tail.count = sel.end_character - sel.start_character;
                        }

                        array_add(*snippets, tail);
                    } else if i == sel.end_line {
                        tail := line;
                        tail.count = sel.end_character;

                        if h.continued && (snippets.count != 0) {
                            s := pop(*snippets);
                            tail = join(s, tail);
                            array_add(*snippets, tail);
                            free(tail);
                        } else {
                            array_add(*snippets, tail);
                        }
                    } else if (i >= sel.start_line) && (i <= sel.end_line) {
                        if h.continued && (snippets.count != 0) {
                            s := pop(*snippets);
                            line = join(s, line);
                            array_add(*snippets, line);
                            free(line);
                        } else {
                            array_add(*snippets, line);
                        }
                    }
                }
            
                text := join(..snippets, "\n");
                defer free(text);
            
                if text os_clipboard_set_text(text);

                reset_console_selection();
            }
        }
    }            
}


#scope_file

/*
console_add_to_topic :: (topic: *Topic_Info, _s: string, flags := NO_FLAGS, entry: *Buffered_Log_Entry) {
    unflowed := array_add(*topic.unflowed_history);
    unflowed.text = copy_string(_s);
    unflowed.continued = false;
    unflowed.flags = flags;

    if current_rt_width != -1 {   // If it's -1, we will reflow when we set visible geometry for the console.
        flow(topic, unflowed);
    }
}

flow :: (topic: *Topic_Info, unflowed: *History_Line) {
    effect :: 0;  // @Incomplete: Use whatever the console's style is (but now it is always 0).
    font := report_font;
    
    x0 := console_x0 * current_rt_width;
    x1 := console_x1 * current_rt_width - get_scrollbar_iwidth(current_rt_width);

    M_width := get_m_width(font);
    pad := report_font.character_height * report_text_left_pad;

    s := unflowed.text;
    continued := false;
    while s {
        text_width := get_string_width_in_pixels(font, s, effect);

        console_width := x1 - x0 - 2 * pad;
        if continued console_width -= xx M_width;  // So we have room to indent.
        
        if text_width <= xx console_width {
            flowed := array_add(*topic.flowed_history);
            << flowed = << unflowed;
            flowed.text      = s;
            flowed.continued = continued;
            break;
        }

        subtext := s;
        found := false;

        // @Speed! This is mega-slow. We could binary-search or something.
        // @Speed! This is mega-slow. We could binary-search or something.
        // @Speed! This is mega-slow. We could binary-search or something.
        // @Speed! This is mega-slow. We could binary-search or something.
        // @Speed! This is mega-slow. We could binary-search or something.
        // @Speed! This is mega-slow. We could binary-search or something.
        for 0..s.count {
            subtext.count = it;

            text_width := get_string_width_in_pixels(font, subtext, effect);
            if text_width > xx console_width {
                // Modify subtext to wrap at spaces.
                from_right := find_character_from_right(subtext, #char " ");
                if from_right && (from_right.count < subtext.count) {
                    subtext.count -= from_right.count-1;
                }

                found = true;
                break;
            }
        }

        if subtext {
            subtext.count -= 1;
            advance(*s, subtext.count);

            flowed := array_add(*topic.flowed_history);
            << flowed = << unflowed;
            flowed.text      = subtext;
            flowed.continued = continued;
            
            continued = true;
        } else {
            advance(*s, 1);
        }
    }
}
*/
#scope_file

find_line_and_character :: (text: *Flowable_Text, rt_width: int, rt_height: int, cursor_x: int, cursor_y: int) -> found: bool, line: int, character: int{
    //
    // @Cleanup: This whole thing uses a lot of code pasted from
    // when we draw the text, and we would like to @Refactor a bunch of it
    // to make it less rot-prone.  -jblow, 5 February 2017.
    //
    y0 := get_input_y1(get_console_bottom(rt_height));
    y1 := get_console_top(rt_height);

    // @Cutnpaste from actual font drawing.
    pad := report_font.character_height * report_text_left_pad;  // @Cutnpaste @Volatile
    x0 := console_x0 * rt_width;
    text_x := cast(int) (x0 + pad);  // @Cutnpaste
    text_y := cast(int) (y0 + pad);  // @Cutnpaste

    last_y := text_y;
    font := report_font;

    history := text.flowed_history;
    
    index := history.count - 1 - text.bottom_line_index;
    top := cast(int) get_console_top(rt_height);

    while text_y < top + report_font.character_height  {
        if index < 0 break;

        offset := 0;
        if history[index].continued {
            M_width := get_m_width(font);
            offset = M_width;
        }
        
        text_x0 := text_x + offset;

        line_y0 := text_y + font.max_descender;
        line_y1 := line_y0 + font.character_height;  // :FontYSpacing: Use the typical_line_spacing value, not character_height. @Cleanup.

        if (cursor_y >= line_y0) && (cursor_y < line_y1) {
            effect :: 0;  // @Cleanup
            text := history[index].text;
            character := get_insert_point_for_cursor(font, text, xx text_x0, cursor_x, effect);
            return true, index, character;
        }
        
        text_y += font.character_height;
        index -= 1;
    }
    
    return false, 0, 0;  // @Incomplete
}

start_selection :: (text: *Flowable_Text, cursor_x: int, cursor_y: int) {
    topic := get_current_topic();
    found, line, character := find_line_and_character(topic, cursor_x, cursor_y);

    if found {
        selection := *topic.selection;
        
        selection.active = true;
        selection.start_line = line;
        selection.start_character = character;
        selection.end_line = line;
        selection.end_character = character;

        reset_input_selection();
    }
}

update_selection_endpoint_for_mouse_position :: (rt_width: int, rt_height: int) {
    cursor_x, cursor_y, success := get_mouse_pointer_position(true);
    if success {
        topic := get_current_topic();
        found, line, character := find_line_and_character(topic, rt_width, rt_height, cursor_x, cursor_y);

        if found {
            topic.selection.end_line = line;
            topic.selection.end_character = character;
        }
    }
}

#scope_export
maybe_reflow_text_if_rect_dimensions_changed :: (text: *Flowable_Text, r: Rect) {
    do_flow := !text.flowed;

    flowed_count := text.num_flowed_lines;
    if (text.flowed_rect != r.x) || (text.flowed_rect != r.y) flowed_count = 0;

    if flowed_count == text.unflowed_lines.count return;

    flow_text(text, r, flowed_count);
}

flow_text :: (text: *Flowable_Text, r: Rect, flowed_count: s32) {
}
