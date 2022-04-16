// Size_Computation controls the way the sizes of various widget aspects are computed. Wherever there
// is a declaration of type Size_Computation, there is also a similarly-named floating point parameter
// that acts as an argument. Rectangle_Shape, for example, has two fields 'roundedness_type' and 'roundedness'.
// Setting 'roundedness_type' to RELATIVE_TO_HEIGHT causes the system to multiply 'roundedness' by rect.h
// to get the radius, in pixels, of the circle used to round the corner of the widget.
//
// The various options are:
//
//   RELATIVE_TO_HEIGHT:        Size is computed by multiplying the relevant theme field by the height of the Rect passed to the widget function.
//   RELATIVE_TO_WIDTH:         Size is computed by multiplying the relevant theme field by the height of the Rect passed to the widget function.
//   ABSOLUTE_FROM_THEME_FIELD: The value in the field is used verbatim as the number of pixels. If the target you are shipping on does not have a known fixed display resolution, you should update this field yourself based on screen resolution.
//   ABSOLUTE_FROM_GLOBAL:      If you want all your themes to have matched sizes for some parameter, regardless of their rect sizes, but you don't want to manually adjust them all whenever the display resolution changes, you can use built-in global variables. See, for example, set_global_rounding_radius_in_pixels() in module.jai. If you do not call these setter functions yourself, the globals will hold some default value that is recomputed whenever the resolution changes. Once you do call any of the setter functions, the system will no longer automatically update it, so responsibility is on you to maintain that value as the resolution changes.
//

Size_Computation :: enum u8 {   // Defaults to RELATIVE_TO_HEIGHT.
    RELATIVE_TO_HEIGHT        :: 0;
    RELATIVE_TO_WIDTH         :: 1;
    ABSOLUTE_FROM_THEME_FIELD :: 2;
    ABSOLUTE_FROM_GLOBAL      :: 3;
};

Rectangle_Shape :: struct {
    roundedness_type: Size_Computation;
    
    roundedness := .18;   // If absolute, this is the number of pixels. If relative, set this to a value in [0, 1]: 0 == totally squared off; 1 == capsule along the width or height (though this will be clamped to the shortest side).
    
    pixels_per_edge_segment  := 10.0;  // How many triangles we generate for the curves, based on the length of the arc.

    frame_thickness_type: Size_Computation;
    frame_thickness := .02;            // By default, .02 * rect.h. Set to a value <= 0 for no frame.

    Rounding_Flags :: enum_flags u32 {
        NORTHEAST :: 0x1;
        NORTHWEST :: 0x2;
        SOUTHWEST :: 0x4;
        SOUTHEAST :: 0x8;
    }

    rounding_flags := Rounding_Flags.NORTHEAST | .NORTHWEST | .SOUTHWEST | .SOUTHEAST;
}

Label_Theme :: struct {
    font:    *Font;
    effects: Font_Effects;
    
    text_color                      := Vector4.{1, 1, 1, 1};
    alignment                       := Text_Alignment.Center;
    alignment_pad_ems               := 1.0;
    text_baseline_vertical_position := FLOAT32_INFINITY;      // How high up the rect is the text baseline, relative to rect height.  If it is FLOAT32_INFINITY, we choose a default based on the input rect.
}

Background_Theme :: struct {
    shape: Rectangle_Shape;

    color       := Vector4.{.08, .08, .08, 1.0};
    frame_color := Vector4.{.25, .25, .22, 1.0};
}

