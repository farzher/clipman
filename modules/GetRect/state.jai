Button_State :: struct {
    hash:    u64;

    over_duration := 0.0;
    over_effect_t := 0.0;

    down_duration := 0.0;
    down_effect_t := 0.0;

    action_duration   := -1.0;  // Set to 0 when an action first happens.
    action_duration_2 := -1.0;  // Set to 0 when an action first happens.

    pressed := false;  // @Temporary? Only used for vanilla button.
}

Column_Button_State :: struct {
    using base: Button_State;
    open_t:  float;  // Ranges from 0 to 1.
}

Checkbox_State :: struct {
    using base: Button_State;
    selected_t := 0.0;
}    

Slider_State :: struct {
    background: Button_State;
    foreground: Button_State;

    // Initial value is used so that we don't clamp it in the case of a relative drag.
    union {
        initial_value_float32: float32;
        initial_value_float64: float64;
        initial_value_int:     int;
    };

    sliding_t: float;
    slowing_t: float;

    accumulated_delta_for_int_slider := 0.0;

    sliding             := false;
    sliding_is_relative := false;
    inputting_text      := false;
}    

Title_Bar_State :: struct {
    using base: Button_State;
}

Text_Input_State :: struct {
    using base: Button_State;  // Not all of these members are used.
    
    camera_initted  := false;
    camera_x        := 0.0;
    active_t        := 0.0;
    
    shrunken_deadzone_margin := -1.0;     // -1 means disabled.
    last_displayed_text_x    := FLOAT32_INFINITY;  // Infinity means not yet initted (-1 might be a valid draw position!)
}

Scrollable_Region_State :: struct {
    nib_state:  Button_State;
    
    outer_rect: Rect;
    inner_rect: Rect;
    bar_rect:   Rect;

    dragging    := false;
    teleporting := false;
}

Slidable_Region_State :: struct {
    divider_state:  Button_State;

    left_or_top_rect:     Rect;
    right_or_bottom_rect: Rect;
    divider_rect:         Rect;
    theme:                *Slidable_Region_Theme;

    divider_t:              float;  // Divider position as a fraction of the input rect's slide_dimension.
    divider_over_factor:    float;  // @Cleanup: Probably we should leave this stuff on Button_State and just refer to it there. It'd be more compact?
    divider_pressed_factor: float; 
    
    dragging    := false;
}

Dropdown_State :: struct {
    open := false;
    open_t := 0.0;
}

Number_Input_State :: struct {
    text_input_state: Text_Input_State; // So that we can do the same hover/etc stuff, without a text input existing for this yet.

    inputting_text := false;
}

Color_Picker_State :: struct {
    ring_point     := Vector2.{1, 0};
    disc_point     := Vector2.{1, 0};

    dragging_in_ring:    bool;
    dragging_in_disc:    bool;

    dragging_in_h: bool;
    dragging_in_h_zoom: bool;
    dragging_in_s: bool;
    dragging_in_l: bool;
    dragging_in_r: bool;
    dragging_in_g: bool;
    dragging_in_b: bool;
    dragging_in_hsv_rectangle: bool;

    dragging_in_ring_t: float;
    dragging_in_disc_t: float;
    dragging_in_h_t: float;
    dragging_in_h_zoom_t: float;
    dragging_in_s_t: float;
    dragging_in_l_t: float;
    dragging_in_r_t: float;
    dragging_in_g_t: float;
    dragging_in_b_t: float;
    dragging_in_hsv_rectangle_t: float;

    toggled_s: bool;
    toggled_v: bool;
    toggled_s_t: float;
    toggled_v_t: float;
    
/*
    hue_zooming: bool;
    hue_zoom_t:  float;
*/

    hsv_picker_in_rectangle_mode := true;
    circle_picker_in_warped_mode := false;
    
    zoom_hue_center := 0.0;  // In degrees; where the zoomed hue bar is centered. Doesn't move when you change hue via that bar itself.
    
    color_pick_mode := Color_Pick_Mode.HSV_CIRCLE;

    current_hsv_color: Vector3;      // In 2.2 gamma space.
    current_rgb_color: Vector3;      // In 2.2 gamma space.

    original_rgb_color: Vector3;     // In 2.2 gamma space.

    stashed_colors: [..] Vector3;
}

Text_Display_State :: struct {
    rect: Rect;
    text: *Flowable_Text;
    selecting := false;
}

table_button:            Table(u64, Button_State);
table_column_button:     Table(u64, Column_Button_State);
table_title_bar:         Table(u64, Title_Bar_State);
table_checkbox:          Table(u64, Checkbox_State);
table_slider:            Table(u64, Slider_State);
table_text_input:        Table(u64, Text_Input_State);
table_dropdown:          Table(u64, Dropdown_State);
table_color_picker:      Table(u64, Color_Picker_State);
table_number_input:      Table(u64, Number_Input_State);
table_scrollable_region: Table(u64, Scrollable_Region_State);
table_slidable_region:   Table(u64, Slidable_Region_State);
table_text_display:      Table(u64, Text_Display_State);

find_or_create_state :: (table: *$T/Table, hash: u64) -> (*T.Value_Type, created: bool) {
    p := table_find_pointer(<<table, hash);
    if p  return p, false;

    state: T.Value_Type;  // A dummy to add a blank entry.
    p = table_add(table, hash, state);
    return p, true;
}

