#import,file "../mywindows.jai";
#import "Windows_Utf8";


//
// @Incomplete @Robustness: We should check whichever flags Windows gives us automatically
// in the event data (e.g. is control held, is shift held, etc)... rather than maintaining
// our own per-frame state... the "is ctrl held down" variables should just be informational
// to the outside user.
//

window_minimized := false; // @@ Hack.


//#scope_export

get_key_code :: (wParam: WPARAM) -> Key_Code {
    if (wParam >= 48) && (wParam <= 90) return cast(Key_Code) wParam;
    
    using Key_Code;

    if wParam == VK_SPACE   return xx 32;

    // @Incomplete: Convert this to if wParam == { ... }. Or even a lookup table of some kind.
    if wParam == VK_HOME  return HOME;
    if wParam == VK_END   return END;

    if wParam == VK_PAUSE        return PAUSE;
    if wParam == VK_SCROLL       return SCROLL_LOCK;
    
    if wParam == VK_PRIOR
        return PAGE_UP;
    if wParam == VK_NEXT
        return PAGE_DOWN;
    if wParam == VK_LEFT
        return ARROW_LEFT;
    if wParam == VK_RIGHT
        return ARROW_RIGHT;
    if wParam == VK_UP
        return ARROW_UP;
    if wParam == VK_DOWN
        return ARROW_DOWN;
    if wParam == VK_MENU
        return ALT;
    if wParam == VK_SHIFT
        return SHIFT;
    if wParam == VK_CONTROL
        return CTRL;
    if wParam == VK_BACK
        return BACKSPACE;
    if wParam == VK_DELETE
        return DELETE;
    if wParam == VK_INSERT
        return INSERT;
    if wParam == VK_ESCAPE
        return ESCAPE;
    if wParam == VK_RETURN
        return ENTER;
    if wParam == VK_TAB
        return TAB;

    if wParam == VK_OEM_1  // Sigh.
        return xx #char ";";
    if wParam == VK_OEM_2  // Sigh.
        return xx #char "/";
    if wParam == VK_OEM_3
        return xx #char "`";
    if wParam == VK_OEM_4
        return xx #char "[";
    if wParam == VK_OEM_5
        return xx #char "\\";
    if wParam == VK_OEM_6
        return xx #char "]";
    if wParam == VK_OEM_7
        return xx #char "'";

    if wParam == VK_OEM_PLUS    return xx #char "+";
    if wParam == VK_OEM_MINUS   return xx #char "-";
    if wParam == VK_OEM_PERIOD  return xx #char ".";
    if wParam == VK_OEM_COMMA   return xx #char ",";
    
    if (wParam >= VK_F1) && (wParam <= VK_F16) {
        delta := wParam - VK_F1;
        return xx(F1 + xx delta);
    }
    if wParam == VK_SNAPSHOT
        return PRINT_SCREEN;

    return UNKNOWN;
}

get_vk :: (key: Key_Code) -> VK: u64 {
    using Key_Code;

    if (key >= xx 48) && (key <= xx 90) return cast(u64) key;
    
    if key == xx 32            return  VK_SPACE;

    if key == PAGE_UP          return VK_PRIOR;
    if key == PAGE_DOWN        return VK_NEXT;

    if key == ARROW_LEFT       return VK_LEFT;
    
    if key == ARROW_RIGHT      return VK_RIGHT; 
    
    if key == ARROW_UP         return VK_UP;
    
    if key == ARROW_DOWN       return VK_DOWN;
    
    if key == ALT              return VK_MENU;
    if key == SHIFT            return VK_SHIFT;
    
    if key == CTRL             return VK_CONTROL;
    
    if key == BACKSPACE        return VK_BACK;
    
    if key == DELETE           return VK_DELETE;
    if key == INSERT           return VK_INSERT;
    
    if key == ESCAPE           return VK_ESCAPE;
    
    if key == ENTER            return VK_RETURN;
    
    if key == TAB              return VK_TAB;

    if key == xx #char ";"     return VK_OEM_1;
    if key == xx #char "/"     return VK_OEM_2;
    if key == xx #char "`"     return VK_OEM_3;
    if key == xx #char "["     return VK_OEM_4;
    if key == xx #char "\\"    return VK_OEM_5;
    if key == xx #char "]"     return VK_OEM_6;
    if key == xx #char "'"     return VK_OEM_7;
    
    if key == xx #char "+"     return VK_OEM_PLUS;
    if key == xx #char "-"     return VK_OEM_MINUS;
    if key == xx #char "."     return VK_OEM_PERIOD;
    if key == xx #char ","     return VK_OEM_COMMA;

    if (key >= F1) && (key <= F16) {
        delta := key - F1;
        return xx(VK_F1 + xx delta);
    }

    if key == PRINT_SCREEN  return VK_SNAPSHOT;

    return 0;
}


