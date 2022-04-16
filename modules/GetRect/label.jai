default_text_baseline :: (font: *Font, height: float) -> float {
    // Just a heuristic to try to line up fonts, kind of.
    // Could probably be better.
    active_height := font.character_height * 0.55;
    pad := height - active_height;

    return floor(pad * 0.5);
}

text_origin :: (theme: *Label_Theme, font: *Font, r: Rect, text_width: float) -> (x: float, y: float) {
    // theme.font is ignored, so that people can pass in a substituted font.
    // However, other properties like alignment, baseline, etc are used here.
    
    x := r.x;

    if #complete theme.alignment == {
      case .Left;
        x += em(theme.alignment_pad_ems, font);
      case .Center;
        x += (r.w - text_width) * 0.5;
      case .Right;
        x += (r.w - text_width) - em(theme.alignment_pad_ems, font);
    }
    
    // y := text_baseline(font, y, y+r.h);
    vert := theme.text_baseline_vertical_position;
    if vert == FLOAT32_INFINITY {
        vert = default_text_baseline(font, r.h);
    } else {
        vert *= r.h;
    }
    
    y := r.y + vert;

    // Due to atlassed texture rendering, we draw text at integer coordinates currently.
    // If we wish to change this, don't round! (Or round to whatever subpixel resolution
    // we generate atlas alternatives at. etc.)
    x = floor(x + .5);
    y = floor(y + .5);
    return x, y;
}

// Right now, the difference between 'core_draw_label' and 'label' is that
// 'core_draw_label' does not scissor... but I probably want to make it so that
// we have a version of label that uses prepped text. To Be Continued...
label_from_prepared_text :: (r: Rect, font: *Font, theme: *Label_Theme, do_scissor := true) {
    assert(font != null);  // Font must be specified to use this, because that is where the prepared text is stored. That is why the font is passed specifically.
        
    text_width := cast(float) font.temporary_glyphs_width_in_pixels;
    if (text_width > r.w) && do_scissor        push_scissor(r);
    defer if (text_width > r.w) && do_scissor  pop_scissor();

    text_x, text_y := text_origin(theme, font, r, text_width);
    draw_procs.draw_prepared_text(font, xx text_x, xx text_y, theme.text_color, theme.effects);
}

label :: (r: Rect, text: string, theme: *Label_Theme, do_scissor := true) {
    font := theme.font;
    if !font  font = get_default_font_at_size(r.h *.65);

    text_width := cast(float) draw_procs.prepare_text(font, text, theme.effects);

    if (text_width > r.w) && do_scissor        push_scissor(r);
    defer if (text_width > r.w) && do_scissor  pop_scissor();

    text_x, text_y := text_origin(theme, font, r, text_width);
    draw_procs.draw_prepared_text(font, xx text_x, xx text_y, theme.text_color, theme.effects);
}
