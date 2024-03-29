// Input handler routines, platform-independent.

/*
  KNOWN PROBLEM: On Windows, keys will be erroneously considered held-down if you press them, alt-tab, then release.
  They'll get un-stuck if you press them again. To be fixed.
 */

#if OS == .WINDOWS {
    #load "windows.jai";
} else #if OS == .LINUX {
    #load "x11.jai";
} else #if OS == .MACOSX {
    #load "osx.jai";
}

Event_Type :: enum u32 {  // If we set this to u8, our packing will stop matching C's.
    UNINITIALIZED       :: 0;
    KEYBOARD            :: 1;
    TEXT_INPUT          :: 2;
    WINDOW              :: 3;
    MOUSE_WHEEL         :: 4;
    QUIT                :: 5;
    DRAG_AND_DROP_FILES :: 6;
    CLIP_COPY           :: 7;
    FOCUS_LOST          :: 8;
    HOTKEY              :: 9;
    KEYUP               :: 10;
    KEYDOWN             :: 11;
    MY_TRAY_CONTEXT_COMMAND :: 12;
    MY_TRAY :: 13;
}

Key_Current_State :: enum_flags u32 {
    NONE  :: 0x0;
    DOWN  :: 0x1;
    START :: 0x4;
    END   :: 0x8;
}

// We reserve 32 buttons for each gamepad.
GAMEPAD_BUTTON_COUNT :: 32;

Key_Code :: enum u32 {
    UNKNOWN :: 0;

    // Non-textual keys that have placements in the ASCII table
    // (and thus in Unicode):

    BACKSPACE   :: 8;
    TAB         :: 9;
    LINEFEED    :: 10;
    ENTER       :: 13;
    ESCAPE      :: 27;
    SPACEBAR    :: 32;

    // The letters A-Z live in here as well and may be returned
    // by keyboard events.
    
    DELETE      :: 127;

    ARROW_UP    :: 128;
    ARROW_DOWN  :: 129;
    ARROW_LEFT  :: 130;
    ARROW_RIGHT :: 131;

    PAGE_UP     :: 132;
    PAGE_DOWN   :: 133;

    HOME        :: 134;
    END         :: 135;

    INSERT      :: 136;

    PAUSE       :: 137;
    SCROLL_LOCK :: 138;
    
    ALT;
    CTRL;
    SHIFT;
    
    F1;         
    F2;
    F3;
    F4;
    F5;
    F6;
    F7;
    F8;
    F9;
    F10;
    F11;
    F12;
    F13;
    F14;
    F15;
    F16;
    F17;
    F18;
    F19;
    F20;
    F21;
    F22;
    F23;
    F24;

    PRINT_SCREEN;

    MOUSE_BUTTON_LEFT;
    MOUSE_BUTTON_MIDDLE;
    MOUSE_BUTTON_RIGHT;

    MOUSE_WHEEL_UP;
    MOUSE_WHEEL_DOWN;

    // We reserve button codes for up to 4 gamepads.
    GAMEPAD_0_BEGIN;
    GAMEPAD_0_END :: GAMEPAD_0_BEGIN + xx GAMEPAD_BUTTON_COUNT;
    GAMEPAD_1_BEGIN;
    GAMEPAD_1_END :: GAMEPAD_1_BEGIN + xx GAMEPAD_BUTTON_COUNT;
    GAMEPAD_2_BEGIN;
    GAMEPAD_2_END :: GAMEPAD_2_BEGIN + xx GAMEPAD_BUTTON_COUNT;
    GAMEPAD_3_BEGIN;
    GAMEPAD_3_END :: GAMEPAD_3_BEGIN + xx GAMEPAD_BUTTON_COUNT;

    // WARNING!
    //
    // We make an array whose size is controlled
    // by the last enum value in this array, so if you make
    // really big values to match Unicode code points, our
    // memory usage will become quite sorry.
    //
    //                               -jblow, 19 March 2017
    //
}

// Modifier_Flags used to use #place, but I rewrote it to use a union
// instead .... it is not necessarily clearer though! So I am switching
// it back for now...