MyWindowProc :: (hwnd: HWND, message: u32,
                 wParam: WPARAM, lParam: LPARAM) -> s64 #c_call {
    new_context: Context;

    WMAPP_NOTIFYCALLBACK :: WM_APP + 1; // xxx
    push_context new_context {
        using Key_Code;

  	    if message == {
            // xxx
          case WM_CONTEXTMENU;
            // i don't think this is used
            log("WM_CONTEXTMENU % % %", message, wParam, lParam);
          case WM_COMMAND;
            event: Event;
            event.type = .MY_TRAY_CONTEXT_COMMAND;
            event.mycode = xx wParam;
            array_add(*events_this_frame, event);
          case WMAPP_NOTIFYCALLBACK;
            event: Event;
            event.type = .MY_TRAY;
            event.mycode = xx lParam;
            array_add(*events_this_frame, event);


          case WM_CLIPBOARDUPDATE;
            event: Event;
            event.type = .CLIP_COPY;
            array_add(*events_this_frame, event);
            return DefWindowProcW(hwnd, message, wParam, lParam);

//          case WM_ERASEBKGND; return 1;
          case WM_SYSCOMMAND;
/*
            if (wParam & 0xfff0) == SC_KEYMENU {
                print("LPARAM %\n", lParam);
                // Ignore the cursed F10 key.
                // @Incomplete: Do we need to generate an event,
                // or do we also get a KEYDOWN for F10?
                return 0;
            }
*/                
	        return DefWindowProcW(hwnd, message, wParam, lParam);
            
          case WM_ACTIVATEAPP;
            if wParam {  // We are being activated.
/*
                // Scan all our keys; if any are pressed, detect whether they are really down.
                // @Incomplete? Notice whether keys are down when we get ACTIVATEAPP?
                for input_button_states {
                    if !(it & DOWN) continue;

                    vk := get_vk(xx it_index);
                    if !vk continue;

                    state := GetKeyState(xx vk);
                    
                    if !(state & 0x8000) {
                        event: Event;
                        event.type = .KEYBOARD;
                        event.key_pressed = 0;
                        event.key_code = xx it_index;
                        event.packed = 0;  // @Temporary: Unions not currently initialized.
                        event.shift_pressed = shift_state;
                        event.ctrl_pressed = ctrl_state;
                        event.alt_pressed = alt_state;
                        array_add(*events_this_frame, event);
                        
                        input_button_states[it_index] = .END;  // Because we shadowed that by Key_Code.END.
                        // @Redundant: It would probably be cleaner
                        // if we just set shift/ctrl/alt state
                        // on each Event based on the state of
                        // these keys in input_button_states[].
                        //          -jblow, 6 May 2017.
                        if vk == VK_SHIFT    shift_state = false;
                        if vk == VK_CONTROL  ctrl_state  = false;
                        if vk == VK_MENU     alt_state   = false;
                    }
                }
*/
            }
	        return DefWindowProcW(hwnd, message, wParam, lParam);

          case WM_SYSKEYDOWN; #through;
          case WM_KEYDOWN;
            // @Refactor: Keydown and Keyup were written to use an array, as
            // below, but later on the buffered system was created for WM_CHAR
            // so maybe these can be rewritten to use that (and we can ditch
            // the arrays)?  It all depends on what functionality we settle
            // on wanting from the arrays...
            
            repeat := ((cast (s32) lParam) & 0x40000000);

            //alt_down := (message == WM_SYSKEYDOWN) && (lParam & (1 << 29)) != 0;

            event: Event;
            event.type = .KEYBOARD;
            event.key_pressed = 1;
            event.key_code = get_key_code(wParam);
            event.packed = 0;
            event.shift_pressed = shift_state;
            event.ctrl_pressed  = ctrl_state;
            event.alt_pressed   = alt_state;
            event.repeat = (repeat != 0);
            
            input_button_states[event.key_code] |= (DOWN | START);

            array_add(*events_this_frame, event);
            
            if wParam == VK_MENU      alt_state   = true;
            if wParam == VK_SHIFT     shift_state = true;
            if wParam == VK_CONTROL   ctrl_state  = true;  // @Cleanup: Look at what I do in the Braid code because this is bananas.

          case WM_SYSKEYUP; #through;
          case WM_KEYUP;
            event: Event;
            event.type = .KEYBOARD;
            event.key_pressed = 0;
            event.key_code = get_key_code(wParam);
            event.packed = 0;  // @Temporary: Unions not currently initialized.
            event.shift_pressed = shift_state;
            event.ctrl_pressed = ctrl_state;
            event.alt_pressed   = alt_state;

            input_button_states[event.key_code] |= .END;  // Because we shadowed that by Key_Code.END.
            
            array_add(*events_this_frame, event);

            if wParam == VK_MENU      alt_state   = false;
            if wParam == VK_SHIFT     shift_state = false;
            if wParam == VK_CONTROL   ctrl_state  = false;
          
          case WM_SYSCHAR;
              // This is here to prevent beeps when a Alt key combo is pressed. If we don't return 0, windows helpfully emits a beep sound to
              // indicate the user that the key wasn't handled.
              
          case WM_CHAR;
            keycode := wParam;

            if keycode > 31 {
                // Control characters generate key codes < 32, but these are redundant
                // with KEYDOWN events and are also ambiguous (ctrl-m generates 13, but
                // so does RETURN.)
                event: Event;
                event.type = .TEXT_INPUT;
                event.utf32 = xx keycode;
                
                array_add(*events_this_frame, event);
            }

          case WM_HOTKEY;
            event: Event;
            event.type = .HOTKEY;
            array_add(*events_this_frame, event);
          case WM_SETFOCUS;
            input_application_has_focus = true;
          case WM_KILLFOCUS;
            input_application_has_focus = false;
            event: Event;
            event.type = .FOCUS_LOST;
            array_add(*events_this_frame, event);
          case WM_PAINT;
		    ValidateRect(hwnd, null);
	        return DefWindowProcW(hwnd, message, wParam, lParam);

          case WM_LBUTTONDOWN; #through;
          case WM_LBUTTONUP;
            event: Event;
            event.type     = .KEYBOARD;
            event.key_code = MOUSE_BUTTON_LEFT;
            
            pressed := false;
            if message == WM_LBUTTONDOWN  {
                pressed = true;
                input_button_states[event.key_code] |= (START | DOWN);
            } else {
                input_button_states[event.key_code] |= .END;  // Because we shadowed that by Key_Code.END.
            }

            event.key_pressed = xx pressed;

            array_add(*events_this_frame, event);

            if message == WM_LBUTTONDOWN SetCapture(hwnd);
            else ReleaseCapture();

          case WM_RBUTTONDOWN; #through;
          case WM_RBUTTONUP;
            event: Event;
            event.type = .KEYBOARD;
            event.key_code = MOUSE_BUTTON_RIGHT;

            pressed := false;
            if message == WM_RBUTTONDOWN {
                pressed = true;
                input_button_states[event.key_code] |= (START | DOWN);
            } else {
                input_button_states[event.key_code] |= .END;  // Because we shadowed that by Key_Code.END.
            }

            event.key_pressed = xx pressed;

            array_add(*events_this_frame, event);

         case WM_MBUTTONDOWN; #through;
         case WM_MBUTTONUP;
            event: Event;
            event.type = .KEYBOARD;
            event.key_code = MOUSE_BUTTON_MIDDLE;

            pressed := false;
            if message == WM_MBUTTONDOWN {
                pressed = true;
                input_button_states[event.key_code] |= (START | DOWN);
            } else {
                input_button_states[event.key_code] |= .END;  // Because we shadowed that by Key_Code.END.
            }

            event.key_pressed = xx pressed;

            array_add(*events_this_frame, event);
            
          case WM_MOUSEMOVE;
            // We don't have mouse move events yet, but we'll record the delta.


            // We use Raw Input for mouse position stuff now.
/*
            x := (lParam & 0xffff);
            y := (lParam >> 16) & 0xffff;
            mouse_delta_x += x - last_mouse_event_x;
            mouse_delta_y += y - last_mouse_event_y;

            last_mouse_event_x = x;
            last_mouse_event_y = y;
*/
          case WM_MOUSEWHEEL;
            event: Event;
            event.type = .MOUSE_WHEEL;
            event.typical_wheel_delta = WHEEL_DELTA;
            event.wheel_delta = xx cast,trunc(s16)(wParam >> 16);
            array_add(*events_this_frame, event);

            mouse_delta_z += event.wheel_delta;
            
          case WM_CLOSE; #through;
          case WM_QUIT;
            event: Event;
            event.type = .QUIT;
            array_add(*events_this_frame, event);
	        return DefWindowProcW(hwnd, message, wParam, lParam);

          case WM_INPUT;
            extra := GetMessageExtraInfo();

            if (extra & 0x82) == 0x82 {
                // @Hack: Ignore touch input! There is no documentation of this
                // that I can see. This is just what I needed to do to filter
                // out fake mouse input generated by WM_TOUCH. I would regard
                // this as extremely fragile and could-break-at-any-time.
            } else {
                process_raw_input(cast(HRAWINPUT)lParam);
            }

            DefWindowProcW(hwnd, message, wParam, lParam);  // This is required for some reason.    // @@ Why?
          case WM_SIZE;
            if wParam == {
              case SIZE_MAXIMIZED;
                window_minimized = false;
                add_resize_record(hwnd);
              case SIZE_RESTORED;
                  if window_minimized window_minimized = false;
                  else add_resize_record(hwnd);
              case SIZE_MINIMIZED;
                  window_minimized = true;
            }
            return 0;
          case WM_MOVE;
            add_move_record(hwnd);
            return 0;
          case WM_EXITSIZEMOVE;
            add_resize_record(hwnd);
            return 0;
          case WM_DPICHANGED;
            y_dpi := (wParam >> 16) & 0xFFFF;
            x_dpi := (wParam)       & 0xFFFF;
            
            rect := cast(*RECT) lParam;

            w := rect.right - rect.left;
            h := rect.bottom - rect.top;

            SetWindowPos(hwnd, HWND_TOPMOST, rect.left, rect.top, w, h, SWP_NOACTIVATE|SWP_NOZORDER);
            return 0;

          case WM_DROPFILES;
            drop := cast(HDROP) wParam;
            // If "0xFFFFFFFF" as the second parameter: return the count of files dropped.
            file_paths_count := DragQueryFileW(drop, 0xFFFFFFFF, null, 0);
            files: [..] string;

            for i: 0..file_paths_count-1 {
                // If nulll as the third parameter: return the length of the path, not counting the trailing '\0'.
                file_name_wide_count := DragQueryFileW(drop, i, null, 0) + 2;
                assert(file_name_wide_count > 0);

                file_name_wide := cast(*u16) alloc(file_name_wide_count * size_of(u16), __temporary_allocator);
                ok := DragQueryFileW(drop, i, file_name_wide, file_name_wide_count);
                assert(ok > 0); // means success

                file_name := wide_to_utf8(file_name_wide);
                array_add(*files, file_name);
            }

            DragFinish(drop);

            event: Event;
            event.type  = .DRAG_AND_DROP_FILES;
            event.files = files;
            array_add(*events_this_frame, event);
            return 0;

          case;
	        return DefWindowProcW(hwnd, message, wParam, lParam);
	    }

        return 0;
    }
}

