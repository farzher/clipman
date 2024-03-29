
#import "Objective_C";
#import "Objective_C/LightweightRenderingView";

#scope_file

App_Delegate :: struct {
    using delegate: NSApplicationDelegate;

    applicationShouldTerminate :: (using self: *App_Delegate, _sel: Selector, sender: id) -> NSApplicationTerminateReply #c_call {
        jai_context: Context;
        push_context jai_context {
            event: Event;
            event.type = Event_Type.QUIT;
            array_add(*osx_externally_generated_events, event);
        }
        return NSTerminateCancel;
    } @selector(applicationShouldTerminate:)

    applicationWillTerminate :: (self: *App_Delegate, _sel: Selector, notification: *NSNotification) #c_call {
        // NSAutoreleasePool.drain(self.application_autorelease_pool);
        // release(self.application_autorelease_pool);
    } @selector(applicationWillTerminate:)

    applicationDidResignActive :: (using self: *App_Delegate, _sel: Selector, notification: *NSNotification) #c_call {
        input_application_has_focus = false;
    } @selector(applicationDidResignActive:)

    applicationDidBecomeActive :: (using self: *App_Delegate, _sel: Selector, notification: *NSNotification) #c_call {
        input_application_has_focus = true;
    } @selector(applicationDidBecomeActive:)

    applicationDidFinishLaunching :: (self: *App_Delegate, _sel: Selector, app: *NSApplication) #c_call {
        ctx: Context;
            push_context ctx {
            NSApplication.setActivationPolicy(NSApp, NSApplicationActivationPolicyRegular);
            NSApplication.activateIgnoringOtherApps(NSApp, YES);
            NSApp.stop(NSApp, null);
        }
    }    

    doNothing :: (using self: *App_Delegate, sel: Selector, obj: id) #c_call {

    } @selector(doNothing:)
}

Window_Delegate :: struct {
    using nsobject: NSObject;

    windowWillClose :: (using self: *Window_Delegate, _sel: Selector, notification: *NSNotification) #c_call {
        jai_context: Context;
        push_context jai_context {
            // win := NSNotification.object(notification);

            event: Event;
            event.type = Event_Type.QUIT;
            array_add(*osx_externally_generated_events, event);
        }
    } @selector(windowWillClose:)

    windowDidMiniaturize :: (using self: *Window_Delegate, _sel: Selector, notification: *NSNotification) #c_call {
        // win := cast(*NSWindow) NSNotification.object(notification);
        window_minimized = true;
    } @selector(windowDidMiniaturize:)

    windowDidDeminiaturize :: (using self: *Window_Delegate, _sel: Selector, notification: *NSNotification) #c_call {
        // win := cast(*NSWindow) NSNotification.object(notification);
        window_minimized = false;
    } @selector(windowDidDeminiaturize:)

    /*
    windowWillResize :: (using self: *Window_Delegate, _sel: Selector, sender: *NSWindow, toSize: NSSize) -> NSSize #c_call {
        push_context jai_context {
            add_resize_record(sender, cast(s32) toSize.width, cast(s32) toSize.height);
            return toSize;
        }
    } @selector(windowDidResize:toSize:)
    */

    windowDidResize :: (using self: *Window_Delegate, _sel: Selector, notification: *NSNotification) #c_call {
        jai_context: Context;
        push_context jai_context {
            my_window := cast(*NSWindow) notification.object(notification);
            view := NSWindow.contentView(my_window);
            frame := NSView.frame(view);
            fb := NSView.convertRectToBacking(view, frame);

            add_resize_record(my_window, cast(s32) frame.size.width, cast(s32) frame.size.height);

            view.drawRect(view, frame);
        }
    } @selector(windowDidResize:)
}

#scope_export

application_initialized := false;