Event :: struct {
    Modifier_Flags :: union {
        // Eventually we'd like the *_pressed modifiers to be 1 bit each,
        // but still be nameable as booleans. But for now they're 1 byte each.
        // You can compare them as a u32 using the 'packed' member.

        struct {
            // @@ This is confusing. Below key_pressed means the key was just pressed, here _pressed means the key is held down.
            shift_pressed := false;   // Only set for Event_Type.KEYBOARD.
            ctrl_pressed  := false;   // Only set for Event_Type.KEYBOARD.
            alt_pressed   := false;
            dummy         := false;
        }
        
        packed: u32 = 0;
    }
    
    type : Event_Type = Event_Type.UNINITIALIZED;

    // If keyboard event:
    key_pressed : u32 = 0;  // If not pressed, it's a key release.
    key_code : Key_Code = Key_Code.UNKNOWN;

    using modifier_flags: Modifier_Flags;

    utf32 : u32 = 0;  // If TEXT_INPUT.
    repeat := false;  // If KEYBOARD event.
    
    typical_wheel_delta: s32;  // Used only for mouse events.
    wheel_delta: s32;          // Used only for mouse events.

    files: [] string;  // Used only for drag and drop events. Heap-allocated, lives until events are reset for the next frame.

    mycode: int;
}

// Per-frame mouse deltas:
mouse_delta_x: int;
mouse_delta_y: int;
mouse_delta_z: int;

events_this_frame:   [..] Event;
input_button_states: [NUM_BUTTON_STATES] Key_Current_State;

input_application_has_focus := false;

NUM_BUTTON_STATES :: #run enum_highest_value(Key_Code) + 1;

Window_Resize_Record :: struct {
    window: Window_Type;
    width:  s32;
    height: s32;
}

Window_Move_Record :: struct {
    window: Window_Type;
    x: s32;
    y: s32;
}

get_window_resizes :: () -> [] Window_Resize_Record {
    // The return value here will stick around in memory until the next call
    // to get_window_resizes (from any thread. Actually this whole module does
    // not deal with threading, so don't do that!)
    
    if resizes_to_free  array_reset(*resizes_to_free);
    
    if !pending_resizes return .[];

    array_copy(*resizes_to_free, pending_resizes);
    pending_resizes.count = 0;
    return resizes_to_free;
}

get_window_moves :: () -> [] Window_Move_Record {
    // See notes on get_window_resizes. This works the same way.
    if moves_to_free  array_reset(*moves_to_free);

    if !pending_moves return .[];

    array_copy(*moves_to_free, pending_moves);
    pending_moves.count = 0;
    return moves_to_free;
}

is_a_window_resized :: () -> bool, Window_Resize_Record #deprecated "Use get_window_resizes instead." {
    // Note: If the user never calls this routine, pending_resizes may grow without bound!
    // Maybe we should clean this up so that it only stores one record per window, max.
    
    // @Robustness: Do we want to make it easier for the application by consolidating
    // multiple resizes of the same window, so there's only one?
    dummy: Window_Resize_Record = ---;
    if !pending_resizes.count return false, dummy;
    return true, pop(*pending_resizes);
}

has_a_window_moved :: () -> bool, Window_Move_Record #deprecated "Use get_window_moves instead." {
    // Note: If the user never calls this routine, pending_moves may grow without bound!

    // @Robustness: Do we want to make it easier for the application by consolidating
    // multiple resizes of the same window, so there's only one?
    dummy: Window_Move_Record = ---;
    if !pending_moves.count return false, dummy;
    return true, pop(*pending_moves);
}

input_per_frame_event_and_flag_update :: () {
    // Called once per frame, probably.
    array_reset(*events_this_frame);
    
    mask     := ~Key_Current_State.START;
    end_mask := ~(Key_Current_State.END | .DOWN | .START);
    // @Speed: Could just keep a list of who is not currently set.
    for * input_button_states {
        if (<<it & .END) {
            <<it &= end_mask;
        } else {
            <<it &= mask;
        }
    }

    mouse_delta_x = 0;
    mouse_delta_y = 0;
    mouse_delta_z = 0;
}

#scope_module

pending_moves:   [..] Window_Move_Record;
moves_to_free:   [..] Window_Move_Record;

pending_resizes: [..] Window_Resize_Record;
resizes_to_free: [..] Window_Resize_Record;

#import "Basic";
#import "Window_Type";