update_window_events :: () {
    if !initted {
        init_input_system();
        initted = true;
    }
    
    input_per_frame_event_and_flag_update();

    // @Robustness: Maybe do this for all keystrokes that are down? Sigh...
    if alt_state || (input_button_states[Key_Code.ALT] & .DOWN) { // Checking both just to be paranoid about desync between them.
        state := GetAsyncKeyState(VK_MENU);  // GetAsyncKeyState actually checks the key, not to be confused with GetKeyState, which does nothing.
        if !(state & 0x8000) {
            alt_state = false;
            input_button_states[Key_Code.ALT] |= .END;
        }
    }

    if ctrl_state || (input_button_states[Key_Code.CTRL] & .DOWN) { // Checking both just to be paranoid about desync between them.
        state := GetAsyncKeyState(VK_CONTROL);  // GetAsyncKeyState actually checks the key, not to be confused with GetKeyState, which does nothing.
        if !(state & 0x8000) {
            ctrl_state = false;
            input_button_states[Key_Code.CTRL] |= .END;
        }
    }

    if shift_state || (input_button_states[Key_Code.SHIFT] & .DOWN) { // Checking both just to be paranoid about desync between them.
        state := GetAsyncKeyState(VK_SHIFT);  // GetAsyncKeyState actually checks the key, not to be confused with GetKeyState, which does nothing.
        if !(state & 0x8000) {
            shift_state = false;
            input_button_states[Key_Code.SHIFT] |= .END;
        }
    }
    
    while true {
        msg: MSG;

        result := PeekMessageW(*msg, null, 0, 0, PM_REMOVE);
        if !result break;

        // This is how we used to handle Alt+Enter on The Witness:
        // Alt+Enter is not delivered through WM_INPUT, so the combination was handled through WM_(SYS)KEYDOWN messages.
        /*if msg.message == WM_SYSKEYDOWN {
            if msg.wParam == VK_RETURN {

                // Toggle full screen upon alt-enter 
                dwMask :: (1 << 29);
                if (msg.lParam & dwMask) != 0 { // Alt is down also
                    //display->toggle_fullscreen();

                    event: Event;
                    event.type = .KEYBOARD;
                    event.key_pressed = 1;
                    event.key_code = get_key_code(msg.wParam);
                    event.packed = 0;  // @Temporary: Unions not currently initialized.
                    event.shift_pressed = shift_state;
                    event.ctrl_pressed = ctrl_state;
                    event.alt_pressed = true;

                    array_add(*events_this_frame, event);

                    // Do not send this message to the window proc, because that produces beep sound.
                    continue;
                }
            }
        }*/

        // Doing that was also useful to avoid the beeping sound when pressing Alt+key combinations. However, to avoid that 
        // we only need to avoid TranslateMessage. Turns out TranslateMessage enqueues a WM_SYSCHAR message which is the actual
        // culprit of the beeping sound. Handling WM_SYSCHAR in the message handler and returning 0 prevents the default handling
        // of the message and avoids the beep.

        TranslateMessage(*msg);
        DispatchMessageW(*msg);
    }
}

