using #import "Windows";

MOD_ALT      :: 0x0001;
MOD_CONTROL  :: 0x0002;
MOD_SHIFT    :: 0x0004;
MOD_WIN      :: 0x0008;
MOD_NOREPEAT :: 0x4000;

WM_HOTKEY                       :: 0x0312;
WM_CLIPBOARDUPDATE              :: 0x031D;

SetForegroundWindow :: (hwnd: HWND) -> BOOL #foreign user32;
SetFileTime :: (file: HANDLE, lpCreationTime: *FILETIME, lpLastAccessTime: *FILETIME, lpLastWriteTime: *FILETIME) -> BOOL #foreign kernel32;


SetLayeredWindowAttributes :: (hwnd: HWND, crkey: COLORREF, balpha: u8, dwflags: DWORD) -> BOOL #foreign user32;
LWA_ALPHA    :: 0x02;

TPM_BOTTOMALIGN :: 0x0020;
TPM_LEFTALIGN :: 0x0000;
CreatePopupMenu :: () -> HMENU #foreign user32;
TrackPopupMenu :: (hmenu: HMENU, uflags: u32, x: s32, y: s32, nreserved: s32, hwnd: HWND, prcrect: *RECT) -> BOOL #foreign user32;
InsertMenuW :: (hmenu: HMENU, uposition: u32, uflags: u32, uidnewitem: u64, lpnewitem: LPCWSTR) -> BOOL #foreign user32;


GetMessageW :: (lpMsg: *MSG, hwnd: HWND, wMsgFilterMin: u32, wMsgFilterMax: u32) -> BOOL #foreign user32;
WaitMessage :: () -> BOOL #foreign user32;

KEYEVENTF_KEYUP :: 0x0002;

MF_BYPOSITION :: 0x00000400;
MF_STRING :: 0x00000000;
MF_CHECKED :: 0x00000008;

TPM_RETURNCMD :: 0x0100;

INPUT :: struct {
    type: enum DWORD {
        INPUT_MOUSE;
        INPUT_KEYBOARD;
        INPUT_HARDWARE;
    };
    union {
        mi: MOUSEINPUT;
        ki: KEYBDINPUT;
        hi: HARDWAREINPUT;
    }
}
MOUSEINPUT :: struct {
    dx         : s32; // LONG
    dy         : s32; // LONG
    mouseData  : DWORD;
    dwFlags    : DWORD;
    time       : DWORD;
    dwExtraInfo: u64; // ULONG_PTR
}
KEYBDINPUT :: struct {
    wVk        : u16; // WORD
    wScan      : u16; // WORD
    dwFlags    : DWORD;
    time       : DWORD;
    dwExtraInfo: u64; // ULONG_PTR
}
HARDWAREINPUT :: struct {
    uMsg   : DWORD;
    wParamL: u16; // WORD
    wParamH: u16; // WORD
}


RegisterHotKey :: (hwnd: HWND, id: s32, fsModifiers: u32, vk: u32) -> BOOL #foreign user32;
SendInput :: (cInputs: u32, pInputs: *INPUT, cbSize: s32) -> u32 #foreign user32;
SetFocus :: (hwnd: HWND) -> HWND #foreign user32;

AddClipboardFormatListener :: (hwnd: HWND) -> HANDLE #foreign user32;

DROPFILES :: struct {
    pFiles: DWORD;
    pt: POINT;
    fNC: BOOL;
    fWide: BOOL;
}

IsClipboardFormatAvailable :: (uFormat: u32) -> BOOL #foreign user32;

COLORREF :: DWORD;
DragQueryFileA :: (hDrop: HDROP, iFire: u32, lpszFile: LPSTR, cch: u32) -> u32 #foreign shell32;

WM_APP :: 0x8000;

Shell_NotifyIconA :: (dwMessage: DWORD, lpData: *NOTIFYICONDATA) -> BOOL #foreign shell32;
NOTIFYICONDATA :: struct {
  cbSize: DWORD;
  hWnd: HWND  ;
  uID: u32  ;
  uFlags: u32  ;
  uCallbackMessage: u32  ;
  hIcon: HICON ;
  szTip: [128]u8;
  dwState: DWORD ;
  dwStateMask: DWORD ;
  szInfo: [256]u8;
  union {
    uTimeout: u32;
    uVersion: u32;
  }
  szInfoTitle: [64]u8;
  dwInfoFlags: DWORD;
  guidItem: GUID;
  hBalloonIcon: HICON;
}

NIF_MESSAGE :: 0x01;
NIF_ICON    :: 0x02;
NIF_TIP     :: 0x04;
NIF_SHOWTIP :: 0x80;

NIM_ADD :: 0x00;
NIM_DELETE :: 0x02;
NIM_SETVERSION :: 0x04;

DwmFlush :: () -> HRESULT #foreign Dwmapi;


GlobalSize :: (hMem: HGLOBAL) -> SIZE_T #foreign kernel32;

ShellExecuteA :: (hwnd: HWND, lpOperation: *u8, lpFile: *u8, lpParmeters: *u8, lpDirectory: *u8, nShowCmd: int) -> s32 #foreign shell32;

VkKeyScanA :: (ch: u8) -> u16 #foreign user32;

GetWindowTextA :: (hWnd: HWND, lpString: LPSTR, nMaxCount: s32) -> s32 #foreign user32;
CreateFontW :: (cHeight: s32, cWidth: s32, cEscapement: s32, cOrientation: s32, cWeight: s32, bItalic: DWORD, bUnderline: DWORD, bStrikeOut: DWORD, iCharSet: DWORD, iOutPrecision: DWORD, iClipPrecision: DWORD, iQuality: DWORD, iPitchAndFamily: DWORD, pszFaceName: LPCWSTR) -> HANDLE #foreign gdi;
SendMessageW :: (hWnd: HWND, Msg: u32, wParam: WPARAM, lParam: LPARAM) -> LRESULT #foreign user32;
EnableWindow :: (hWnd: HWND, bEnable: BOOL) -> BOOL #foreign user32;
IsWindow :: (hWnd: HWND) -> BOOL #foreign user32;

// Registry
REGSAM :: u32;

HKEY_CURRENT_USER : HKEY : xx 0x80000001;
KEY_ALL_ACCESS : REGSAM : 0xF003F;
KEY_READ : REGSAM : 0x20019;
ERROR_SUCCESS :: 0;

RegOpenKeyExA    :: (hKey: HKEY, lpSubKey: *u8, ulOptions: DWORD, samDesired: REGSAM, phkResult: *HKEY) -> s32 #foreign Advapi32;
RegSetValueExA   :: (hKey: HKEY, lpValueName: *u8, reserved: DWORD, dwType: DWORD, lpData: *u8, cbData: DWORD) -> s32 #foreign Advapi32;
RegDeleteValueA  :: (hKey: HKEY, lpValueName: *u8) -> s32 #foreign Advapi32;
RegQueryValueExA :: (hKey: HKEY, lpValueName: *u8, lpReserved: *DWORD, lpType: *DWORD, lpData: *u8, lpcbData: *DWORD) -> s32 #foreign Advapi32;
RegCloseKey      :: (hKey: HKEY) -> s32 #foreign Advapi32;

#scope_file
kernel32 :: #system_library "kernel32";
user32   :: #system_library "user32";
shell32  :: #system_library "shell32";
gdi      :: #system_library "Gdi32";
Dwmapi   :: #system_library "Dwmapi";
Advapi32 :: #system_library "Advapi32";
