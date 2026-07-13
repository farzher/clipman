// Static libcurl bindings for clipman.
// libcurl_tiny_static.lib comes from curl-8.21.0/dist/curl-tiny-static.

libcurl :: #library,no_dll "win/libcurl_tiny_static";

// Transitive libs used by the Windows static curl build (WinSock, Schannel,
// CryptoAPI). Declaring/using symbols from them makes Jai pass them to the linker.
ws2_32  :: #library,system "ws2_32";
crypt32 :: #library,system "crypt32";
secur32 :: #library,system "secur32";
advapi32 :: #library,system "advapi32";
volatileaccessu :: #library,no_dll "win/volatileaccessu";

CURL :: void;
curl_slist :: struct { data: *u8; next: *curl_slist; }

CURLcode :: enum s32 {
  OK          :: 0;
  FAILED_INIT :: 2;
}

CURLoption :: enum s32 {
  WRITEDATA      :: 10001;
  URL            :: 10002;
  POSTFIELDS     :: 10015;
  HTTPHEADER     :: 10023;
  CUSTOMREQUEST  :: 10036;
  WRITEFUNCTION  :: 20011;
  TIMEOUT        :: 13;
  HEADER         :: 42;
  NOBODY         :: 44;
  FOLLOWLOCATION :: 52;
  SSL_VERIFYPEER :: 64;
  SSL_VERIFYHOST :: 81;
}

CURLINFO :: enum s32 {
  RESPONSE_CODE :: 2097154;
}

curl_easy_init__foreign :: () -> *CURL #foreign libcurl "curl_easy_init";
curl_easy_init :: () -> *CURL {
  force_link_curl_system_libs();
  return curl_easy_init__foreign();
}

curl_easy_setopt    :: (curl: *CURL, option: CURLoption, __args: ..Any) -> CURLcode #foreign libcurl;
curl_easy_perform   :: (curl: *CURL) -> CURLcode #foreign libcurl;
curl_easy_cleanup   :: (curl: *CURL) -> void #foreign libcurl;
curl_easy_getinfo   :: (curl: *CURL, info: CURLINFO, __args: ..Any) -> CURLcode #foreign libcurl;
curl_slist_append   :: (list: *curl_slist, str: *u8) -> *curl_slist #foreign libcurl;
curl_slist_free_all :: (list: *curl_slist) -> void #foreign libcurl;

WSADATA :: struct { data: [512] u8; }
WSAStartup :: (version_requested: u16, data: *WSADATA) -> s32 #foreign ws2_32;
CertCloseStore :: (store: *void, flags: u32) -> s32 #foreign crypt32;
InitSecurityInterfaceA :: () -> *void #foreign secur32;
CryptAcquireContextA :: (prov: **void, container: *u8, provider: *u8, prov_type: u32, flags: u32) -> s32 #foreign advapi32;
RtlSetVolatileMemory :: (dst: *void, value: s32, size: u64) -> *void #foreign volatileaccessu;

force_link_curl_libs_enabled := false;
force_link_curl_system_libs :: () {
  if force_link_curl_libs_enabled {
    wsa: WSADATA;
    WSAStartup(0, *wsa);
    CertCloseStore(null, 0);
    InitSecurityInterfaceA();
    CryptAcquireContextA(null, null, null, 0, 0);
    RtlSetVolatileMemory(null, 0, 0);
  }
}