#scope_file

shift_state := false;
ctrl_state  := false;
alt_state   := false;


// Nice tutorial about using raw input for games:
// http://www.toymaker.info/Games/html/raw_input.html

// About Raw Input:
// http://msdn.microsoft.com/en-us/library/ms645543(v=vs.85).aspx#_win32_Registration_for_Raw_Input

// Taking Advantage of High-Definition Mouse Movement:
// http://msdn.microsoft.com/en-us/library/ee418864(v=vs.85).aspx

// Using Raw Input Examples:
// http://msdn.microsoft.com/en-us/library/ms645546(v=vs.85).aspx#standard_read

raw_input_buffer: [..] *u8;
process_raw_input :: (handle: HRAWINPUT) {
    //
    // We currently use Raw Input for mouse events, so that we can get deltas
    // while doing things like tightly constraining the mouse pointer.
    //
    // In The Witness we also used Raw Input for keyboard events, but I am
    // not sure what benefit we got from this. Maybe it's better, I don't know!
    // But for now I am leaving keyboard out of this code.
    //
    //          -jblow, 31 March 2017.

    // IC: We are using raw input, because there are no WM events for some special keys such as PrintScreen.

    dwSize: u32;
    GetRawInputData(handle, RID_INPUT, null, *dwSize, size_of(RAWINPUTHEADER));

    if raw_input_buffer.count < dwSize {
        array_resize(*raw_input_buffer, dwSize);
    }

	written_bytes := GetRawInputData(handle, RID_INPUT, raw_input_buffer.data, *dwSize, size_of(RAWINPUTHEADER));
    assert(written_bytes <= dwSize);        // note that GetRawInputData() is allowed to request a buffer size and then write less bytes than the size

    raw := cast(*RAWINPUT) raw_input_buffer.data;
    
    handled := false;
    if raw.header.dwType == RIM_TYPEMOUSE {
        mouse := *raw.data.mouse;

        // The docs say to check this flag, but MOUSE_MOVE_RELATIVE
        // is defined as 0? wtf?
        if (mouse.usFlags & MOUSE_MOVE_ABSOLUTE) {
            // @@ What to do if we only receive absolute coordinates? To do proper motions we need to know when the pen touches the tablet and when is it lifted.
            //mouse_delta_x += cast(int)((mouse.lLastX - mouse_abs_x) * 0.01);
            //mouse_delta_y += cast(int)((mouse.lLastY - mouse_abs_y) * 0.01);
            //mouse_abs_x = mouse.lLastX;
            //mouse_abs_y = mouse.lLastY;
        } else {
            mouse_delta_x += mouse.lLastX;
            mouse_delta_y += mouse.lLastY;
        }
    } else if raw.header.dwType == RIM_TYPEKEYBOARD {
        is_left  := (raw.data.keyboard.Flags & RI_KEY_E0)    != 0;
        is_right := (raw.data.keyboard.Flags & RI_KEY_E1)    != 0;
        is_down  := (raw.data.keyboard.Flags & RI_KEY_BREAK) == 0;
        
        vkey    := raw.data.keyboard.VKey;
        raw_key := raw.data.keyboard.MakeCode;

        handle_keyboard_event(is_left, is_right, is_down, vkey, raw_key);
    }
}

