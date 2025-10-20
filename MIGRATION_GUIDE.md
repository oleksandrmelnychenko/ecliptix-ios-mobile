# Desktop to iOS Migration Guide

This document outlines the step-by-step process for migrating the Ecliptix desktop application (.NET/Avalonia) to iOS (Swift).

## Table of Contents

1. [Overview](#overview)
2. [Technology Mapping](#technology-mapping)
3. [Migration Phases](#migration-phases)
4. [Detailed Migration Steps](#detailed-migration-steps)
5. [Key Differences](#key-differences)
6. [Testing Strategy](#testing-strategy)

## Overview

**Source**: .NET 9.0 + Avalonia UI + ReactiveUI
**Target**: Swift 5.9+ + SwiftUI + Combine
**Estimated Duration**: 14-21 weeks

## Technology Mapping

| Desktop (.NET) | iOS (Swift) | Notes |
|----------------|-------------|-------|
| C# | Swift | Language migration |
| Avalonia XAML | SwiftUI | Declarative UI |
| ReactiveUI | Combine + async/await | Reactive programming |
| gRPC .NET | grpc-swift | Network protocol |
| Protocol Buffers | swift-protobuf | Serialization |
| BouncyCastle | CryptoKit + Custom | Cryptography |
| DataProtection API | Keychain + UserDefaults | Secure storage |
| Serilog | os.Logger | Logging |
| Polly | Custom async retry | Resilience |
| Dependency Injection | Protocol-based DI | Architecture |

## Migration Phases

### Phase 1: Foundation (Weeks 1-2)
✅ **Status**: Complete

- [x] iOS project structure created
- [x] Swift Package Manager modules set up
- [x] Core module protocols defined
- [x] Security module foundation
- [x] Networking module foundation
- [x] Authentication module foundation
- [x] Basic SwiftUI views created

### Phase 2: Protocol Buffers & Models (Week 3)

- [ ] Copy `.proto` files from desktop project
- [ ] Generate Swift models using `swift-protobuf`
- [ ] Create type mappings for custom types
- [ ] Verify serialization/deserialization
- [ ] Add to appropriate packages

**Commands**:
```bash
# Copy proto files
cp -r ../ecliptix-desktop/Protos/* Protos/

# Generate Swift code
protoc --swift_out=Generated --grpc-swift_out=Generated Protos/**/*.proto
```

### Phase 3: Cryptography Implementation (Weeks 4-6)

#### 3.1 Core Cryptographic Primitives

**Desktop Location**: `Ecliptix.Infrastructure/Security/`

Tasks:
- [ ] Implement ChaCha20-Poly1305 using CryptoKit
- [ ] Implement X25519 key exchange (CryptoKit.Curve25519)
- [ ] Port RSA chunk encryption
- [ ] Implement secure random number generation
- [ ] Port password hashing (Argon2)

**Files to migrate**:
- `Ecliptix.Infrastructure/Security/Cryptography/`
- Reference implementation for OPAQUE protocol

#### 3.2 OPAQUE Protocol

**Desktop Location**: `Ecliptix.Infrastructure/Security/Opaque/`

Tasks:
- [ ] Understand the OPAQUE flow in desktop app
- [ ] Port OPAQUE registration flow
- [ ] Port OPAQUE authentication flow
- [ ] Implement secure envelope creation/opening
- [ ] Add comprehensive unit tests

**Critical files**:
```csharp
// Desktop references
Ecliptix.Infrastructure/Security/Opaque/OpaqueService.cs
Ecliptix.Infrastructure/Security/Opaque/OpaqueClient.cs
```

**Swift implementation**:
```swift
// Target location
Packages/EcliptixSecurity/Sources/OPAQUE/
├── OPAQUEClient.swift
├── OPAQUERegistration.swift
├── OPAQUEAuthentication.swift
└── OPAQUEEnvelope.swift
```

#### 3.3 Secure Storage

Tasks:
- [ ] Implement Keychain wrapper for sensitive data
- [ ] Create encrypted UserDefaults for settings
- [ ] Port `ApplicationSecureStorageProvider` logic
- [ ] Implement secure state persistence

**Desktop reference**: `Ecliptix.Infrastructure/Data/Storage/ApplicationSecureStorageProvider.cs`

**Swift implementation**:
```swift
Packages/EcliptixSecurity/Sources/Storage/
├── KeychainStorage.swift
├── SecureUserDefaults.swift
└── ApplicationStorageProvider.swift
```

### Phase 4: Networking Layer (Weeks 7-9)

#### 4.1 gRPC Client Setup

Tasks:
- [ ] Configure grpc-swift with TLS
- [ ] Implement certificate pinning
- [ ] Create channel management
- [ ] Add connection lifecycle handling

#### 4.2 Service Implementations

**Desktop Location**: `Ecliptix.Infrastructure/Network/Services/`

Tasks:
- [ ] Port MembershipService client
- [ ] Port AuthVerificationService client
- [ ] Port DeviceService client
- [ ] Implement streaming support for OTP verification

**Files to migrate**:
```csharp
Ecliptix.Infrastructure/Network/Services/
├── MembershipServiceClient.cs
├── AuthVerificationServiceClient.cs
└── DeviceServiceClient.cs
```

**Swift implementation**:
```swift
Packages/EcliptixNetworking/Sources/Services/
├── MembershipServiceClient.swift
├── AuthVerificationServiceClient.swift
└── DeviceServiceClient.swift
```

#### 4.3 Request Interceptors

**Desktop Location**: `Ecliptix.Infrastructure/Network/Interceptors/`

Tasks:
- [ ] Port authentication token interceptor
- [ ] Port logging interceptor
- [ ] Port error handling interceptor
- [ ] Implement retry interceptor with exponential backoff

#### 4.4 Network Monitoring

Tasks:
- [ ] Implement NWPathMonitor for connectivity
- [ ] Port network status notifications
- [ ] Handle offline scenarios
- [ ] Implement request queue for offline mode

**Desktop reference**: `Ecliptix.Infrastructure/Network/Providers/NetworkConnectivityProvider.cs`

### Phase 5: Authentication Module (Weeks 10-12)

#### 5.1 ViewModels

**Desktop Location**: `Ecliptix.Features.Authentication/ViewModels/`

Tasks:
- [ ] Port SignInViewModel → SwiftUI ObservableObject
- [ ] Port RegistrationViewModel
- [ ] Port PasswordRecoveryViewModel
- [ ] Port OTP verification logic
- [ ] Implement reactive validation

**Files to migrate**:
```csharp
Ecliptix.Features.Authentication/ViewModels/
├── SignInViewModel.cs
├── RegistrationViewModel.cs
├── PasswordRecoveryViewModel.cs
└── AuthenticationViewModel.cs
```

**Swift implementation**:
```swift
Packages/EcliptixAuthentication/Sources/ViewModels/
├── SignInViewModel.swift
├── RegistrationViewModel.swift
├── PasswordRecoveryViewModel.swift
└── OTPVerificationViewModel.swift
```

#### 5.2 Views

**Desktop Location**: `Ecliptix.Features.Authentication/Views/`

Tasks:
- [x] Welcome view (basic version created)
- [x] Sign-in view (basic version created)
- [x] Registration view (basic version created)
- [ ] PassPhrase display view
- [ ] Secure key confirmation view
- [ ] Mobile verification view
- [ ] OTP entry view
- [ ] Password recovery view

### Phase 6: Application State & Modules (Weeks 13-14)

#### 6.1 State Management

**Desktop Location**: `Ecliptix.Application/State/`

Tasks:
- [ ] Port ApplicationState enum
- [ ] Implement state transitions
- [ ] Port state persistence
- [ ] Add state restoration on launch

#### 6.2 Module System

**Desktop Location**: `Ecliptix.Application/Modularity/`

Tasks:
- [ ] Port module loading system
- [ ] Implement message bus (using Combine)
- [ ] Port module priorities
- [ ] Implement eager/lazy loading

**Desktop reference**:
```csharp
Ecliptix.Application/Modularity/
├── IModule.cs
├── ModuleManager.cs
└── IModuleMessageBus.cs
```

### Phase 7: UI Components (Weeks 15-16)

Tasks:
- [ ] Port bottom sheet modal system
- [ ] Port network status banner
- [ ] Port language selector
- [ ] Port custom text fields and buttons
- [ ] Port loading indicators
- [ ] Port error/success notifications

**Desktop reference**: `Ecliptix.UI.Common/Controls/`

### Phase 8: Localization (Week 17)

Tasks:
- [ ] Extract string resources from desktop
- [ ] Create `.strings` files for each language
- [ ] Implement language detection
- [ ] Port language switching logic
- [ ] Test all localized strings

**Desktop reference**: `Ecliptix.Application/Localization/`

### Phase 9: Testing (Weeks 18-19)

#### 9.1 Unit Tests

Tasks:
- [ ] Cryptography tests (CRITICAL)
- [ ] OPAQUE protocol tests
- [ ] ViewModel tests
- [ ] Service client tests
- [ ] Storage tests

#### 9.2 Integration Tests

Tasks:
- [ ] End-to-end authentication flow
- [ ] gRPC service integration
- [ ] Network retry scenarios
- [ ] Offline mode handling

#### 9.3 UI Tests

Tasks:
- [ ] Registration flow
- [ ] Sign-in flow
- [ ] Password recovery flow
- [ ] State transitions

### Phase 10: Deployment (Weeks 20-21)

Tasks:
- [ ] Configure code signing
- [ ] Set up provisioning profiles
- [ ] Configure CI/CD (GitHub Actions / Xcode Cloud)
- [ ] TestFlight beta distribution
- [ ] App Store submission preparation
- [ ] Security audit

## Key Differences: Desktop vs iOS

### 1. UI Paradigm

**Desktop (Avalonia)**:
- Window-based with custom chrome
- Multi-window support
- Mouse and keyboard input

**iOS (SwiftUI)**:
- Full-screen, single-window
- Navigation stack/sheets
- Touch-first interaction
- Safe area insets

### 2. Background Execution

**Desktop**: Runs continuously, can perform background tasks freely

**iOS**: Limited background execution, must use background modes

### 3. Storage Paths

**Desktop**:
```csharp
~/.ecliptix/
~/Library/Application Support/Ecliptix/
```

**iOS**:
```swift
FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
```

### 4. Secure Storage

**Desktop**: Microsoft DataProtection API

**iOS**: Keychain Services (more secure, hardware-backed)

### 5. Cryptography APIs

**Desktop**: BouncyCastle (custom implementations)

**iOS**: CryptoKit (Apple's framework, hardware-accelerated)

### 6. Reactive Programming

**Desktop**: ReactiveUI with RxNET

**iOS**: Combine with async/await

## Critical Migration Areas

### ⚠️ High Priority: Security

1. **OPAQUE Protocol** - Must be exact port, extensive testing required
2. **Key derivation** - Ensure compatibility with desktop
3. **Encryption/Decryption** - Binary compatibility for interop
4. **Certificate pinning** - Properly configured for iOS

### ⚠️ High Priority: Data Compatibility

If users will migrate from desktop to iOS:
- Ensure encrypted data formats are compatible
- Port state serialization exactly
- Verify protocol buffer compatibility
- Plan migration path for existing users

### ⚠️ Medium Priority: UX Adaptation

- Redesign window chrome for iOS
- Adapt modal system to iOS sheets
- Update navigation patterns
- Implement iOS-native controls

## Testing Strategy

### 1. Unit Tests (Target: 80%+ coverage)

```swift
@testable import EcliptixSecurity
@testable import EcliptixNetworking
@testable import EcliptixAuthentication

// Example test structure
class OPAQUEProtocolTests: XCTestCase {
    func testRegistrationFlow() async throws {
        // Test OPAQUE registration
    }
}
```

### 2. Integration Tests

Focus areas:
- gRPC service calls
- End-to-end authentication
- Network error handling
- State persistence

### 3. Cryptography Validation

**Critical**: Create test vectors from desktop app and verify iOS produces same results

```swift
func testEncryptionCompatibility() {
    // Use known plaintext, key, and nonce from desktop
    // Verify ciphertext matches
}
```

### 4. Manual Testing Checklist

- [ ] Registration flow (happy path)
- [ ] Registration with invalid mobile number
- [ ] Registration with incorrect OTP
- [ ] Sign-in flow (happy path)
- [ ] Sign-in with wrong password
- [ ] Password recovery flow
- [ ] Network disconnection scenarios
- [ ] App backgrounding/foregrounding
- [ ] State restoration after app termination

## Next Steps

1. **Phase 2**: Start with Protocol Buffer migration
   ```bash
   cd /home/user/ecliptix-desktop
   find Protos -name "*.proto" -exec cp {} /home/user/ecliptix-ios/Protos/ \;
   ```

2. **Phase 3**: Begin cryptography implementation
   - Start with basic primitives (ChaCha20, X25519)
   - Move to OPAQUE protocol
   - Extensive testing

3. **Continuous**: Keep documentation updated as you discover edge cases

## Resources

- [Swift Protobuf Documentation](https://github.com/apple/swift-protobuf)
- [gRPC Swift Guide](https://github.com/grpc/grpc-swift)
- [CryptoKit Documentation](https://developer.apple.com/documentation/cryptokit)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [iOS Keychain Services](https://developer.apple.com/documentation/security/keychain_services)

## Questions & Decisions

Track important decisions and open questions:

- [ ] **Q**: Should we maintain binary compatibility with desktop app?
- [ ] **Q**: Will users migrate data from desktop to iOS?
- [ ] **Q**: Do we need to support iOS < 16.0?
- [ ] **Q**: Should we use TCA instead of MVVM+Combine?
- [ ] **D**: Using CryptoKit where possible, custom implementations for OPAQUE
- [ ] **D**: Minimum iOS 16.0 for modern Swift features
