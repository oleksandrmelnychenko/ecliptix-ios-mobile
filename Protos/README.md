# Protocol Buffer Definitions

This directory contains Protocol Buffer (`.proto`) files that define the gRPC service contracts and message types for the Ecliptix application.

## Migration Instructions

To migrate the Protocol Buffer definitions from the desktop application:

1. **Copy `.proto` files** from the desktop project:
   ```bash
   cp /home/user/ecliptix-desktop/Protos/*.proto /home/user/ecliptix-ios/Protos/
   ```

2. **Install Protocol Buffer compiler** (if not already installed):
   ```bash
   brew install protobuf
   brew install swift-protobuf
   brew install grpc-swift
   ```

3. **Generate Swift code** from proto files:
   ```bash
   # From the ecliptix-ios directory
   protoc --swift_out=Generated \
          --grpc-swift_out=Generated \
          --proto_path=Protos \
          Protos/*.proto
   ```

4. **Move generated files** to the appropriate package:
   ```bash
   # Service definitions to Networking package
   mv Generated/*_service.swift Packages/EcliptixNetworking/Sources/Generated/

   # Message types can go to Core or appropriate feature packages
   mv Generated/*.pb.swift Packages/EcliptixCore/Sources/Generated/
   ```

## Expected Proto Files (from Desktop Application)

Based on the desktop codebase analysis, the following proto files should be migrated:

### Service Definitions
- `membership_services.proto` - User registration, sign-in, logout
- `auth_verification_services.proto` - OTP verification, mobile validation
- `device_service.proto` - Device registration and secure channel
- Additional service definitions as identified

### Message Types
- OPAQUE protocol messages (registration, authentication)
- Secure envelope wrapper messages
- Device and session management messages
- Error and status messages

## Proto File Structure

```
Protos/
├── common/
│   ├── common_types.proto
│   └── error_types.proto
├── services/
│   ├── membership_services.proto
│   ├── auth_verification_services.proto
│   └── device_service.proto
└── messages/
    ├── auth_messages.proto
    └── device_messages.proto
```

## Code Generation

### Manual Generation

```bash
# Generate Swift code
protoc --swift_out=. Protos/**/*.proto

# Generate gRPC service stubs
protoc --grpc-swift_out=. Protos/**/*.proto
```

### Automated Generation (Recommended)

Add a build phase in Xcode or create a script:

```bash
#!/bin/bash
# scripts/generate-protos.sh

PROTO_DIR="Protos"
OUT_DIR="Generated"

mkdir -p $OUT_DIR

protoc --swift_out=$OUT_DIR \
       --grpc-swift_out=$OUT_DIR \
       --proto_path=$PROTO_DIR \
       $PROTO_DIR/**/*.proto

echo "✅ Protocol Buffers generated successfully"
```

Make it executable:
```bash
chmod +x scripts/generate-protos.sh
```

## Integration with Swift Package

Once generated, add the generated files to the appropriate Swift Package targets in `Package.swift`.

## Notes

- Generated files should be added to `.gitignore` and regenerated during build
- Or commit generated files if you want reproducible builds
- Keep proto files in sync with backend service definitions
- Version proto files alongside API versions
