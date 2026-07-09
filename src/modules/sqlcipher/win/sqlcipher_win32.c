#include <windows.h>
#include <bcrypt.h>
#include <stdlib.h>
#include <string.h>
#include "sqlite3.h"

#pragma comment(lib, "bcrypt.lib")

#ifndef SQLITE_OK
#define SQLITE_OK 0
#endif
#ifndef SQLITE_ERROR
#define SQLITE_ERROR 1
#endif

#define SQLCIPHER_DECRYPT 0
#define SQLCIPHER_ENCRYPT 1
#define SQLCIPHER_HMAC_SHA1 0
#define SQLCIPHER_HMAC_SHA256 1
#define SQLCIPHER_HMAC_SHA512 2
#define SQLCIPHER_PBKDF2_HMAC_SHA1 0
#define SQLCIPHER_PBKDF2_HMAC_SHA256 1
#define SQLCIPHER_PBKDF2_HMAC_SHA512 2

typedef struct sqlcipher_provider sqlcipher_provider;
struct sqlcipher_provider {
  int (*init)(void);
  void (*shutdown)(void);
  const char* (*get_provider_name)(void *ctx);
  int (*add_random)(void *ctx, const void *buffer, int length);
  int (*random)(void *ctx, void *buffer, int length);
  int (*hmac)(void *ctx, int algorithm, const unsigned char *hmac_key, int key_sz, const unsigned char *in, int in_sz, const unsigned char *in2, int in2_sz, unsigned char *out);
  int (*kdf)(void *ctx, int algorithm, const unsigned char *pass, int pass_sz, const unsigned char* salt, int salt_sz, int workfactor, int key_sz, unsigned char *key);
  int (*cipher)(void *ctx, int mode, const unsigned char *key, int key_sz, const unsigned char *iv, const unsigned char *in, int in_sz, unsigned char *out);
  const char* (*get_cipher)(void *ctx);
  int (*get_key_sz)(void *ctx);
  int (*get_iv_sz)(void *ctx);
  int (*get_block_sz)(void *ctx);
  int (*get_hmac_sz)(void *ctx, int algorithm);
  int (*ctx_init)(void **ctx);
  int (*ctx_free)(void **ctx);
  int (*fips_status)(void *ctx);
  const char* (*get_provider_version)(void *ctx);
  sqlcipher_provider *next;
};

static int win32_hmac_sz(void *ctx, int algorithm);

static LPCWSTR hash_alg(int algorithm) {
  switch(algorithm) {
    case SQLCIPHER_HMAC_SHA1: return BCRYPT_SHA1_ALGORITHM;
    case SQLCIPHER_HMAC_SHA256: return BCRYPT_SHA256_ALGORITHM;
    case SQLCIPHER_HMAC_SHA512: return BCRYPT_SHA512_ALGORITHM;
    default: return NULL;
  }
}

static int win32_add_random(void *ctx, const void *buffer, int length) { return SQLITE_OK; }
static int win32_random(void *ctx, void *buffer, int length) {
  return BCryptGenRandom(NULL, (PUCHAR)buffer, (ULONG)length, BCRYPT_USE_SYSTEM_PREFERRED_RNG) == 0 ? SQLITE_OK : SQLITE_ERROR;
}

static int win32_hmac(void *ctx, int algorithm, const unsigned char *hmac_key, int key_sz, const unsigned char *in, int in_sz, const unsigned char *in2, int in2_sz, unsigned char *out) {
  BCRYPT_ALG_HANDLE alg = NULL;
  BCRYPT_HASH_HANDLE hash = NULL;
  DWORD obj_len = 0, cb = 0;
  PUCHAR obj = NULL;
  LPCWSTR name = hash_alg(algorithm);
  NTSTATUS st;
  if(!name || !in) return SQLITE_ERROR;
  st = BCryptOpenAlgorithmProvider(&alg, name, NULL, BCRYPT_ALG_HANDLE_HMAC_FLAG);
  if(st) goto fail;
  st = BCryptGetProperty(alg, BCRYPT_OBJECT_LENGTH, (PUCHAR)&obj_len, sizeof(obj_len), &cb, 0);
  if(st) goto fail;
  obj = (PUCHAR)malloc(obj_len);
  if(!obj) goto fail;
  st = BCryptCreateHash(alg, &hash, obj, obj_len, (PUCHAR)hmac_key, (ULONG)key_sz, 0);
  if(st) goto fail;
  st = BCryptHashData(hash, (PUCHAR)in, (ULONG)in_sz, 0);
  if(st) goto fail;
  if(in2) { st = BCryptHashData(hash, (PUCHAR)in2, (ULONG)in2_sz, 0); if(st) goto fail; }
  st = BCryptFinishHash(hash, out, (ULONG)win32_hmac_sz(ctx, algorithm), 0);
  if(st) goto fail;
  if(hash) BCryptDestroyHash(hash);
  if(alg) BCryptCloseAlgorithmProvider(alg, 0);
  if(obj) free(obj);
  return SQLITE_OK;
fail:
  if(hash) BCryptDestroyHash(hash);
  if(alg) BCryptCloseAlgorithmProvider(alg, 0);
  if(obj) free(obj);
  return SQLITE_ERROR;
}

