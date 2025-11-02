#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Візибіліті для iOS/Clang та Windows */
#if defined(_WIN32) || defined(_WIN64)
#  ifdef OPAQUE_CLIENT_BUILD
#    define OPAQUE_API __declspec(dllexport)
#  else
#    define OPAQUE_API __declspec(dllimport)
#  endif
#else
#  ifdef OPAQUE_CLIENT_BUILD
#    define OPAQUE_API __attribute__((visibility("default")))
#  else
#    define OPAQUE_API
#  endif
#endif

/* ------------------------------------------------------------
 * C API (точно як у client_exports.cpp)
 * ------------------------------------------------------------ */

/* Версія бібліотеки (zero-terminated ASCII) */
OPAQUE_API const char* opaque_client_get_version(void);

/* Створення клієнта з даним публічним ключем серверу */
OPAQUE_API int  opaque_client_create(const uint8_t* server_public_key,
                                     size_t key_length,
                                     void** handle);

/* Створення клієнта з вшитим (hardcoded) ключем серверу */
OPAQUE_API int  opaque_client_create_default(void** handle);

/* Звільнення клієнта */
OPAQUE_API void opaque_client_destroy(void* handle);

/* Створення/звільнення стану клієнтської сесії */
OPAQUE_API int  opaque_client_state_create(void** handle);
OPAQUE_API void opaque_client_state_destroy(void* handle);

/* Реєстрація (крок 1): сформувати registration request */
OPAQUE_API int  opaque_client_create_registration_request(void* client_handle,
                                                          const uint8_t* password,
                                                          size_t password_length,
                                                          void* state_handle,
                                                          uint8_t* request_out,
                                                          size_t request_length);

/* Реєстрація (крок 2): фіналізувати, отримати record (envelope+client_pk) */
OPAQUE_API int  opaque_client_finalize_registration(void* client_handle,
                                                    const uint8_t* response,
                                                    size_t response_length,
                                                    void* state_handle,
                                                    uint8_t* record_out,
                                                    size_t record_length);

/* Аутентифікація (крок 1): згенерувати KE1 */
OPAQUE_API int  opaque_client_generate_ke1(void* client_handle,
                                           const uint8_t* password,
                                           size_t password_length,
                                           void* state_handle,
                                           uint8_t* ke1_out,
                                           size_t ke1_length);

/* Аутентифікація (крок 3): згенерувати KE3 у відповідь на KE2 */
OPAQUE_API int  opaque_client_generate_ke3(void* client_handle,
                                           const uint8_t* ke2,
                                           size_t ke2_length,
                                           void* state_handle,
                                           uint8_t* ke3_out,
                                           size_t ke3_length);

/* Завершити протокол та отримати сесійний ключ */
OPAQUE_API int  opaque_client_finish(void* client_handle,
                                     void* state_handle,
                                     uint8_t* session_key_out,
                                     size_t session_key_length);

/* Усі функції повертають 0 при успіху; ненульові коди означають помилку.
 * Буфери out_* можуть бути більші за мінімально необхідні розміри. */

#ifdef __cplusplus
} /* extern "C" */
#endif