handle_keyboard_event :: (is_left: bool, is_right: bool, is_down: bool, vkey: u16, raw_key: u16) -> handled:bool {
    // @@ IC: Here we only care about the PRINT SCREEN key, because there's no WM message for it.
    if vkey != VK_SNAPSHOT return false;

    key_code := get_key_code(vkey);

    repeat := is_down && (input_button_states[key_code] & .DOWN) != 0;

    if is_down {
        input_button_states[key_code] |= (Key_Current_State.DOWN | .START);
    } else {
        input_button_states[key_code] |= .END;
    }

    event: Event;
    event.type = .KEYBOARD;
    event.key_pressed = xx is_down;
    event.key_code = key_code;
    event.packed = 0;
    event.shift_pressed = shift_state;
    event.ctrl_pressed  = ctrl_state;
    event.alt_pressed   = alt_state;
    event.repeat = repeat;
    
    array_add(*events_this_frame, event);

    return true;
}


init_input_system :: () {
    rid: [2]RAWINPUTDEVICE;

    rid[0].usUsagePage = 0x01;
    rid[0].usUsage = 0x02;            // HID mouse
    rid[0].dwFlags = 0;
    // rid[0].hwndTarget = null;

    // IC: We are not using the RIDEV_NOHOTKEYS flag anymore, because it interferes with the Alt-Tab dialog. 
    // This means that we are not blocking the windows logo key and that pressing it will cause the app to loose the focus.
    rid[1].usUsagePage = 0x01;
    rid[1].usUsage = 0x06;            // HID keyboard
    rid[1].dwFlags = 0; //RIDEV_NOHOTKEYS;
    rid[1].hwndTarget = null;


    if RegisterRawInputDevices(rid.data, 2, size_of(RAWINPUTDEVICE)) == 1 {
        // Do nothing.
    } else {
        log_error("Failed to initialize Raw Input.\n");
    }
    
    // @@ Enable/Disable shortcut keys?

    // Disable StickyKeys/etc shortcuts but if the accessibility feature is on, 
    // then leave the settings alone as its probably being usefully used

    sk: STICKYKEYS;
    SystemParametersInfoW(SPI_GETSTICKYKEYS, size_of(STICKYKEYS), *sk, 0);

    tk: TOGGLEKEYS;
    SystemParametersInfoW(SPI_GETTOGGLEKEYS, size_of(TOGGLEKEYS), *tk, 0);

    fk: FILTERKEYS;
    SystemParametersInfoW(SPI_GETFILTERKEYS, size_of(FILTERKEYS), *fk, 0);

    // Disable shortcuts:
    {
        skOff := sk;
        if (skOff.dwFlags & SKF_STICKYKEYSON) == 0 {
            // Disable the hotkey and the confirmation
            skOff.dwFlags &= ~SKF_HOTKEYACTIVE;
            skOff.dwFlags &= ~SKF_CONFIRMHOTKEY;
            skOff.dwFlags &= ~SKF_HOTKEYSOUND;

            result := SystemParametersInfoW(SPI_SETSTICKYKEYS, size_of(STICKYKEYS), *skOff, 0);
            k := result;
        }

        tkOff := tk;
        if (tkOff.dwFlags & TKF_TOGGLEKEYSON) == 0 {
            // Disable the hotkey and the confirmation
            tkOff.dwFlags &= ~TKF_HOTKEYACTIVE;
            tkOff.dwFlags &= ~TKF_CONFIRMHOTKEY;
            tkOff.dwFlags &= ~TKF_HOTKEYSOUND;

            result := SystemParametersInfoW(SPI_SETTOGGLEKEYS, size_of(TOGGLEKEYS), *tkOff, 0);
            k := result;
        }

        fkOff := fk;
        if (fkOff.dwFlags & FKF_FILTERKEYSON) == 0 {
            // Disable the hotkey and the confirmation
            fkOff.dwFlags &= ~FKF_HOTKEYACTIVE;
            fkOff.dwFlags &= ~FKF_CONFIRMHOTKEY;
            fkOff.dwFlags &= ~FKF_HOTKEYSOUND;

            result := SystemParametersInfoW(SPI_SETFILTERKEYS, size_of(FILTERKEYS), *fkOff, 0);
            k := result;
        }
    }
}


initted := false;

WHEEL_DELTA :: 120;

using Key_Current_State;

add_resize_record :: (hwnd: HWND) {
    client_rect: RECT;
    GetClientRect(hwnd, *client_rect);

    record: *Window_Resize_Record;
    for * pending_resizes {
        if it.window == hwnd {
            record = it;
            break;
        }
    }

    if !record {
        record = array_add(*pending_resizes);
    }

    record.window = hwnd;
    record.width  = client_rect.right;
    record.height = client_rect.bottom;
}

add_move_record :: (hwnd: HWND) {
    client_rect: RECT;
    GetWindowRect(hwnd, *client_rect);

    record: *Window_Move_Record;
    for * pending_moves {
        if it.window == hwnd {
            record = it;
            break;
        }
    }

    if !record {
        record = array_add(*pending_moves);
    }

    record.window = hwnd;
    record.x = client_rect.left;
    record.y = client_rect.top;
}




