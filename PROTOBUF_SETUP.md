# Protobuf Setup for Ecliptix iOS

This guide explains how to set up protobuf code generation for the Ecliptix iOS project.

## Prerequisites

### 1. Install Protocol Buffers Compiler (protoc)

**macOS (Homebrew):**
```bash
brew install protobuf
```

**Verify installation:**
```bash
protoc --version
# Should show: libprotoc 3.x.x or higher
```

### 2. Install Swift Protobuf Plugin

**macOS (Homebrew):**
```bash
brew install swift-protobuf
```

**Verify installation:**
```bash
which protoc-gen-swift
# Should show: /usr/local/bin/protoc-gen-swift or similar
```

### 3. Install gRPC Swift Plugin

The gRPC Swift plugin is included as a dependency in `Package.swift`. However, you need to build it:

**Option A: Use SPM to build the plugin**
```bash
cd /path/to/ecliptix-ios
swift build --product protoc-gen-grpc-swift
```

**Option B: Install from grpc-swift repository**
```bash
git clone https://github.com/grpc/grpc-swift.git
cd grpc-swift
make plugins
# Copy the plugin to PATH
sudo cp .build/release/protoc-gen-grpc-swift /usr/local/bin/
```

**Verify installation:**
```bash
which protoc-gen-grpc-swift
# Should show path to the plugin
```

## Generate Protobuf Code

Once prerequisites are installed, run the generation script:

```bash
cd /path/to/ecliptix-ios
./generate-protos.sh
```

This will:
1. Find all `.proto` files in `./Protos/`
2. Generate Swift message code for each proto file
3. Generate gRPC service code for service definitions
4. Place generated files in `./Packages/EcliptixCore/Sources/Generated/Proto/`
5. Create an import index file

## Generated File Structure

```
Packages/EcliptixCore/Sources/Generated/
├── ProtoImports.swift          # Convenience import file
└── Proto/
    ├── common/
    │   ├── types.pb.swift
    │   ├── secure_envelope.pb.swift
    │   └── ...
    ├── membership/
    │   ├── membership_services.pb.swift
    │   ├── membership_services.grpc.swift
    │   └── ...
    ├── device/
    │   └── ...
    └── protocol/
        └── ...
```

## Integration with Service Clients

### Before (Placeholder):
```swift
public func registrationInit(envelope: SecureEnvelope) async -> Result<SecureEnvelope, NetworkFailure> {
    throw NetworkError.unknown("Protobuf client not yet generated")
}
```

### After (With Generated Code):
```swift
import Ecliptix_Protobuf_Membership

public func registrationInit(envelope: SecureEnvelope) async -> Result<SecureEnvelope, NetworkFailure> {
    return await executeSecureEnvelopeCall(
        serviceType: .registrationInit,
        envelope: envelope
    ) { request, callOptions in
        let client = Ecliptix_Protobuf_Membership_MembershipServicesClient(channel: try self.channelManager.getChannel())
        return try await client.registrationInit(request, callOptions: callOptions)
    }
}
```

## Updating Package.swift

Make sure your `Package.swift` includes the Generated directory:

```swift
.target(
    name: "EcliptixCore",
    dependencies: [
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
    ],
    path: "Packages/EcliptixCore/Sources",
    sources: [".", "Generated"]
)
```

## Proto Files Included

The following proto files are ready for generation:

**Common:**
- `common/types.proto` - Common data types
- `common/encryption.proto` - Encryption types
- `common/secure_envelope.proto` - SecureEnvelope definition

**Membership:**
- `membership/membership_services.proto` - Membership RPC services
- `membership/membership_core.proto` - Core membership types
- `membership/opaque_models.proto` - OPAQUE protocol types

**Device:**
- `device/device_services.proto` - Device RPC services
- `device/device_models.proto` - Device data models
- `device/application_settings.proto` - App settings

**Protocol:**
- `protocol/key_exchange.proto` - Key exchange types
- `protocol/protocol_state.proto` - Protocol state types
- `protocol/key_materials.proto` - Key material types

**Authentication:**
- `authentication/auth_services.proto` - Auth RPC services
- `authentication/verification_models.proto` - Verification types

**Security:**
- `security/secure_request.proto` - Secure request types

**Account:**
- `account/account_models.proto` - Account data models

## Troubleshooting

### Error: protoc not found
```bash
brew install protobuf
```

### Error: protoc-gen-swift not found
```bash
brew install swift-protobuf
```

### Error: protoc-gen-grpc-swift not found
```bash
# Build from dependencies
swift build --product protoc-gen-grpc-swift

# Or install manually
git clone https://github.com/grpc/grpc-swift.git
cd grpc-swift
make plugins
sudo cp .build/release/protoc-gen-grpc-swift /usr/local/bin/
```

### Generated files not compiling
1. Make sure SwiftProtobuf dependency is in Package.swift
2. Verify generated files are in the correct location
3. Check Package.swift includes the Generated directory in sources
4. Run `swift build` to see specific errors

### Import errors in service clients
```swift
// Make sure to import the generated module
import Ecliptix_Protobuf_Membership
import Ecliptix_Protobuf_Device
import Ecliptix_Protobuf_Common
```

## Next Steps After Generation

1. **Review Generated Code**
   ```bash
   ls -R Packages/EcliptixCore/Sources/Generated/Proto/
   ```

2. **Update Service Clients**
   - MembershipServiceClient.swift
   - DeviceServiceClient.swift
   - SecureChannelServiceClient.swift

3. **Build Project**
   ```bash
   swift build
   ```

4. **Run Tests**
   ```bash
   swift test
   ```

## Notes

- Generated files are **not** checked into Git (see `.gitignore`)
- Re-run `./generate-protos.sh` after updating any `.proto` files
- Keep proto files in sync with backend C# definitions
- Generated code uses `SwiftProtobuf` types (Message, FieldNumber, etc.)
- gRPC services use `GRPC` framework (CallOptions, GRPCChannel, etc.)

## Resources

- [SwiftProtobuf Documentation](https://github.com/apple/swift-protobuf)
- [gRPC Swift Documentation](https://github.com/grpc/grpc-swift)
- [Protocol Buffers Guide](https://developers.google.com/protocol-buffers)
- [gRPC Concepts](https://grpc.io/docs/what-is-grpc/core-concepts/)