Button_Theme :: struct {
    using label_theme: Label_Theme;

    rectangle_shape:   Rectangle_Shape;
    
    surface_color            := Vector4.{.08, .08, .08, 1.0};
    surface_color_over       := Vector4.{.15, .15, .20, 1.0};
    
    surface_color_flash := Vector4.{.60, .77, .62, 1.0};
    surface_color_down       := Vector4.{.28, .28, .38, 1.0};  // When held down.
    
    text_color                = Vector4.{.82, .82, .82, 1.0};  // (Inherited from Label_Theme).
    text_color_over          := Vector4.{.95, .95, .95, 1.0};
    text_color_pressed       := Vector4.{.99, .99, .99, 1.0};  // @Cleanup: Should change this to "text_color_down".

    text_offset_down         := Vector2.{.12, -.12};  // In ems.

    // Default frame thickness comes from rectangle_shape.
    frame_thickness_over     := .04;
    frame_thickness_down     := .05;
    frame_thickness_flash := .07;
    enable_variable_frame_thickness := false;
    
    frame_color              := Vector4.{.40, .40, .50, 1.0};
    frame_color_over         := Vector4.{.55, .55, .45, 1.0};
    frame_color_flash := Vector4.{.99, .99, .65, 1.0};
    frame_color_down         := Vector4.{.75, .75, .55, 1.0};
        
    press_duration       := 0.7;    // The flash when you press the button.

    over_fade_in_speed   := 10.0;  // Higher is faster; 10 == 1/10 second for full fade in.
    over_fade_out_speed  := 4.0;   // 4 == 1/4 second for full fade in.
    
    down_fade_in_speed   := 12.0;
    down_fade_out_speed  := 4.0;
        
    highlight_lighten_parameter := .15; // For lighter theme colors, you might want more ligten and less darken.
    highlight_darken_parameter  := .6;
    
    alpha_scale := 1.0;

    texture_scale := 1.0;  // Relative to the size of the button, if a texture is being drawn.
}

Slider_Theme :: struct {

    // The 'down' state of the button themes is used when sliding.
    foreground: Button_Theme;
    foreground.surface_color         = Vector4.{0.0, 0.50, 0.35, 1.0};
    foreground.surface_color_over    = Vector4.{0.0, 0.60, 0.40, 1.0};
    foreground.surface_color_flash   = Vector4.{.03, 0.80, 0.30, 1.0};
    foreground.surface_color_down    = Vector4.{.30, 0.60, 0.40, 1.0};

    foreground.frame_color           = Vector4.{0.2, 0.70, 0.55, 1.0};
    foreground.frame_color_over      = Vector4.{0.2, 0.80, 0.60, 1.0};
    foreground.frame_color_flash     = Vector4.{.23, 0.95, 0.50, 1.0};
    foreground.frame_color_down      = Vector4.{.50, 0.80, 0.60, 1.0};

    foreground.alignment         = .Center;  // Alignment for the text.
    foreground.alignment_pad_ems = .5;

    decimals: s32 = 2;  // If sliding a float, how many digits of precision to display after the decimal.
    
    background: Button_Theme;
    background.surface_color          = Vector4.{0.0, 0.1, 0.00, 1.0};
    background.surface_color_over     = Vector4.{0.0, 0.2, 0.00, 1.0};
    background.surface_color_flash    = Vector4.{0.0, 0.2, 0.10, 1.0};
    background.surface_color_down     = Vector4.{0.0, 0.2, 0.15, 1.0};
    
    background.frame_color            = Vector4.{0.2, 0.3, 0.20, 1.0};
    background.frame_color_over       = Vector4.{0.2, 0.4, 0.20, 1.0};
    background.frame_color_flash      = Vector4.{0.2, 0.4, 0.30, 1.0};
    background.frame_color_down       = Vector4.{0.2, 0.4, 0.35, 1.0};

    surface_margin   := .15;      // As a fraction of the rect height.

    text_editable    := true;     // Right-click or left-double-click to edit, if this is set.  @Incomplete: double-click not yet handled.
    clamp_text_input_low  := true;
    clamp_text_input_high := true;

    sliding_is_relative   := false;  // If false, the slider goes to the mouse pointer's position on the screen. If true, you change it via mouse motion.
    sliding_becomes_relative_by_pressing_shift := true;  // Has no meaning if sliding_is_relative == true. But if we start in non-relative mode, we can become relative by pressing shift. This also changes the slide factor from default to modified.
    
    relative_slide_factor          := 0.7;    // The number of pixels by which the slider value will change, relative to the number of pixels of mouse motion.
    relative_slide_factor_modified := 0.2;    // Slide factor when the user is holding the shift key.

    do_clamp_if_we_are_relative_dragging_but_started_outside_the_clamp_range := false;  // By default you can type a value beyond the official min/max, and still be able to drag out in that range. Set to true if you want to clamp on any drag action.  See also clamp_text_input_*.
    
    text_input_theme: Text_Input_Theme;  // If you decide to edit the slider. Note, this has a separate alignment_pad_ems, etc, so you may wish to keep these in sync with the slider's sliding-mode display, or, you may not.

    use_spinboxes    := true;
    spinbox_button_width    := 1.0;      // As a fraction of the slider rect's height. 1.0 means each spinbox button will be square, and 2*height will be cut from the main rect to make space for the spinbox.

    spinbox_theme:      Button_Theme;

    spinbox_theme.text_color         = .{ .1, .42, .42, 1.0 };
    spinbox_theme.text_color_over    = .{ .4, .70, .70, 1.0 };
    spinbox_theme.text_color_pressed = .{ .5, .99, .99, 1.0 };

    spinbox_theme.frame_color            = Vector4.{0.2, 0.25, 0.40, 1.0};
    spinbox_theme.frame_color_over       = Vector4.{0.2, 0.30, 0.50, 1.0};
    spinbox_theme.frame_color_flash      = Vector4.{0.2, 0.35, 0.60, 1.0};
    spinbox_theme.frame_color_down       = Vector4.{0.2, 0.55, 0.5, 1.0};
}

