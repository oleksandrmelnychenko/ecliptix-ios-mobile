# Ecliptix iOS Migration Status

## Overview
Step-by-step migration of Ecliptix desktop application (.NET/C#/Avalonia) to iOS (Swift/SwiftUI).

**Started**: 2025-10-20
**Status**: In Progress - Foundation Complete
**Completion**: ~20% (Foundation + Cryptography)

---

## ✅ Completed Migrations

### Phase 1: Foundation & Project Setup
- [x] iOS project structure with Swift Package Manager
- [x] Modular architecture (Core, Security, Networking, Authentication)
- [x] Protocol Buffer definitions (17 .proto files)
- [x] Basic SwiftUI views (Splash, Welcome, SignIn, Registration, Main)
- [x] Build infrastructure (Makefile, proto generation script)
- [x] Documentation (README, SETUP, MIGRATION_GUIDE)

**Commit**: `f3440a6` - Initial iOS project setup

### Phase 2: Core Types & Storage Layer
- [x] **Result<T, E>** type with extensions
- [x] **Option<T>** type (Rust-style optionality)
- [x] **Unit** type (void result)
- [x] **ServiceFailure** error types
- [x] **Logger** protocol + DefaultLogger (os.Logger)
- [x] **KeychainStorage** - iOS Keychain wrapper
- [x] **EncryptedFileStorage** - File encryption with Data Protection
- [x] **ApplicationSecureStorageProvider** - Main storage provider

**C# Source**: `Ecliptix.Core/Infrastructure/Data/SecureStorage/ApplicationSecureStorageProvider.cs`
**Swift Target**: `Packages/EcliptixSecurity/Sources/Storage/`

**Commit**: `d0e1347` - Secure storage layer migration

#### Storage Strategy Comparison

| Aspect | Desktop (C#) | iOS (Swift) |
|--------|--------------|-------------|
| API | Microsoft DataProtection | Keychain + Data Protection |
| Keys | File-based persistence | iOS Keychain (hardware-backed) |
| Data | Encrypted files | Encrypted files + Keychain |
| Encryption | BouncyCastle | CryptoKit (ChaChaPoly) |
| Location | `~/.ecliptix/` | App Support + Keychain |

### Phase 3: Cryptographic Primitives
- [x] **CryptographicConstants** - All crypto constants
- [x] **AESGCMCrypto** - AES-GCM encryption/decryption
  - encryptWithNonceAndAD()
  - decryptWithNonceAndAD()
- [x] **X25519KeyExchange** - Curve25519 key agreement
  - Raw byte interfaces for protobuf
- [x] **HKDFKeyDerivation** - HKDF-SHA256
  - deriveChainAndMessageKey()
  - deriveRootAndChainKeys()
  - deriveMetadataEncryptionKey()
- [x] **RSAChunkEncryptor** - RSA chunk encryption
  - 120-byte plaintext → 256-byte ciphertext chunks
- [x] **CertificatePinningService** - iOS Security framework wrapper
- [x] **CryptographicHelpers** - SHA256, constant-time compare, secure wipe

**C# Sources**:
- `Ecliptix.Protocol.System/Core/EcliptixProtocolSystem.cs` (AES-GCM)
- `Ecliptix.Utilities/Constants.cs` (Constants)
- `Ecliptix.Utilities/CryptographicHelpers.cs` (Helpers)
- `Ecliptix.Core/Infrastructure/Security/Crypto/RsaChunkEncryptor.cs` (RSA)

**Swift Target**: `Packages/EcliptixSecurity/Sources/Crypto/`

**Commit**: `2141dad` - Cryptographic primitives migration

#### Cryptography Mapping

| Component | Desktop (C#) | iOS (Swift) |
|-----------|--------------|-------------|
| AES-GCM | System.Security.Cryptography.AesGcm | CryptoKit.AES.GCM |
| X25519 | Sodium/libsodium | CryptoKit.Curve25519 |
| HKDF | BouncyCastle / Custom | CryptoKit.HKDF<SHA256> |
| RSA | BouncyCastle | Security (SecKey) |
| SHA256 | System.Security.Cryptography.SHA256 | CryptoKit.SHA256 |

**Key Sizes**:
- AES Key: 32 bytes (256-bit)
- AES Nonce: 12 bytes
- AES Tag: 16 bytes
- X25519 Keys: 32 bytes
- Ed25519 Keys: 32 bytes (public), 64 bytes (secret)

---

## 🚧 In Progress

### Phase 4: Protocol & Envelope System
Currently analyzing and preparing to migrate:

- [ ] **EnvelopeBuilder** utilities
  - CreateEnvelopeMetadata()
  - CreateSecureEnvelope()
  - EncryptMetadata() / DecryptMetadata()
  - ParseEnvelopeMetadata()

**C# Source**: `Ecliptix.Protocol.System/Utilities/EnvelopeBuilder.cs`

---

## 📋 Pending Migrations

### Phase 5: Ratcheting & Protocol State
- [ ] **RatchetChainKey** - Key ratcheting for forward secrecy
- [ ] **EcliptixProtocolConnection** - Connection state management
- [ ] **EcliptixProtocolChainStep** - Chain stepping
- [ ] **ProtocolStateStorage** - Secure protocol state persistence

**C# Sources**:
- `Ecliptix.Protocol.System/Core/EcliptixProtocolConnection.cs`
- `Ecliptix.Protocol.System/Core/EcliptixProtocolChainStep.cs`
- `Ecliptix.Core/Infrastructure/Security/Storage/SecureProtocolStateStorage.cs`

### Phase 6: OPAQUE Protocol
- [ ] **OpaqueClient** - OPAQUE registration and authentication
- [ ] **OpaqueRegistration** flow
- [ ] **OpaqueAuthentication** flow
- [ ] **OpaqueEnvelope** handling

**C# Source**: Desktop app OPAQUE implementation (needs to be located)

### Phase 7: gRPC & Network Layer
- [ ] **GRPCChannelManager** - Channel lifecycle management
- [ ] **GRPCInterceptors** - Auth, logging, retry
- [ ] **NetworkConnectivityMonitor** - NWPathMonitor wrapper
- [ ] **RetryPolicyExecutor** - Exponential backoff

**C# Sources**:
- `Ecliptix.Infrastructure/Network/` (various files)

### Phase 8: gRPC Service Clients
- [ ] **MembershipServiceClient**
  - OpaqueRegistrationInit/Complete
  - OpaqueSignInInit/Complete
  - Logout
- [ ] **AuthVerificationServiceClient**
  - InitiateVerification (streaming)
  - VerifyOtp
  - ValidateMobileNumber
- [ ] **DeviceServiceClient**
  - RegisterDevice
  - EstablishSecureChannel
  - RestoreSecureChannel

**C# Sources**: `Ecliptix.Infrastructure/Network/Services/`

### Phase 9: ViewModels & Business Logic
- [ ] **SignInViewModel**
- [ ] **RegistrationViewModel**
- [ ] **PasswordRecoveryViewModel**
- [ ] **OTPVerificationViewModel**

**C# Sources**: `Ecliptix.Features.Authentication/ViewModels/`

### Phase 10: UI & Views (Enhanced)
- [ ] Enhanced authentication views
- [ ] PassPhrase display view
- [ ] Secure key confirmation view
- [ ] Mobile verification view
- [ ] OTP entry view
- [ ] Password recovery flow
- [ ] Network status banner
- [ ] Bottom sheet modal system
- [ ] Loading states

**C# Sources**: `Ecliptix.Features.Authentication/Views/`

---

## 📊 Migration Statistics

| Category | Total | Completed | In Progress | Remaining |
|----------|-------|-----------|-------------|-----------|
| Project Setup | 1 | 1 | 0 | 0 |
| Core Types | 7 | 7 | 0 | 0 |
| Storage Layer | 3 | 3 | 0 | 0 |
| Cryptography | 7 | 7 | 0 | 0 |
| Protocol System | 4 | 0 | 1 | 3 |
| OPAQUE | 4 | 0 | 0 | 4 |
| gRPC Layer | 7 | 0 | 0 | 7 |
| Service Clients | 3 | 0 | 0 | 3 |
| ViewModels | 4 | 0 | 0 | 4 |
| UI Components | 10 | 5 | 0 | 5 |
| **TOTAL** | **50** | **23** | **1** | **26** |

**Overall Progress**: ~46% of foundation components complete

---

## 🔑 Key Design Decisions

### 1. Storage Architecture
- **Decision**: Use Keychain for keys, encrypted files for data
- **Rationale**: iOS best practice, hardware-backed security
- **Trade-off**: Slightly different from desktop but more secure

### 2. Cryptography Library
- **Decision**: CryptoKit over OpenSSL/BouncyCastle ports
- **Rationale**: Native, hardware-accelerated, maintained by Apple
- **Trade-off**: Must ensure binary compatibility with desktop

### 3. MVVM Framework
- **Decision**: SwiftUI + Combine (not TCA)
- **Rationale**: Closer to ReactiveUI patterns, less learning curve
- **Trade-off**: Could have used TCA for better state management

### 4. Protocol Buffer Strategy
- **Decision**: Check in generated Swift code (temporarily manual types)
- **Rationale**: Reproducible builds, easier development
- **Trade-off**: Larger repo size

### 5. Error Handling
- **Decision**: Result<T, E> type matching C# patterns
- **Rationale**: Explicit error handling, familiar to C# developers
- **Trade-off**: More verbose than Swift throws

---

## 🎯 Next Steps (Priority Order)

1. **EnvelopeBuilder Migration** (Current)
   - Migrate envelope creation and parsing
   - Metadata encryption/decryption
   - Result code handling

2. **Ratcheting System**
   - Chain key derivation
   - Message key generation
   - Forward secrecy implementation

3. **Protocol State Management**
   - Connection state
   - Ratchet indices
   - Replay protection

4. **OPAQUE Protocol**
   - Most complex cryptographic component
   - Critical for authentication

5. **gRPC Service Clients**
   - Network communication
   - Service implementations

---

## 📝 Notes & Observations

### Challenges Encountered
1. ✅ **Solved**: iOS Keychain vs file-based key storage
   - Solution: Hybrid approach (Keychain + encrypted files)

2. ✅ **Solved**: AES-GCM vs ChaCha20-Poly1305
   - Desktop uses AES-GCM
   - iOS CryptoKit has both
   - Decision: Use AES.GCM for compatibility

3. 🚧 **In Progress**: Protocol Buffer code generation
   - Need `protoc`, `protoc-gen-swift`, `protoc-gen-grpc-swift`
   - Currently using manual type definitions
   - Will integrate generated code later

### iOS-Specific Considerations
- Background execution limitations
- App lifecycle management
- Keychain access after device restart
- Data Protection levels
- Biometric authentication integration (future)

### Testing Strategy
- Unit tests for crypto primitives (critical!)
- Test vectors from desktop app
- Integration tests for storage
- UI tests for authentication flows

---

## 📚 Resources & References

- Desktop Repo: `/home/user/ecliptix-desktop`
- iOS Repo: `/home/user/ecliptix-ios`
- Migration Guide: `MIGRATION_GUIDE.md`
- Setup Instructions: `SETUP.md`

**Key Files to Reference**:
- C# Constants: `Ecliptix.Utilities/Constants.cs`
- C# Crypto System: `Ecliptix.Protocol.System/Core/EcliptixProtocolSystem.cs`
- C# Storage: `Ecliptix.Core/Infrastructure/Data/SecureStorage/`
- Proto Definitions: `Protos/**/*.proto`

---

## 🤝 Commit History

| Commit | Date | Description |
|--------|------|-------------|
| `f3440a6` | 2025-10-20 | Initial iOS project setup with Protocol Buffers |
| `d0e1347` | 2025-10-20 | Migrate secure storage layer from C# to Swift |
| `2141dad` | 2025-10-20 | Migrate cryptographic primitives from C# to Swift |

---

**Last Updated**: 2025-10-20
**Next Milestone**: Complete Protocol System & Envelope handling
