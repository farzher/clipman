using #import "Clipboard";

#if OS == .WINDOWS {

    #import,file "mywindows.jai";
    #import "Basic";

    os_clipboard_get_file :: (hwnd: HWND) -> [..]string {
        files: [..] string;
        files.allocator = temp;

        if !IsClipboardFormatAvailable(CF_HDROP) return files;

        if !OpenClipboard(hwnd) return files;
        defer CloseClipboard();

        hData := GetClipboardData(CF_HDROP);
        nfiles := DragQueryFileA(hData, 0xFFFFFFFF, null, 0);
        for i: 0..nfiles-1 {
            length := DragQueryFileA(hData, i, null, 0);
            path := talloc_string(xx length + 1);
            DragQueryFileA(hData, i, path.data, xx path.count);
            path.count = length;
            array_add(*files, path);
        }

        return files;
    }

    os_clipboard_set_file :: (hwnd: HWND, path: string) {
        if !OpenClipboard(hwnd) return;
        defer CloseClipboard();

        EmptyClipboard();

        size: int = size_of(DROPFILES) + path.count + 2/*ends with two zero bytes*/;
        hGlobal := GlobalAlloc(GMEM_MOVEABLE, xx size);
        df: *DROPFILES = cast(*DROPFILES) GlobalLock(hGlobal);
        defer GlobalUnlock(hGlobal);

        memset(df, 0, size);
        df.pFiles = size_of(DROPFILES);
        df.fWide = .FALSE;
        memcpy(df+1, path.data, path.count);
        SetClipboardData(CF_HDROP, hGlobal);
    }

    os_clipboard_get_bitmap :: (hwnd: HWND) -> string {
        if !IsClipboardFormatAvailable(CF_DIB) return "";

        if !OpenClipboard(hwnd) return "";
        defer CloseClipboard();

        cb_hnd := GetClipboardData(CF_DIB);
        if !cb_hnd then return "";

        size := GlobalSize(cb_hnd);
        data := GlobalLock(cb_hnd);
        defer GlobalUnlock(cb_hnd);

        bytes := talloc_string(xx size);
        memcpy(bytes.data, data, bytes.count);
        return bytes;
    }

    os_clipboard_set_bitmap :: (hwnd: HWND, bytes: string) {
        if !OpenClipboard(hwnd) return;
        defer CloseClipboard();

        EmptyClipboard();

        hMem := GlobalAlloc(GMEM_SHARE, xx bytes.count);
        GlobalLock(hMem);
        defer GlobalUnlock(hMem);

        memcpy(hMem, bytes.data, bytes.count);

        SetClipboardData(CF_DIB, hMem);
    }
}

