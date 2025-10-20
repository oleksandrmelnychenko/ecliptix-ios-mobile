# Ecliptix iOS - Setup Guide

This guide will help you set up your development environment for the Ecliptix iOS project.

## Prerequisites

- macOS 13.0 or later
- Xcode 15.0 or later
- Homebrew (recommended for package management)

## Required Tools

### 1. Xcode

Download from the Mac App Store or:

```bash
xcode-select --install
```

### 2. Swift (comes with Xcode)

Verify installation:

```bash
swift --version
# Should show Swift 5.9 or later
```

### 3. Protocol Buffers Compiler

```bash
# Install protoc
brew install protobuf

# Verify installation
protoc --version
# Should show libprotoc 3.20.0 or later
```

### 4. Swift Protobuf Plugin

```bash
# Install swift-protobuf
brew install swift-protobuf

# Verify installation
which protoc-gen-swift
# Should show path to plugin
```

### 5. gRPC Swift (for service generation)

#### Option A: Using Homebrew (if available)

```bash
brew install grpc-swift
```

#### Option B: Build from Source

```bash
# Clone the repository
git clone https://github.com/grpc/grpc-swift.git
cd grpc-swift

# Build the plugins
make plugins

# Install to /usr/local/bin
cp .build/release/protoc-gen-grpc-swift /usr/local/bin/

# Verify
which protoc-gen-grpc-swift
protoc-gen-grpc-swift --version
```

## Project Setup

### 1. Clone the Repository

```bash
cd /home/user
ls ecliptix-ios  # Should exist
cd ecliptix-ios
```

### 2. Verify Proto Files

```bash
find Protos -name "*.proto" | wc -l
# Should show 17 files
```

### 3. Generate Swift Code from Proto Files

```bash
# Using the Makefile
make generate-protos

# Or directly
./scripts/generate-protos.sh
```

Expected output:
```
Starting Protocol Buffer Swift code generation...

Found proto files:
  - Protos/account/account_models.proto
  - Protos/authentication/auth_services.proto
  ...

✓ Swift Protocol Buffer models generated
✓ gRPC service stubs generated

Generation Complete!
  Protocol Buffer models: 17 files
  gRPC service stubs:     3 files
```

### 4. Build the Project

#### Using Swift Package Manager

```bash
# Build all packages
swift build

# Build specific package
swift build --package-path Packages/EcliptixCore
```

#### Using Xcode

1. Open `Package.swift` in Xcode
2. Select scheme (e.g., EcliptixApp)
3. Build (⌘+B)

### 5. Run Tests

```bash
# Run all tests
swift test

# Or in Xcode
# Product > Test (⌘+U)
```

## Common Commands

```bash
# Generate proto files
make generate-protos

# Clean generated files
make clean

# Build project
make build

# Run tests
make test

# Show all commands
make help
```

## Project Structure After Setup

```
ecliptix-ios/
├── EcliptixApp/              # Main iOS app
├── Packages/                 # Swift Package modules
│   ├── EcliptixCore/
│   ├── EcliptixNetworking/
│   │   └── Sources/
│   │       └── Generated/    # ← Generated proto files go here
│   ├── EcliptixSecurity/
│   └── EcliptixAuthentication/
├── Protos/                   # Protocol Buffer definitions
├── Generated/                # Temporary generated files
├── scripts/
│   └── generate-protos.sh    # Generation script
├── Package.swift             # Workspace manifest
└── Makefile                  # Build commands
```

## Troubleshooting

### "protoc: command not found"

```bash
brew install protobuf
```

### "protoc-gen-swift: program not found or is not executable"

```bash
brew install swift-protobuf
# Or ensure it's in PATH
export PATH="/usr/local/bin:$PATH"
```

### "protoc-gen-grpc-swift: program not found"

Build from source as described in step 5 above.

### Generated files not appearing in Xcode

1. Right-click on `Sources/Generated` folder
2. Select "Add Files to..."
3. Navigate to `Packages/EcliptixNetworking/Sources/Generated`
4. Select all `.swift` files
5. Ensure "Copy items if needed" is checked
6. Click "Add"

### Build errors related to gRPC

Ensure all dependencies are resolved:

```bash
swift package resolve
swift package update
```

## Xcode Configuration

### Opening the Project

```bash
cd ecliptix-ios

# Option 1: Open Package.swift
open Package.swift

# Option 2: If you have an .xcodeproj
open EcliptixApp.xcodeproj
```

### Setting Up Schemes

1. Product > Scheme > Manage Schemes
2. Ensure "EcliptixApp" scheme is visible
3. Set deployment target to iOS 16.0+

### Code Signing

1. Select project in navigator
2. Select "EcliptixApp" target
3. Go to "Signing & Capabilities"
4. Select your development team
5. Choose automatic or manual signing

## Next Steps

After setup:

1. ✅ Verify proto generation works
2. ✅ Build the project successfully
3. ✅ Run tests (even if minimal)
4. Continue migration:
   - Implement gRPC service clients
   - Port cryptographic implementations
   - Build authentication flows

## Additional Resources

- [Swift Package Manager](https://swift.org/package-manager/)
- [Protocol Buffers](https://developers.google.com/protocol-buffers)
- [gRPC Swift Documentation](https://github.com/grpc/grpc-swift)
- [CryptoKit](https://developer.apple.com/documentation/cryptokit)
- [SwiftUI](https://developer.apple.com/documentation/swiftui)

## Support

For issues or questions:
- Check existing GitHub issues
- Consult MIGRATION_GUIDE.md
- Review desktop implementation in `/home/user/ecliptix-desktop`