Checkbox_Theme :: struct {
    using button_theme: Button_Theme;

    // Button_Theme's surface_color, etc are used for the checkbox bitmap.
    surface_color         = .{.55, .55, .55, 1.0};
    surface_color_over    = .{.80, .80, .80, 1.0};
    surface_color_flash = .{.90, .70, .90, 1.0}; 
    surface_color_down    = .{.90, .70, .90, 1.0};  // When held down.
    
    text_color               = .{.55, .55, .55, 1.0};
    text_color_over          = .{.80, .80, .80, 1.0};
    text_color_pressed       = .{.90, .70, .90, 1.0};

    // There aren't separate 'over' and 'pressed' colors when selected,
    // though maybe we should add those?
    button_color_selected   := Vector4.{.90, .90, .90, 1.0};
    text_color_selected     := Vector4.{.90, .60, .90, 1.0};

    is_radio_button := false;

    alignment         = .Left;  // Alignment for the text.
    alignment_pad_ems = 0.2;    // Spacing between checkbox and text.
}

Margin :: enum_flags {
    Horizontal :: 0x1;
    Vertical   :: 0x2;
}

Panel_Theme :: struct {
    button_theme:            Button_Theme;
    checkbox_theme:          Checkbox_Theme;
    label_theme:             Label_Theme;
    slider_theme:            Slider_Theme;
    scrollable_region_theme: Scrollable_Region_Theme;
    dropdown_theme:          Dropdown_Theme;
    color_picker_theme:      Color_Picker_Theme;
    slidable_region_theme:   Slidable_Region_Theme;
    text_display_theme:      Text_Display_Theme;
    
    // These are the same ingredients as in Button_Theme ..
    // Hmmmmm!!
    font: *Font;

    background_color        := Vector4.{.05, .05, .05, 1.0};
    background_color_bright := Vector4.{.15, .15, .15, 1.0};
    text_color              := Vector4.{.80, .80, .80, 1.0};

    title_bar_color         := Vector4.{.80, .30, .30, 1.0};
    title_bar_color_hilit   := Vector4.{.95, .50, .50, 1.0};

    border_width       := .004;  // Border of the window, relative to render target height.
    outer_margin_size  := .007;  // Outer margin of the content space, relative to render target height.
    outer_margin_flags := Margin.Horizontal | .Vertical;
    
    scrollable_section_margin_width := .007;  // Outer margin of the content space, relative to render target height.
    scrollable_section_margin_flags := Margin.Horizontal | .Vertical;
    
    alpha_scale := 1.0;
}

