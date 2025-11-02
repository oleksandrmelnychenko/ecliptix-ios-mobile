#ifndef OPAQUE_CLIENT_C_H
#define OPAQUE_CLIENT_C_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Constants from OPAQUE protocol
#define OPAQUE_PRIVATE_KEY_LENGTH 32
#define OPAQUE_PUBLIC_KEY_LENGTH 32
#define OPAQUE_MASTER_KEY_LENGTH 32
#define OPAQUE_NONCE_LENGTH 32
#define OPAQUE_MAC_LENGTH 64
#define OPAQUE_HASH_LENGTH 64
#define OPAQUE_ENVELOPE_LENGTH 176
#define OPAQUE_REGISTRATION_REQUEST_LENGTH 32
#define OPAQUE_REGISTRATION_RESPONSE_LENGTH 96
#define OPAQUE_CREDENTIAL_REQUEST_LENGTH 96
#define OPAQUE_CREDENTIAL_RESPONSE_LENGTH 208
#define OPAQUE_KE1_LENGTH 96
#define OPAQUE_KE2_LENGTH 336
#define OPAQUE_KE3_LENGTH 64

// Result codes
typedef enum {
    OPAQUE_SUCCESS = 0,
    OPAQUE_INVALID_INPUT = -1,
    OPAQUE_CRYPTO_ERROR = -2,
    OPAQUE_MEMORY_ERROR = -3,
    OPAQUE_VALIDATION_ERROR = -4,
    OPAQUE_AUTHENTICATION_ERROR = -5,
    OPAQUE_INVALID_PUBLIC_KEY = -6
} opaque_result_t;

// Opaque handle types (forward declarations)
typedef void* opaque_client_handle_t;
typedef void* opaque_client_state_handle_t;

/**
 * Create OPAQUE client instance with server's public key
 * @param server_public_key Server's public key (32 bytes)
 * @param key_length Length of public key (must be 32)
 * @param handle Output handle to created client
 * @return OPAQUE_SUCCESS on success, error code otherwise
 */
int opaque_client_create(
    const uint8_t* server_public_key,
    size_t key_length,
    opaque_client_handle_t* handle
);

/**
 * Create OPAQUE client with default hardcoded server key (for testing)
 * @param handle Output handle to created client
 * @return OPAQUE_SUCCESS on success, error code otherwise
 */
int opaque_client_create_default(opaque_client_handle_t* handle);

/**
 * Destroy OPAQUE client instance and free resources
 * @param handle Client handle to destroy
 */
void opaque_client_destroy(opaque_client_handle_t handle);

/**
 * Create client state handle for tracking registration/authentication session
 * @param handle Output handle to created state
 * @return OPAQUE_SUCCESS on success, error code otherwise
 */
int opaque_client_state_create(opaque_client_state_handle_t* handle);

/**
 * Destroy client state handle and securely wipe memory
 * @param handle State handle to destroy
 */
void opaque_client_state_destroy(opaque_client_state_handle_t handle);

/**
 * Step 1 of Registration: Create registration request
 * @param client_handle Client handle
 * @param secure_key User's password/secure key
 * @param secure_key_length Length of secure key
 * @param state_handle State handle to track session
 * @param request_out Output buffer for registration request (32 bytes)
 * @param request_length Length of output buffer (must be >= 32)
 * @return OPAQUE_SUCCESS on success, error code otherwise
 */
int opaque_client_create_registration_request(
    opaque_client_handle_t client_handle,
    const uint8_t* secure_key,
    size_t secure_key_length,
    opaque_client_state_handle_t state_handle,
    uint8_t* request_out,
    size_t request_length
);

/**
 * Step 2 of Registration: Finalize registration with server response
 * @param client_handle Client handle
 * @param response Server's registration response (96 bytes)
 * @param response_length Length of response (must be >= 96)
 * @param master_key Client's master key (32 bytes)
 * @param master_key_length Length of master key (must be 32)
 * @param state_handle State handle from step 1
 * @param record_out Output buffer for registration record (208 bytes: envelope + public key)
 * @param record_length Length of output buffer (must be >= 208)
 * @return OPAQUE_SUCCESS on success, error code otherwise
 */
int opaque_client_finalize_registration(
    opaque_client_handle_t client_handle,
    const uint8_t* response,
    size_t response_length,
    const uint8_t* master_key,
    size_t master_key_length,
    opaque_client_state_handle_t state_handle,
    uint8_t* record_out,
    size_t record_length
);

/**
 * Step 1 of Authentication: Generate KE1 message
 * @param client_handle Client handle
 * @param secure_key User's password/secure key
 * @param secure_key_length Length of secure key
 * @param state_handle State handle to track authentication session
 * @param ke1_out Output buffer for KE1 message (96 bytes)
 * @param ke1_length Length of output buffer (must be >= 96)
 * @return OPAQUE_SUCCESS on success, error code otherwise
 */
int opaque_client_generate_ke1(
    opaque_client_handle_t client_handle,
    const uint8_t* secure_key,
    size_t secure_key_length,
    opaque_client_state_handle_t state_handle,
    uint8_t* ke1_out,
    size_t ke1_length
);

/**
 * Step 2 of Authentication: Generate KE3 message from server's KE2
 * @param client_handle Client handle
 * @param ke2 Server's KE2 message (336 bytes)
 * @param ke2_length Length of KE2 (must be >= 336)
 * @param state_handle State handle from step 1
 * @param ke3_out Output buffer for KE3 message (64 bytes)
 * @param ke3_length Length of output buffer (must be >= 64)
 * @return OPAQUE_SUCCESS on success, error code otherwise
 */
int opaque_client_generate_ke3(
    opaque_client_handle_t client_handle,
    const uint8_t* ke2,
    size_t ke2_length,
    opaque_client_state_handle_t state_handle,
    uint8_t* ke3_out,
    size_t ke3_length
);

/**
 * Step 3 of Authentication: Extract session key and master key
 * @param client_handle Client handle
 * @param state_handle State handle from previous steps
 * @param session_key_out Output buffer for session key (64 bytes)
 * @param session_key_length Length of session key buffer (must be >= 64)
 * @param master_key_out Output buffer for master key (32 bytes)
 * @param master_key_length Length of master key buffer (must be 32)
 * @return OPAQUE_SUCCESS on success, error code otherwise
 */
int opaque_client_finish(
    opaque_client_handle_t client_handle,
    opaque_client_state_handle_t state_handle,
    uint8_t* session_key_out,
    size_t session_key_length,
    uint8_t* master_key_out,
    size_t master_key_length
);

/**
 * Get library version string
 * @return Version string (e.g., "1.0.0")
 */
const char* opaque_client_get_version(void);

#ifdef __cplusplus
}
#endif

#endif // OPAQUE_CLIENT_C_H
