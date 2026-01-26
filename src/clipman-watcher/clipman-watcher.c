// install visual studio c++ build tools
// open x64 Native Tools Command Prompt for VS 2019
// you have to open this special command prompt otherwise the cl command doesn't work properly .....
// compile the program:
// cl clipman-watcher.c /Os /GS- /GL /Gy /link /ENTRY:WinMainCRTStartup /SUBSYSTEM:WINDOWS /OPT:REF /OPT:ICF /INCREMENTAL:NO user32.lib kernel32.lib && editbin /RELEASE clipman-watcher.exe

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#define HOTKEY_ID 1

static HWND g_wnd = NULL;

#pragma function(memset)
void* memset(void* dest,int c,size_t count) {
  char* bytes=(char*)dest;
  while(count--) *bytes++=(char)c;
  return dest;
}

static void SpawnClipManWithArgAndExit(const char* arg) {
  char path[MAX_PATH],dir[MAX_PATH],cmd[MAX_PATH];
  STARTUPINFOA si={0};
  PROCESS_INFORMATION pi={0};

  // Release
  UnregisterHotKey(NULL,HOTKEY_ID);
  RemoveClipboardFormatListener(g_wnd);

  // Focus
  HWND hForegroundWnd=GetForegroundWindow();
  DWORD dwForegroundThread=GetWindowThreadProcessId(hForegroundWnd,NULL);
  DWORD dwMyThread=GetCurrentThreadId();

  if(dwForegroundThread!=dwMyThread) {
    AttachThreadInput(dwForegroundThread,dwMyThread,TRUE);

    ShowWindow(g_wnd,SW_SHOW);
    SetForegroundWindow(g_wnd);
    SetFocus(g_wnd);

    AttachThreadInput(dwForegroundThread,dwMyThread,FALSE);
  }

  // Clear keys
  INPUT inputs[3]={0};
  inputs[0].type=INPUT_KEYBOARD; inputs[0].ki.wVk=VK_CONTROL;
  inputs[1].type=INPUT_KEYBOARD; inputs[1].ki.wVk=VK_CONTROL; inputs[1].ki.dwFlags=KEYEVENTF_KEYUP;
  inputs[2].type=INPUT_KEYBOARD; inputs[2].ki.wVk=VK_MENU;    inputs[2].ki.dwFlags=KEYEVENTF_KEYUP;
  SendInput(3,inputs,sizeof(INPUT));

  // Build cmdline
  GetModuleFileNameA(NULL,path,MAX_PATH);
  lstrcpyA(dir,path);
  for(int i=lstrlenA(dir)-1;i>=0;i--) {
    if(dir[i]=='\\') { dir[i+1]=0; break; }
  }

  lstrcpyA(cmd,dir);
  lstrcatA(cmd,"clipman.exe ");
  lstrcatA(cmd,arg);

  si.cb=sizeof(si);
  si.dwFlags=STARTF_USESHOWWINDOW;
  si.wShowWindow=SW_SHOW;

  // Launch
  if(CreateProcessA(NULL,cmd,NULL,NULL,FALSE,0,NULL,NULL,&si,&pi)) {
    WaitForInputIdle(pi.hProcess,5000);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
  }

  ExitProcess(0);
}

static LRESULT CALLBACK WndProc(HWND hwnd,UINT msg,WPARAM wParam,LPARAM lParam) {
  if(msg==WM_DESTROY) PostQuitMessage(0);
  return DefWindowProcA(hwnd,msg,wParam,lParam);
}

void WINAPI WinMainCRTStartup(void) {
  // Single instance
  HANDLE hMutex=CreateMutexA(NULL,FALSE,"MUTEX_clipman-watcher");
  if(!hMutex||GetLastError()==ERROR_ALREADY_EXISTS) ExitProcess(0);

  MSG msg;
  WNDCLASSA wc={0};
  wc.lpfnWndProc=WndProc;
  wc.hInstance=GetModuleHandleA(0);
  wc.lpszClassName="ClipManWatcherClass";
  RegisterClassA(&wc);

  // Hidden window
  g_wnd=CreateWindowExA(
    WS_EX_TOOLWINDOW,
    "ClipManWatcherClass",
    NULL,
    WS_POPUP,
    -32000,-32000,1,1,
    NULL,NULL,wc.hInstance,NULL
  );

  // Hotkey
  if(!RegisterHotKey(NULL,HOTKEY_ID,MOD_ALT,VK_OEM_3)) ExitProcess(1);

  // Clipboard
  AddClipboardFormatListener(g_wnd);

  while(GetMessageA(&msg,NULL,0,0)>0) {
    if(msg.message==WM_HOTKEY&&msg.wParam==HOTKEY_ID) {
      SpawnClipManWithArgAndExit("-spawned_by_watcher");
    } else if(msg.message==WM_CLIPBOARDUPDATE) {
      SpawnClipManWithArgAndExit("-spawned_by_watcher -copy");
    }

    TranslateMessage(&msg);
    DispatchMessageA(&msg);
  }

  // Cleanup
  UnregisterHotKey(NULL,HOTKEY_ID);
  ExitProcess(0);
}