Text_Input_Theme :: struct {
    // @Incomplete: label_theme.effects not yet used when drawing.

    // A Button_Theme is used for general background and frame coloring.
    // The "down" state of the theme is used when the Text_Input is active.
    using button_theme: Button_Theme;
    alignment = .Left;
    button_theme.surface_color        = Vector4.{.07, .07, .20, 1.0};
    button_theme.surface_color_over   = Vector4.{.12, .12, .99, 1.0};
    button_theme.surface_color_down   = Vector4.{.66, .10, .40, 1.0};
    button_theme.surface_color_flash  = Vector4.{.60, .77, .62, 1.0};

    button_theme.frame_color          = Vector4.{.10, .25, .40, 1.0};
    button_theme.frame_color_over     = Vector4.{.15, .45, .75, 1.0};
    button_theme.frame_color_down     = Vector4.{.45, .75, .95, 1.0};
    button_theme.frame_color_flash    = Vector4.{.85, .85, .99, 1.0};
    

    
    text_color               = Vector4.{.30, .65, .65, 1.0};  // Inherited from button_theme.label_theme.
    
    text_color_over          = Vector4.{.99, .70, .70, 1.0};
    text_color_pressed       = Vector4.{.55, .99, .99, 1.0};

    text_color_autocomplete        := Vector4.{.30, .99, .30, 0.9};
    text_color_autocomplete_failed := Vector4.{.99, .55, .55, 0.9};

    selection_color         := Vector4.{.15, .09, .75, 1.0};

    cursor_color            := Vector4.{1.0, 1.0, 1.0, 1.0};
    
    text_insert_margin         := 4.7;  // How much you want to be able to see when typing near the edge of a text in put, in ems. The resulting pixel value is clamped at 49% of the width of the rect at render time (otherwise it would be ill-defined where you want the insert point to be, unless we had two different margins).

    cursor_width_inside_text   := 0.11;  // In ems.
    cursor_width_outside_text  := .55;   // In ems.    
}

Scrollable_Region_Theme :: struct {
    horizontal_margin_size := 0.005;   // Relative to render target height.
    vertical_margin_size   := 0.005;   // Relative to render target height. It's intentional that this is width and not height, because by default youwant the sizes of the two margins to be controllable relative to each other, not messed up by random aspect ratio changes.

    scrollbar_size := 0.03;            // Relative to render target height. This indicates the width for a vertical scrollbar, or height for a horizontal scrollbar.

    minimum_nib_height := 1.0;         // Relative to scrollbar size. 1.0 means it will not get shorter than the width of the scrollbar.
    nib_margin := 0.10;                // Margin between trench and nib, relative to scrollbar size.
    
    margin_flags := Margin.Horizontal | .Vertical;

    scrollbar_nib_theme: Button_Theme;
    scrollbar_nib_theme.surface_color                    = Vector4.{.55, .05, .55, 1};
    scrollbar_nib_theme.surface_color_over               = Vector4.{.70, .05, .70, 1};
    scrollbar_nib_theme.surface_color_flash = Vector4.{.90, .50, .90, 1};
    scrollbar_nib_theme.surface_color_down               = Vector4.{.85, .15, .85, 1};
    scrollbar_nib_theme.rectangle_shape.frame_thickness_type = .RELATIVE_TO_WIDTH;
    scrollbar_nib_theme.rectangle_shape.roundedness_type     = .RELATIVE_TO_WIDTH;
    scrollbar_nib_theme.rectangle_shape.roundedness          = .24;
    scrollbar_nib_theme.enable_variable_frame_thickness = true;
    scrollbar_nib_theme.frame_thickness_over = .1;
    scrollbar_nib_theme.frame_thickness_down = .12;
    scrollbar_nib_theme.frame_thickness_flash = .15;
    scrollbar_nib_theme.frame_color                    = Vector4.{.65, .25, .65, 1};
    scrollbar_nib_theme.frame_color_over               = Vector4.{.72, .45, .72, 1};
    scrollbar_nib_theme.frame_color_flash = Vector4.{.99, .90, .99, 1};
    scrollbar_nib_theme.frame_color_down               = Vector4.{.88, .60, .88, 1};

    region_background: Background_Theme;
    region_background.shape.rounding_flags       = Rectangle_Shape.Rounding_Flags.NORTHWEST | .SOUTHWEST;
    region_background.shape.frame_thickness_type = .ABSOLUTE_FROM_GLOBAL;
    region_background.shape.roundedness_type     = .RELATIVE_TO_WIDTH;
    region_background.shape.roundedness          = .06; // Scrollable regions are bound to be pretty wide, so default this to a kinda small value
    region_background.frame_color                = Vector4.{0.35, 0.28, 0.40, 1.0};
    region_background.color                      = Vector4.{0.08, 0.013, 0.10, 1.0};

    scrollbar_background: Background_Theme;
    scrollbar_background.shape.rounding_flags       = Rectangle_Shape.Rounding_Flags.NORTHEAST | .SOUTHEAST;
    scrollbar_background.shape.frame_thickness_type = .ABSOLUTE_FROM_GLOBAL;
    scrollbar_background.shape.roundedness_type     = .RELATIVE_TO_WIDTH;
    scrollbar_background.frame_color                = Vector4.{0.30, 0.22, 0.34, 1.0};
    scrollbar_background.color                      = Vector4.{0.17, 0.015, 0.20, 1.0};

    mouse_wheel_increment := 0.0004;  // Distance to scroll per tick of the mouse wheel, relative to render target height.
}

