# Ecliptix iOS

**Modern, secure messaging app for iOS built with Swift and SwiftUI**

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2017.0+-blue.svg)](https://developer.apple.com/ios/)
[![License](https://img.shields.io/badge/License-Proprietary-red.svg)]()

Ecliptix is a privacy-focused messaging application featuring end-to-end encryption, modern Swift architecture, and a beautiful SwiftUI interface. This iOS app maintains full protocol compatibility with the C#/.NET desktop version.

## 🌟 Features

### Security & Privacy
- 🔐 **End-to-End Encryption** - Double Ratchet protocol with forward secrecy
- 🔑 **X3DH Key Agreement** - Secure key exchange using Curve25519
- 🛡️ **Secure Storage** - iOS Keychain + ChaChaPoly encrypted local storage
- 📱 **Device-Only Data** - All sensitive data stays on device
- 🔒 **No Cloud Backup** - Credentials never leave the device

### Network & Performance
- 🌐 **gRPC Communication** - High-performance binary protocol
- 🔄 **Automatic Retry** - Smart retry with exponential backoff and jitter
- 🚦 **Circuit Breaker** - Automatic failure protection
- 💚 **Health Monitoring** - Real-time connection health tracking
- 💾 **Response Caching** - Intelligent caching for improved performance
- ⏱️ **Timeout Management** - Per-request timeout control
- 🌊 **Outage Recovery** - Automatic recovery from network outages

### User Experience
- 🎨 **Modern SwiftUI** - Beautiful, native iOS interface
- 🌓 **Dark Mode** - Full dark mode support
- ♿ **Accessibility** - VoiceOver and accessibility features
- ⚡ **Reactive UI** - Instant updates with @Observable
- 🔔 **Real-time Validation** - Live input validation and feedback

## 📋 Requirements

- **iOS 17.0+**
- **Xcode 15.0+**
- **Swift 5.9+**
- **CocoaPods or Swift Package Manager**

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/oleksandrmelnychenko/ecliptix-ios-mobile.git
cd ecliptix-ios-mobile
```

### 2. Install Dependencies

The project uses Swift Package Manager. Dependencies will be resolved automatically when you open the project in Xcode.

### 3. Generate Protobuf Code

```bash
# Install prerequisites
brew install protobuf swift-protobuf

# Build gRPC plugin
swift build --product protoc-gen-grpc-swift

# Generate Swift code from proto files
./generate-protos.sh
```

### 4. Open in Xcode

```bash
open EcliptixApp/EcliptixApp.xcodeproj
```

### 5. Build and Run

- Select your target device or simulator
- Press `⌘R` to build and run

## 📁 Project Structure

```
ecliptix-ios/
├── Packages/
│   ├── EcliptixCore/              # Core types, logging, storage
│   │   └── Sources/
│   │       ├── Logging/           # Logging system
│   │       ├── Storage/           # Keychain, encrypted storage, sessions
│   │       └── Utilities/         # Helpers and extensions
│   │
│   ├── EcliptixSecurity/          # Cryptography & protocol
│   │   └── Sources/
│   │       ├── Crypto/            # X3DH, DoubleRatchet, IdentityKeys
│   │       └── Protocol/          # Protocol implementation
│   │
│   └── EcliptixNetworking/        # Network layer
│       └── Sources/
│           ├── Core/              # Retry, circuit breaker, health, cache
│           ├── GRPC/              # gRPC channel management
│           ├── Protocol/          # NetworkProvider, connection management
│           └── Services/          # RPC service clients
│
├── EcliptixApp/                   # Main iOS application
│   └── EcliptixApp/
│       ├── Views/                 # SwiftUI views
│       │   └── Authentication/    # Sign in, registration, OTP
│       └── Services/              # Business logic services
│
├── Protos/                        # Protocol Buffer definitions
├── generate-protos.sh             # Protobuf generation script
├── MIGRATION_STATUS.md            # Migration progress tracker
└── Package.swift                  # Swift Package Manager manifest
```

## 🏗️ Architecture

### Clean Architecture Layers

1. **Domain Layer** (`EcliptixCore`, `EcliptixSecurity`)
   - Core business logic
   - Cryptographic protocols
   - Storage abstractions

2. **Network Layer** (`EcliptixNetworking`)
   - gRPC communication
   - Network resilience
   - Service clients

3. **Presentation Layer** (`EcliptixApp`)
   - SwiftUI views
   - Services (replacing ViewModels)
   - Navigation

### Key Design Patterns

- **Service-based Architecture** - Using Swift 5.9+ `@Observable` instead of ViewModels
- **Result Types** - Explicit error handling instead of exceptions
- **Dependency Injection** - Protocol-based dependencies for testability
- **Combine** - Reactive programming for state management
- **Async/Await** - Modern Swift concurrency

## 🔐 Security Features

### Double Ratchet Protocol

The app implements the Signal Protocol's Double Ratchet for end-to-end encryption:

- **Forward Secrecy** - Compromised keys don't decrypt past messages
- **Break-in Recovery** - Automatic recovery from key compromise
- **Per-Message Keys** - Unique encryption key for every message
- **Associated Data** - Authenticated metadata

### X3DH Key Agreement

Extended Triple Diffie-Hellman for secure key exchange:

- **Identity Keys** - Long-term Curve25519 keys
- **Signed Prekeys** - Medium-term signed keys
- **One-Time Prekeys** - Single-use keys (up to 100)
- **HKDF** - HMAC-based key derivation

### Storage Security

- **Keychain** - Sensitive credentials (identity keys, tokens)
- **Encrypted Files** - ChaChaPoly AEAD for local data
- **Device-Only** - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- **Secure Deletion** - Memory wiping for cryptographic material

## 🌐 Network Resilience

### Retry Strategy

- **Exponential Backoff** - 1s → 2s → 4s → 8s → 16s → 30s (max)
- **Decorrelated Jitter** - ±20% randomization to prevent thundering herd
- **Operation Tracking** - Global exhaustion detection
- **Manual Retry** - UI-triggered retry after exhaustion

### Circuit Breaker

- **Closed State** - Normal operation, requests pass through
- **Open State** - Failure threshold exceeded, fail-fast
- **Half-Open State** - Testing recovery with limited requests
- **Per-Connection** - Individual circuit breakers per connection

### Health Monitoring

- **Health States** - Healthy, degraded, unhealthy, critical
- **Success Rate** - Track request success percentage
- **Latency Tracking** - Rolling window of 100 samples
- **Auto-Recovery** - Circuit reset when healthy

### Caching

- **Policies** - networkOnly, cacheFirst, networkFirst, cacheOnly
- **TTL** - Configurable time-to-live (default: 5 minutes)
- **Size Limits** - Max 100 entries, 1MB per entry
- **Statistics** - Hit rate, miss rate, eviction tracking

## 📱 User Flows

### Registration

1. Enter mobile number
2. Create secure key (12+ chars, uppercase, lowercase, number, special)
3. Confirm secure key
4. Verify OTP (6 digits)
5. Account created

### Sign In

1. Enter mobile number and secure key
2. Verify OTP if required
3. Signed in

### Messaging (Coming Soon)

1. Select contact
2. Type message
3. Message encrypted and sent
4. Real-time delivery confirmation

## 🧪 Testing

### Unit Tests

```bash
swift test
```

### UI Tests

Run from Xcode:
1. Select test target
2. Press `⌘U`

### Integration Tests

Run against local or staging backend:

```bash
# Set backend URL
export ECLIPTIX_BACKEND_URL="https://staging.ecliptix.com"

# Run tests
swift test --filter IntegrationTests
```

## 📚 Documentation

- [MIGRATION_STATUS.md](./MIGRATION_STATUS.md) - Migration progress (95% complete)
- [PROTOBUF_SETUP.md](./PROTOBUF_SETUP.md) - Protobuf setup instructions
- [PROTOBUF_INTEGRATION_GUIDE.md](./PROTOBUF_INTEGRATION_GUIDE.md) - Integration guide
- [ARCHITECTURE_DECISION.md](./ARCHITECTURE_DECISION.md) - ViewModels vs Services decision

## 🛠️ Development

### Code Style

The project follows Swift API Design Guidelines:

- **PascalCase** for types
- **camelCase** for functions and variables
- **Explicit types** where it improves readability
- **SwiftLint** for code consistency (optional)

### Logging

Use the built-in logging system:

```swift
import EcliptixCore

Log.verbose("Detailed debug info")
Log.debug("Debug information")
Log.info("General information")
Log.warning("Warning message")
Log.error("Error occurred")
```

### Storage

```swift
// Keychain (sensitive credentials)
let keychain = KeychainStorage()
try keychain.store(identityKeys, forKey: .identityKeys)

// Encrypted files (app data)
let storage = try SecureStorage()
try storage.store(userData, forKey: "user_data")

// Session state
let sessionManager = SessionStateManager()
sessionManager.startSession(user: user, device: device)
```

### Network Requests

```swift
// Via NetworkProvider
let result = await networkProvider.executeWithRetry(
    operationName: "signIn",
    connectId: connectId,
    serviceType: .signInInit,
    plainBuffer: requestData
) { responseData in
    return try JSONDecoder().decode(SignInResponse.self, from: responseData)
}
```

## 🤝 Contributing

This is a private project. For questions or issues, please contact the development team.

## 📄 License

Proprietary - All rights reserved.

## 🙏 Acknowledgments

- **Signal Protocol** - For the Double Ratchet specification
- **gRPC** - For high-performance RPC
- **Swift Crypto** - For native cryptographic primitives
- **SwiftUI** - For modern, declarative UI

## 📞 Support

For support, please contact:
- Email: support@ecliptix.com
- Documentation: https://docs.ecliptix.com

---

**Built with ❤️ using Swift and SwiftUI**

**Migration Status:** 95% Complete - Near Production Ready! 🎉