init_mac_app :: () {
    if application_initialized return;

    init_objective_c();

    {
        ad_class := objc_create_class(App_Delegate, NSObject);
        // DO NOT ADD NSApplicationDelegate AS A PROTOCOL HERE!!!!!
        // For whatever reason, on TouchBar macs and for whatever reason
        // only when the program is in a .app bundle, NSApplicationDelegate
        // doesn't exist and thus, this protocol is null.
        // prot := objc_getProtocol("NSApplicationDelegate");
        // class_addProtocol(ad_class, prot);
        objc_add_instance_method(ad_class, App_Delegate.applicationShouldTerminate, "applicationShouldTerminate:");
        objc_add_instance_method(ad_class, App_Delegate.applicationWillTerminate, "applicationWillTerminate:");
        objc_add_instance_method(ad_class, App_Delegate.applicationDidResignActive, "applicationDidResignActive:");
        objc_add_instance_method(ad_class, App_Delegate.applicationDidBecomeActive, "applicationDidBecomeActive:");
        objc_add_instance_method(ad_class, App_Delegate.applicationDidFinishLaunching, "applicationDidFinishLaunching:");
        objc_add_instance_method(ad_class, App_Delegate.doNothing, "doNothing:");
        objc_finalize_class(ad_class);
    }

    {
        wd_class := objc_create_class(Window_Delegate, NSObject);
        objc_add_instance_method(wd_class, Window_Delegate.windowWillClose, "windowWillClose:");
        // objc_add_instance_method(wd_class, Window_Delegate.windowWillResize, "windowWillResize:toSize:");
        objc_add_instance_method(wd_class, Window_Delegate.windowDidResize, "windowDidResize:");
        objc_add_instance_method(wd_class, Window_Delegate.windowDidMiniaturize, "windowDidMiniaturize:");
        objc_add_instance_method(wd_class, Window_Delegate.windowDidDeminiaturize, "windowDidDeminiaturize:");
        objc_finalize_class(wd_class);
    }

    dg := objc_init(objc_alloc(App_Delegate));
    autorelease(dg);

    NSThread.detachNewThreadSelector(selector("doNothing:"), dg, null);

    NSApplication.sharedApplication();

    // pool := objc_init(objc_alloc(NSAutoreleasePool));
    // dg.application_autorelease_pool = pool;

    NSApplication.setDelegate(NSApp, dg);

    menu_bar := objc_init(objc_alloc(NSMenu));
    autorelease(menu_bar);
    NSApp.setMainMenu(NSApp, menu_bar);

    S :: NSString.getTempString;

    app_menu_item := menu_bar.addItemWithTitle(menu_bar, S(""), null, S(""));
    autorelease(app_menu_item);

    app_menu := objc_init(objc_alloc(NSMenu));
    autorelease(app_menu);

    // @TODO we should probably override toggleFullScreen: in NSApplication in order to also set presentation options
    // like we do in toggle_fullscreen
    app_menu.addItemWithTitle(app_menu, S("Enter Full Screen"), selector("toggleFullScreen:"), S("f"));
    app_menu.addItemWithTitle(app_menu, S(tprint("Quit")), selector("terminate:"), S("q"));

    app_menu_item.setSubmenu(app_menu_item, app_menu);

    NSApplication.setAppleMenu(NSApp, app_menu);    
    NSApplication.finishLaunching(NSApp);

    application_initialized = true;
}

create_window :: (width: int, height: int, window_name: string, window_x := 0, window_y := 0, parent: *NSWindow = null) -> *NSWindow {
    if !application_initialized init_mac_app();

    window := NSWindow.initWithContentRect(objc_alloc(NSWindow), NSMakeRect(xx window_x, xx window_y, cast(CGFloat) width, cast(CGFloat) height),
                NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable, NSBackingStoreBuffered, NO);

    // hmm... maybe it would be better if this wasnt kept in the autoreleasepool ?
    autorelease(window);
    NSWindow.setReleasedWhenClosed(window, NO);

    NSWindow.setTitle(window, window_name);

    wd := objc_init(objc_alloc(Window_Delegate));
    autorelease(wd);

    NSWindow.setDelegate(window, wd);
    NSWindow.setCollectionBehavior(window, NSWindowCollectionBehaviorFullScreenPrimary | NSWindowCollectionBehaviorManaged);
    NSWindow.makeKeyAndOrderFront(window, null);

    {
        view := objc_init(objc_alloc(LightweightOpenGLView));
        NSView.setWantsLayer(view, YES);
        NSView.setWantsBestResolutionOpenGLSurface(view, YES);
        autorelease(view);

        NSWindow.setContentView(window, view);
    }

    return window;
}