Slidable_Region_Theme :: struct {
    orientation: enum u8 {
        HORIZONTAL :: 0;
        VERTICAL   :: 1;
    }

    divider_theme: Button_Theme;
    divider_theme.surface_color       = .{.4, .6, .7, 1};
    divider_theme.surface_color_over  = .{.7, .8, .9, 1};
    divider_theme.surface_color_down  = .{.8, .9, .95, 1};
    divider_theme.surface_color_flash = .{.9, .87, .99, 1};

    divider_thickness_type := Size_Computation.ABSOLUTE_FROM_GLOBAL;
    divider_thickness      := .02;

    initial_divider_position_type := Size_Computation.RELATIVE_TO_HEIGHT;
    initial_divider_position      := 0.5;

    first_background:  Background_Theme;    
    second_background: Background_Theme;

    first_background.shape.frame_thickness_type  = .ABSOLUTE_FROM_GLOBAL;
    first_background.shape.rounding_flags        = Rectangle_Shape.Rounding_Flags.NORTHWEST | .SOUTHWEST;
    second_background.shape.frame_thickness_type = .ABSOLUTE_FROM_GLOBAL;
    second_background.shape.rounding_flags       = Rectangle_Shape.Rounding_Flags.NORTHEAST | .SOUTHEAST;
}

Dropdown_Theme :: struct {
    theme_for_current_value:  Button_Theme;
    theme_for_each_choice:    Button_Theme;
    theme_for_current_choice: Button_Theme;  // When drawing the current value in the choice list.

    theme_for_current_value.surface_color        = .{.3, .07, .05, 1};
    theme_for_current_value.surface_color_over   = .{.4, .1, .15, 1};
    theme_for_current_value.surface_color_flash  = .{.75, .75, .55, 1};
    theme_for_current_value.surface_color_down   = .{.4, .4, .25, 1};

    theme_for_current_value.frame\  _color       = .{.6, .37, .35, 1};
    theme_for_current_value.frame\  _color_over  = .{.7, .4, .45, 1};
    theme_for_current_value.frame\  _color_flash = .{.95, .95, .85, 1};
    theme_for_current_value.frame\  _color_down  = .{.7, .7, .55, 1};

    theme_for_current_choice.surface_color       = .{.8, .2, .05, 1};
    theme_for_current_choice.surface_color_over  = .{.9, .3, .15, 1};
    theme_for_current_choice.surface_color_flash = .{.95, .75, .55, 1};
    theme_for_current_choice.surface_color_down  = .{.99, .4, .25, 1};

    theme_for_current_choice.frame\ _color       = .{.9, .5, .35, 1};
    theme_for_current_choice.frame\ _color_over  = .{.95, .6, .45, 1};
    theme_for_current_choice.frame\ _color_flash = .{.99, .95, .85, 1};
    theme_for_current_choice.frame\ _color_down  = .{.99, .7, .55, 1};

    theme_for_each\  _choice.surface_color       = .{.15, .05, .05, 1};
    theme_for_each\  _choice.surface_color_over  = .{.25, .12, .12, 1};
    theme_for_each\  _choice.surface_color_flash = .{.65, .55, .35, 1};
    theme_for_each\  _choice.surface_color_down  = .{.40, .20, .10, 1};

    theme_for_each\  _choice.frame\ _color       = .{.35, .20, .20, 1};
    theme_for_each\  _choice.frame\ _color_over  = .{.45, .25, .25, 1};
    theme_for_each\  _choice.frame\ _color_flash = .{.95, .85, .85, 1};
    theme_for_each\  _choice.frame\ _color_down  = .{.70, .50, .35, 1};
    
    dropdown_indicator_aspect_ratio := 1.0;  // This is for the little arrow showing it's a dropdown box. 1.0 means it's square, with width equal to r.h.

    arrow_flip_up_rate   := 2.5;
    arrow_flip_down_rate := 3.9;
}

