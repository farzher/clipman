#import "X11";

get_key_code :: (key: KeySym) -> Key_Code {
    using Key_Code;
    
    if key == XK_Left
        return ARROW_LEFT;
    if key == XK_Right
        return ARROW_RIGHT;
    if key == XK_Up
        return ARROW_UP;
    if key == XK_Down
        return ARROW_DOWN;
    if (key == XK_Shift_L) || (key == XK_Shift_R)
        return SHIFT;
    if key == XK_Escape
        return ESCAPE;
    if key == XK_Return
        return ENTER;
    if (key == XK_Control_L) || (key == XK_Control_R) 
        return CTRL;
    if key == XK_BackSpace
        return BACKSPACE;
    if key == XK_Delete
        return DELETE;
    if key == XK_Tab
        return TAB;
    if key == XK_F1
        return F1;
    if key == XK_F2
        return F2;
    if key == XK_F3
        return F3;
    if key == XK_F4
        return F4;
    if key == XK_F5
        return F5;
    if key == XK_F6
        return F6;
    if key == XK_F7
        return F7;
    if key == XK_F8
        return F8;
    if key == XK_F9
        return F9;
    if key == XK_F10
        return F10;
    if key == XK_F11
        return F11;
    if key == XK_F12
        return F12;
    if key == XK_F13
        return F13;
    if key == XK_F14
        return F14;
    if key == XK_F15
        return F15;
    if key == XK_F16
        return F16;

    key = key & 0xFF;
    if (key >= #char "a") && (key <= #char "z") return cast(Key_Code) (key - 0x20);

    return UNKNOWN;
}


#scope_file

update_x11_window_events :: () {
    using Key_Code;

    input_per_frame_event_and_flag_update();

    dpy := x_global_display;
    XLockDisplay(dpy);
    while XPending(dpy) {
        xev: XEvent;
        XNextEvent(dpy, *xev);

        if xev.type == {

          case ClientMessage;
            message := xev.xclient.message_type;
            if message == x_global_wm_protocols {
                message0 := cast(Atom) xev.xclient.data.l[0];

                // This can't be a switch, because the values are not constant!
                // Except come on guys, every single implementation of X11 in the universe
                // is going to agree on these values. Why are we pretending they are not constant?
                // How about if we just look them up once and then hardcode them into this program?
                // We'd save startup time...

                if message0 == x_global_wm_delete_window {
                    event: Event;
                    event.type = .QUIT;
                    array_add(*events_this_frame, event);
                }
            } else if message == XdndEnter {
                /*
                Just pretend like we accept everything. Dude I don't even know.
                if xev.xclient.data.l[1] & 1 {
                    // More than three types, so look in XdndTypeList.
                } else {
                    // Only three types, check three in turn and stop when we find
                    // the one we support.
                }
                */
            } else if message == XdndPosition {
            } else if message == XdndStatus {
            } else if message == XdndTypeList {
            } else if message == XdndActionCopy {
            } else if message == XdndDrop {
            } else if message == XdndLeave {
            } else if message == XdndFinished {
            } else if message == XdndSelection {
            } else if message == XdndProxy {
            }
        case KeyPress;
            event: Event;

            shift: u32;
            if xev.xkey.state & ShiftMask
                shift = 1;
            if xev.xkey.state & ControlMask
                event.ctrl_pressed = true;
            if xev.xkey.state & Mod1Mask
                event.alt_pressed = true;

            keysym := XkbKeycodeToKeysym(dpy, xx xev.xkey.keycode, 0, 0 /* English lowercase group*/);
            event.type = Event_Type.KEYBOARD;
            event.key_pressed = 1;
            event.key_code = get_key_code(keysym);
            event.shift_pressed = cast(bool) shift;

            input_button_states[event.key_code] = (Key_Current_State.START | Key_Current_State.DOWN);
            
            array_add(*events_this_frame, event);

            keysym = XkbKeycodeToKeysym(dpy, xx xev.xkey.keycode, 0, shift);
            if (keysym < XK_BackSpace || keysym > XK_Hyper_R) && !event.ctrl_pressed {
                //WM_CHAR equivalent
                char_event: Event;
                char_event.type = Event_Type.TEXT_INPUT;
                char_event.utf32 = xx keysym; // luckily most Xkb keys are directly mapped to Unicode characters @FixME which keys dont map to utf32 ??

                array_add(*events_this_frame, char_event);
            }
        case KeyRelease;
            // For some odd reason X11 generates KeyRelease followed by a near identical KeyPress to simulate repeat events so we have to filter that out
            if XEventsQueued(dpy, QueuedAfterReading) {
                nev: XEvent;
                XPeekEvent(dpy, *nev);

                if nev.type == KeyPress
                    && nev.xkey.time == xev.xkey.time
                    && nev.xkey.keycode == xev.xkey.keycode {

                    // this is a repeat so we pull it out of the queue and ignore the KeyRelease
                    XNextEvent(dpy, *nev);
                    continue;
                }
            }

            event: Event;

            shift: u32;
            if xev.xkey.state & ShiftMask
                shift = 1;
            if xev.xkey.state & ControlMask
                event.ctrl_pressed = true;
            if xev.xkey.state & Mod1Mask
                event.alt_pressed = true;

            keysym := XkbKeycodeToKeysym(dpy, xx xev.xkey.keycode, 0, 0 /* English lowercase group*/);
            event.type = Event_Type.KEYBOARD;
            event.key_pressed = 0;
            event.shift_pressed = cast(bool) shift;
            event.key_code = get_key_code(keysym);

            input_button_states[event.key_code] = Key_Current_State.END;
            
            array_add(*events_this_frame, event);
        case ButtonPress;
            event: Event;
            event.type = Event_Type.KEYBOARD;

            event.key_pressed = 1;
            button := xev.xbutton.button;
            if button == Button1 {
                event.key_code = MOUSE_BUTTON_LEFT;
            } else if button == Button2 {
                event.key_code = MOUSE_BUTTON_MIDDLE;
            } else if button == Button3 {
                event.key_code = MOUSE_BUTTON_RIGHT;
            }

            input_button_states[event.key_code] = (Key_Current_State.START | Key_Current_State.DOWN);

            array_add(*events_this_frame, event);
        case ButtonRelease;
            // it seems that mouse input doesnt generate repeat events so we dont have to peek the queue
            event: Event;
            event.type = Event_Type.KEYBOARD;

            event.key_pressed = 0;
            button := xev.xbutton.button;
            if button == Button1 {
                event.key_code = MOUSE_BUTTON_LEFT;
            } else if button == Button2 {
                event.key_code = MOUSE_BUTTON_MIDDLE;
            } else if button == Button3 {
                event.key_code = MOUSE_BUTTON_RIGHT;
            }

            input_button_states[event.key_code] = Key_Current_State.END;

            array_add(*events_this_frame, event);
        case SelectionRequest;
            selreq := cast(*XSelectionRequestEvent) *xev;

            out: XEvent;
            selnot := cast(*XSelectionEvent) *out;
            selnot.type = SelectionNotify;
            selnot.requestor = selreq.requestor;
            selnot.selection = selreq.selection;
            selnot.target = selreq.target;
            selnot.time = selreq.time;
            selnot.property = None;

            if x_window_is_ours(x_global_display, selreq.owner) {
                if selreq.target == x_global_xa_utf8 {
                    selnot.property = selreq.property;

                    text_data := x_global_clipboard_buffer.text_data;
                    XChangeProperty(selreq.display, selreq.requestor, selreq.property, selreq.target, 8, PropModeReplace,
                                    text_data.data, cast(s32) text_data.count);
                } else if selreq.target == x_global_xa_targets {

                    selnot.property = selreq.property;

                    atoms: [..] Atom;
                    array_add(*atoms, x_global_xa_utf8);
                    array_add(*atoms, x_global_xa_targets);
                    array_add(*atoms, x_global_xa_multiple);
                    if x_global_clipboard_buffer.rgb_data {
                        array_add(*atoms, x_global_image_bmp);
                    }
                    XChangeProperty(selreq.display, selreq.requestor, selreq.property, x_global_xa_atom, 32, PropModeReplace,
                                    xx atoms.data, cast(s32) atoms.count);

                    array_reset(*atoms);
                } else if selreq.target == x_global_image_bmp {
                    #import "stb_image_write";

                    Data :: struct {
                        _context: *Context;
                        data: [..] u8;
                    }

                    write_func :: (_context: *void, _data: *void, size: s32) #c_call {
                        data := cast(*Data) _context;
                        push_context <<data._context {
                            data8 := cast(*u8) _data;
                            for 0..size-1 {
                                array_add(*data.data, data8[it]);
                            }
                        }
                    }

                    data: Data;
                    data._context = *context;
                    w := x_global_clipboard_buffer.width;
                    h := x_global_clipboard_buffer.height;
                    comp: s32 = 3;
                    stride := x_global_clipboard_buffer.pitch;
                    stbi_write_bmp_to_func(write_func, *data, w, h, comp, x_global_clipboard_buffer.rgb_data);

                    selnot.property = selreq.property;
                    XChangeProperty(selreq.display, selreq.requestor, selreq.property, selreq.target, 8, PropModeReplace,
                                    xx data.data.data, cast(s32) data.data.count);

                    array_reset(*data.data);
                } else {
                    // print("GOT REQ: %\n", to_string(XGetAtomName(x_global_display, selreq.target)));
                }
            }

            XSendEvent(selreq.display, selreq.requestor, True, 0, *out);
        case ConfigureNotify;
            config := cast(*XConfigureEvent) *xev;
            add_resize_record(config.window, config.width, config.height);
        case FocusIn;
            input_application_has_focus = true;
        case FocusOut;
            input_application_has_focus = false;
        }
    }
    XUnlockDisplay(dpy);
}
#scope_export

update_window_events :: () {
    new_context: Context;
    new_context.allocator = Context.default_allocator;
    new_context.logger    = Context.default_logger;

    push_context new_context {
        update_x11_window_events();
    }
}

// @Cutnpaste from Input/windows.jai
add_resize_record :: (hwnd: Window, width: s32, height: s32) {
    record: *Window_Resize_Record;
    for * pending_resizes {
        if it.window == hwnd {
            record = it;
            break;
        }
    }

    if !record {
        // This seems to be a common operation.
        // Make an array utility function? That is not wasteful
        // by copying an element?
        dummy: Window_Resize_Record = ---;
        array_add(*pending_resizes, dummy);
        record = *pending_resizes[pending_resizes.count-1];
    }

    record.window = hwnd;
    record.width = width;
    record.height = height;
}

#scope_file