swap_buffers :: (win: *NSWindow) {
    view := NSWindow.contentView(win);
    if !view return;

    // The view must at least respond to the swapBuffers selector, in order to be compatible.
    LightweightRenderingView.swapBuffers(view);
}


Saved_Window_Info :: struct {
    mask: NSWindowStyleMask;
    window_frame: NSRect;
}


toggle_fullscreen :: (win: *NSWindow, desire_fullscreen: bool, saved: *Saved_Window_Info) -> success: bool, width: s32, height: s32 {
    #if #run AVAILABLE_MACOSX(MACOSX_10_7) {
        view := NSWindow.contentView(win);
        frame := NSView.frame(view);

        mask := NSWindow.styleMask(win);
        if ((mask & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen) && desire_fullscreen return true, cast(s32) frame.size.width, cast(s32) frame.size.height;

        NSWindow.toggleFullScreen(win, win);

        if desire_fullscreen {
            // maybe preserve the current presentation options ?
            // pres := NSApp.presentationOptions(NSApp);
            NSApp.setPresentationOptions(NSApp, NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar);
        } else {
            NSApp.setPresentationOptions(NSApp, NSApplicationPresentationDefault);
        }

        mask2 := NSWindow.styleMask(win);
        frame = NSView.frame(view);
        return (mask2 & NSWindowStyleMaskFullScreen) != (mask & NSWindowStyleMaskFullScreen), cast(s32) frame.size.width, cast(s32) frame.size.height;
    } else {
        if desire_fullscreen {
            saved.mask = NSWindow.styleMask(win);
            saved.window_frame = NSWindow.frame(win);

            NSWindow.setStyleMask(win, NSWindowStyleMaskBorderless);

            pt: NSPoint;
            NSWindow.setFrameOrigin(win, pt);

            screen := NSScreen.mainScreen();
            frame := NSScreen.frame(screen);
            NSWindow.setContentSize(win, frame.size);
            NSWindow.setLevel(win, kCGMainMenuWindowLevel+1);
            
            frame = NSView.frame(NSWindow.contentView(win));
            return true, cast(s32) frame.size.width, cast(s32) frame.size.height;
        } else {
            NSWindow.setStyleMask(win, saved.mask);
            NSWindow.setFrame(win, saved.window_frame, YES);
            NSWindow.setLevel(win, kCGNormalWindowLevel);

            frame := NSView.frame(NSWindow.contentView(win));
            return true, cast(s32) frame.size.width, cast(s32) frame.size.height;
        }
    }
}



get_mouse_pointer_position :: (win: *NSWindow, right_handed: bool) -> x: int, y: int, success: bool {
    pt := NSWindow.mouseLocationOutsideOfEventStream(win);

    if !right_handed {
        // @TODO does this need to change if we have a retina display?
        frame := NSView.frame(NSWindow.contentView(win));
        h := frame.size.height;

        pt.y = h - pt.y;
    }

    return cast(int) pt.x, cast(int) pt.y, true;
}

get_mouse_pointer_position :: inline (right_handed := false) -> x: int, y: int, success: bool {
    if !NSApp return 0, 0, false;

    win := NSApplication.keyWindow(NSApp);
    if !win return 0, 0, false;

    x, y, success := get_mouse_pointer_position(win, right_handed);
    return x, y, success;
}

