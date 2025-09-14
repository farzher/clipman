#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#define HOTKEY_ID 1

// Spawn ClipMan and exit
void SpawnClipManWithArgAndExit(const char* arg) {
    char path[MAX_PATH], dir[MAX_PATH], cmd[MAX_PATH];
    STARTUPINFOA si = {0};
    PROCESS_INFORMATION pi = {0};
    si.cb = sizeof(si);

    GetModuleFileNameA(NULL, path, MAX_PATH);

    lstrcpyA(dir, path);
    for (int i = lstrlenA(dir) - 1; i >= 0; i--) {
        if (dir[i] == '\\') { dir[i+1] = 0; break; }
    }

    lstrcpyA(cmd, dir);
    lstrcatA(cmd, "clipman.exe ");
    lstrcatA(cmd, arg);

    if (CreateProcessA(NULL, cmd, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
    }

    ExitProcess(0);
}

// Minimal window proc for message-only window
LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    if (msg == WM_DESTROY) PostQuitMessage(0);
    return DefWindowProcA(hwnd, msg, wParam, lParam);
}

void WINAPI WinMainCRTStartup(void) {
    MSG msg;
    WNDCLASSA wc = {0};

    wc.lpfnWndProc = WndProc;
    wc.hInstance = GetModuleHandleA(0);
    wc.lpszClassName = "ClipManMsgOnlyClass";
    RegisterClassA(&wc);

    // Create a message-only window (HWND_MESSAGE)
    HWND hwnd = CreateWindowA("ClipManMsgOnlyClass", NULL,
                              0,0,0,0,0, HWND_MESSAGE, NULL, wc.hInstance, NULL);

    // Hotkey and clipboard listener
    RegisterHotKey(NULL, HOTKEY_ID, MOD_ALT, VK_OEM_3);
    AddClipboardFormatListener(hwnd);

    while (GetMessageA(&msg, NULL, 0, 0) > 0) {
        if (msg.message == WM_HOTKEY && msg.wParam == HOTKEY_ID)
            SpawnClipManWithArgAndExit("-spawned_by_watcher");
        else if (msg.message == WM_CLIPBOARDUPDATE)
            SpawnClipManWithArgAndExit("-spawned_by_watcher -copy");

        TranslateMessage(&msg);
        DispatchMessageA(&msg);
    }

    UnregisterHotKey(NULL, HOTKEY_ID);
    ExitProcess(0);
}