Color_Picker_Theme :: struct {
    horizontal_padding  := .06;   // Relative to rect.w.
    vertical_padding    := .06;   // Relative to rect.w. (This is not a mistake.)
    
    stashed_color_width := .10;   // Relative to rect.w.
    margin_between_color_input_and_stashed_colors := .06; // Relative to rect.w.

    background: Background_Theme;
    background.shape.roundedness_type     = .RELATIVE_TO_WIDTH;
    background.shape.roundedness          = .09;
    background.shape.frame_thickness_type = .RELATIVE_TO_WIDTH;
    
    background.color                      = Vector4.{.00, .10, .10, 1};
    
    outer_circle_diameter := .99;    // Relative to the available circle area's width (which is computed by cutton off the margins).
    inner_circle_diameter := .73;    // Same.
    inner_disc_radius     := .95;    // Relative to inner_circle_diameter. 1.0 means it will meet the inner circle (but the rendering is not set up to do this seamlessly so you would get cracks etc.)
    
    initial_stashed_colors: [] Vector3 = Vector3.[
            .{1,1,1}, .{.1, .1, .1},
            .{.529, .248, .214}, .{.744, .601, .199}, .{.788, .555, .456}, .{.469, .805, .230}, .{.184, .744, .286}, .{.184, .654, .744}, .{.405, .360, .782}, .{.778, .456, .722}
    ];

    apply_and_revert_button_theme: Button_Theme;
    apply_string  := "Apply";
    revert_string := "Revert";

    slider_hue_min := -50.0;   // In degrees.
    slider_hue_max := 345.0;  // In degrees. This covers more than 360 degrees, so we have overlap in reds etc.

    hue_range_in_zoomed_slider := 60.0;

    stash_button_theme:       Button_Theme;

    mode_switch_button_theme: Button_Theme;
    mode_switch_button_theme.text_color.w  = .45;  // This is for the button bitmaps.
    mode_switch_button_theme.texture_scale = .7;  
    
    type_ins_label_theme: Label_Theme;
    type_ins_label_theme.text_color = Vector4.{.30, .65, .65, 1.0};
    type_ins_label_theme.alignment_pad_ems = 0.3;
    
    type_ins_input_theme: Number_Input_Theme;

    stashed_colors_shape: Rectangle_Shape;
    stashed_colors_shape.frame_thickness = 0.06;
}

Number_Input_Theme :: struct {
    using text_input_theme: Text_Input_Theme;
    text_input_theme.cursor_width_outside_text = .11;   // In ems. Matches the default inside_text value, so it looks the same. That way we don't spend a bunch of cursor space at the end of narrow text inputs, where it usually will be.
    text_input_theme.alignment_pad_ems = .2;
    text_input_theme.button_theme.surface_color = .{.08*.7, .208*.7, .236*.7, 1.0};

    // Some of this is a lot like what's on Slider, and we could
    // think about merging things or whatevs.

    // Some other things are a lot like what's on Button_Theme,
    // and in fact our state struct currently uses Button's
    // to do action durations etc.

    clamp_low  := true;
    clamp_high := true;
}

Text_Display_Theme :: struct {
    using text_theme: Label_Theme;

    // @Incomplete
    top_margin_type: Size_Computation;
    top_margin:      float;

    // @Incomplete
    left_margin_type: Size_Computation;
    left_margin:     float;

    // @Incomplete
    right_margin_type: Size_Computation;
    right_margin:     float;

    auto_reflow_text := false;
}

