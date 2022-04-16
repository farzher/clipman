using #import "Clipboard";

#if OS == .WINDOWS {

    #import "mywindows";
    #import "Basic";  // For alloc.

    os_clipboard_get_file :: (hwnd: HWND) -> [..]string {
        files: [..] string;
        files.allocator = __temporary_allocator;

        if !IsClipboardFormatAvailable(CF_HDROP) return files;

        if !OpenClipboard(hwnd) return files;
        defer CloseClipboard();

        hData := GetClipboardData(CF_HDROP);
        GlobalLock(hData);
        defer GlobalUnlock(hData);

        nfiles := DragQueryFileA(hData, 0xFFFFFFFF, null, 0);
        for i: 0..nfiles-1 {
            str := talloc_string(1024*4/*idk*/);
            DragQueryFileA(hData, i, str.data, xx str.count);
            array_add(*files, to_string(str.data));
        }

        return files;
    }

    os_clipboard_set_file :: (hwnd: HWND, path: string) {
        if !OpenClipboard(hwnd) return;

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

        CloseClipboard();
    }

    os_clipboard_get_bitmap :: (hwnd: HWND) -> string {
        if !IsClipboardFormatAvailable(CF_DIB) return "";

        if !OpenClipboard(hwnd) return "";
        defer CloseClipboard();

        cb_hnd := GetClipboardData(CF_DIB);
        if !cb_hnd then return "";

        GlobalLock(cb_hnd);
        defer GlobalUnlock(cb_hnd);

        bmpinfo: *BITMAPINFO = cb_hnd;
        w := bmpinfo.bmiHeader.biWidth;
        h := bmpinfo.bmiHeader.biHeight;
        bisize := bmpinfo.bmiHeader.biSize;
        bitcount := bmpinfo.bmiHeader.biBitCount;

        bytes := talloc_string(size_of(BITMAPINFO) + w * h * (bitcount/8));
        memcpy(bytes.data, cb_hnd, bytes.count);

        return bytes;
    }

    os_clipboard_set_bitmap :: (hwnd: HWND, bytes: string) {
        if !OpenClipboard(hwnd) return;

        EmptyClipboard();

        hMem := GlobalAlloc(GMEM_SHARE, xx bytes.count);
        GlobalLock(hMem);
        defer GlobalUnlock(hMem);

        memcpy(hMem, bytes.data, bytes.count);

        SetClipboardData(CF_DIB, hMem);

        CloseClipboard();
    }
}