static int win32_kdf(void *ctx, int algorithm, const unsigned char *pass, int pass_sz, const unsigned char* salt, int salt_sz, int workfactor, int key_sz, unsigned char *key) {
  BCRYPT_ALG_HANDLE alg = NULL;
  LPCWSTR name = hash_alg(algorithm);
  NTSTATUS st;
  if(!name) return SQLITE_ERROR;
  st = BCryptOpenAlgorithmProvider(&alg, name, NULL, BCRYPT_ALG_HANDLE_HMAC_FLAG);
  if(st) return SQLITE_ERROR;
  st = BCryptDeriveKeyPBKDF2(alg, (PUCHAR)pass, (ULONG)pass_sz, (PUCHAR)salt, (ULONG)salt_sz, (ULONGLONG)workfactor, key, (ULONG)key_sz, 0);
  BCryptCloseAlgorithmProvider(alg, 0);
  return st == 0 ? SQLITE_OK : SQLITE_ERROR;
}

static int win32_cipher(void *ctx, int mode, const unsigned char *key, int key_sz, const unsigned char *iv, const unsigned char *in, int in_sz, unsigned char *out) {
  BCRYPT_ALG_HANDLE alg = NULL;
  BCRYPT_KEY_HANDLE hkey = NULL;
  DWORD obj_len = 0, cb = 0, result = 0;
  PUCHAR obj = NULL;
  unsigned char ivbuf[16];
  NTSTATUS st;
  if(key_sz != 32 || !iv || !in || !out) return SQLITE_ERROR;
  memcpy(ivbuf, iv, 16);
  st = BCryptOpenAlgorithmProvider(&alg, BCRYPT_AES_ALGORITHM, NULL, 0);
  if(st) goto fail;
  st = BCryptSetProperty(alg, BCRYPT_CHAINING_MODE, (PUCHAR)BCRYPT_CHAIN_MODE_CBC, sizeof(BCRYPT_CHAIN_MODE_CBC), 0);
  if(st) goto fail;
  st = BCryptGetProperty(alg, BCRYPT_OBJECT_LENGTH, (PUCHAR)&obj_len, sizeof(obj_len), &cb, 0);
  if(st) goto fail;
  obj = (PUCHAR)malloc(obj_len);
  if(!obj) goto fail;
  st = BCryptGenerateSymmetricKey(alg, &hkey, obj, obj_len, (PUCHAR)key, (ULONG)key_sz, 0);
  if(st) goto fail;
  if(mode == SQLCIPHER_ENCRYPT) st = BCryptEncrypt(hkey, (PUCHAR)in, (ULONG)in_sz, NULL, ivbuf, 16, out, (ULONG)in_sz, &result, 0);
  else st = BCryptDecrypt(hkey, (PUCHAR)in, (ULONG)in_sz, NULL, ivbuf, 16, out, (ULONG)in_sz, &result, 0);
  if(st || result != (DWORD)in_sz) goto fail;
  BCryptDestroyKey(hkey); BCryptCloseAlgorithmProvider(alg, 0); free(obj);
  return SQLITE_OK;
fail:
  if(hkey) BCryptDestroyKey(hkey);
  if(alg) BCryptCloseAlgorithmProvider(alg, 0);
  if(obj) free(obj);
  return SQLITE_ERROR;
}

static const char* win32_name(void *ctx) { return "win32-cng"; }
static const char* win32_version(void *ctx) { return "bcrypt"; }
static const char* win32_cipher_name(void *ctx) { return "aes-256-cbc"; }
static int win32_key_sz(void *ctx) { return 32; }
static int win32_iv_sz(void *ctx) { return 16; }
static int win32_block_sz(void *ctx) { return 16; }
static int win32_hmac_sz(void *ctx, int algorithm) {
  switch(algorithm) { case SQLCIPHER_HMAC_SHA1: return 20; case SQLCIPHER_HMAC_SHA256: return 32; case SQLCIPHER_HMAC_SHA512: return 64; default: return 0; }
}
static int win32_ctx_init(void **ctx) { return SQLITE_OK; }
static int win32_ctx_free(void **ctx) { return SQLITE_OK; }
static int win32_fips(void *ctx) { return 0; }

int sqlcipher_win32_setup(sqlcipher_provider *p) {
  p->init = NULL; p->shutdown = NULL; p->get_provider_name = win32_name;
  p->add_random = win32_add_random; p->random = win32_random; p->hmac = win32_hmac; p->kdf = win32_kdf; p->cipher = win32_cipher;
  p->get_cipher = win32_cipher_name; p->get_key_sz = win32_key_sz; p->get_iv_sz = win32_iv_sz; p->get_block_sz = win32_block_sz; p->get_hmac_sz = win32_hmac_sz;
  p->ctx_init = win32_ctx_init; p->ctx_free = win32_ctx_free; p->fips_status = win32_fips; p->get_provider_version = win32_version; p->next = NULL;
  return SQLITE_OK;
}
