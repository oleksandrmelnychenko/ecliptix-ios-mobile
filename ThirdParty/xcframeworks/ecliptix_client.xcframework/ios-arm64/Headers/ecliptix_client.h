#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stddef.h>

#ifdef _WIN32
  #ifdef ECLIPTIX_CLIENT_STATIC
    #define ECLIPTIX_CLIENT_API
  #else
    #ifdef ECLIPTIX_CLIENT_EXPORTS
      #define ECLIPTIX_CLIENT_API __declspec(dllexport)
    #else
      #define ECLIPTIX_CLIENT_API __declspec(dllimport)
    #endif
  #endif
#else
  #define ECLIPTIX_CLIENT_API __attribute__((visibility("default")))
#endif

typedef enum {
    ECLIPTIX_SUCCESS = 0,
    ECLIPTIX_ERROR_INVALID_PARAMS = -1,
    ECLIPTIX_ERROR_CRYPTO_FAILURE = -2,
    ECLIPTIX_ERROR_VERIFICATION_FAILED = -3,
    ECLIPTIX_ERROR_INIT_FAILED = -4
} ecliptix_result_t;

ECLIPTIX_CLIENT_API int ecliptix_client_init(void);

ECLIPTIX_CLIENT_API void ecliptix_client_cleanup(void);

ECLIPTIX_CLIENT_API ecliptix_result_t ecliptix_client_verify(
    const uint8_t* data,
    size_t data_len,
    const uint8_t* signature,
    size_t sig_len
);

ECLIPTIX_CLIENT_API ecliptix_result_t ecliptix_client_encrypt(
    const uint8_t* plaintext,
    size_t plaintext_len,
    uint8_t* ciphertext,
    size_t* ciphertext_len
);

ECLIPTIX_CLIENT_API ecliptix_result_t ecliptix_client_decrypt(
    const uint8_t* ciphertext,
    size_t ciphertext_len,
    uint8_t* plaintext,
    size_t* plaintext_len
);

ECLIPTIX_CLIENT_API ecliptix_result_t ecliptix_client_get_public_key(
    uint8_t* public_key_der,
    size_t* public_key_len
);

ECLIPTIX_CLIENT_API const char* ecliptix_client_get_error(void);

#ifdef __cplusplus
}
#endif