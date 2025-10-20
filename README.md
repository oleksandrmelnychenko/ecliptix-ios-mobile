# Ecliptix iOS

iOS Swift implementation of the Ecliptix secure messaging and authentication application.

## Overview

Ecliptix iOS is a native Swift application that provides secure user authentication, end-to-end encryption, and messaging capabilities. This is a migration from the .NET/Avalonia desktop application to iOS.

## Architecture

The application follows a modular architecture using Swift Package Manager:

### Modules

- **EcliptixCore**: Core types, protocols, and utilities
  - Application state management
  - Logging abstractions
  - Common types and extensions

- **EcliptixSecurity**: Cryptographic primitives and secure storage
  - OPAQUE protocol implementation
  - X25519 key exchange
  - ChaCha20-Poly1305 encryption
  - iOS Keychain integration
  - Secure storage protocols

- **EcliptixNetworking**: Network layer and gRPC services
  - gRPC client implementations
  - Request interceptors
  - Retry policies with exponential backoff
  - Network connectivity monitoring
  - Certificate pinning

- **EcliptixAuthentication**: Authentication flows and user management
  - Registration with OTP verification
  - Sign-in with OPAQUE protocol
  - Password recovery
  - Session management

### Technology Stack

- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Minimum iOS Version**: iOS 16.0
- **Architecture Pattern**: MVVM with Combine
- **Networking**: gRPC Swift, Swift Protobuf
- **Cryptography**: CryptoKit, custom implementations
- **Dependency Management**: Swift Package Manager

## Project Structure

```
ecliptix-ios/
├── EcliptixApp/                 # Main iOS application
│   └── EcliptixApp/
│       ├── EcliptixApp.swift    # App entry point
│       ├── RootView.swift       # Root navigation
│       └── Views/               # SwiftUI views
│           ├── Auth/            # Authentication views
│           ├── SplashView.swift
│           └── MainView.swift
├── Packages/                    # Swift Package modules
│   ├── EcliptixCore/
│   ├── EcliptixNetworking/
│   ├── EcliptixSecurity/
│   └── EcliptixAuthentication/
├── Protos/                      # Protocol Buffer definitions
└── Package.swift                # Workspace package manifest
```

## Requirements

- Xcode 15.0+
- iOS 16.0+
- Swift 5.9+
- macOS 13.0+ (for development)

## Getting Started

### 1. Clone the Repository

```bash
git clone <repository-url>
cd ecliptix-ios
```

### 2. Open in Xcode

Open the `Package.swift` file or the `.xcodeproj` file in Xcode.

### 3. Build the Project

```bash
# Using Xcode
# Product > Build (⌘+B)

# Or using command line
swift build
```

### 4. Run the Application

Select the `EcliptixApp` scheme and run on simulator or device.

## Development

### Adding Protocol Buffer Definitions

1. Place `.proto` files in the `Protos/` directory
2. Run the protocol buffer compiler:

```bash
protoc --swift_out=. --grpc-swift_out=. Protos/*.proto
```

3. Move generated files to appropriate package Sources directory

### Running Tests

```bash
# Run all tests
swift test

# Or in Xcode
# Product > Test (⌘+U)
```

### Code Style

- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use SwiftLint for code formatting (optional)
- Prefer protocol-oriented programming
- Use async/await for asynchronous operations

## Security Features

- **OPAQUE Protocol**: Password-authenticated key exchange
- **End-to-End Encryption**: ChaCha20-Poly1305 AEAD cipher
- **Key Exchange**: X25519 Elliptic Curve Diffie-Hellman
- **Certificate Pinning**: SSL/TLS certificate validation
- **Secure Storage**: iOS Keychain for sensitive data
- **Device Security**: Optional biometric authentication

## Migration Status

This project is migrated from the .NET/Avalonia desktop application. Current status:

- [x] Project structure setup
- [x] Core module foundation
- [x] Security module protocols
- [x] Networking module protocols
- [x] Authentication module protocols
- [x] Basic SwiftUI views
- [ ] Protocol Buffer models migration
- [ ] gRPC service implementations
- [ ] Cryptographic implementations (OPAQUE)
- [ ] Secure storage implementation
- [ ] Network connectivity monitoring
- [ ] Complete authentication flows
- [ ] Localization support
- [ ] Testing infrastructure

## Contributing

1. Create a feature branch
2. Make your changes
3. Write tests
4. Submit a pull request

## License

[License information to be added]

## Contact

[Contact information to be added]
