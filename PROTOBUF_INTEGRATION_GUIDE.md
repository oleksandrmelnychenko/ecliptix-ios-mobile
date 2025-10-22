# Protobuf Integration Guide

This guide explains how to integrate the generated protobuf code with the service clients.

## Current Status

✅ **Completed:**
- Protobuf generation script (`generate-protos.sh`)
- Setup documentation (`PROTOBUF_SETUP.md`)
- Service client placeholders (MembershipServiceClient, DeviceServiceClient, etc.)
- Example implementation (`MembershipServiceClient+Example.swift`)
- Package.swift configured with SwiftProtobuf dependency
- .gitignore configured to exclude Generated/ directory

⏭️ **Next Steps:**
1. Install protobuf prerequisites
2. Generate Swift protobuf code
3. Update service clients with generated types
4. Test integration

## Step 1: Install Prerequisites

### Install protoc (Protocol Buffers Compiler)
```bash
brew install protobuf
protoc --version  # Should show libprotoc 3.x.x or higher
```

### Install Swift Protobuf Plugin
```bash
brew install swift-protobuf
which protoc-gen-swift  # Should show /usr/local/bin/protoc-gen-swift
```

### Install gRPC Swift Plugin
```bash
cd /home/user/ecliptix-ios
swift build --product protoc-gen-grpc-swift

# Verify the plugin is available
ls .build/debug/protoc-gen-grpc-swift
```

## Step 2: Generate Protobuf Code

Once prerequisites are installed, run the generation script:

```bash
cd /home/user/ecliptix-ios
./generate-protos.sh
```

This will generate Swift code in:
```
Packages/EcliptixCore/Sources/Generated/Proto/
├── common/
│   ├── secure_envelope.pb.swift
│   ├── types.pb.swift
│   ├── encryption.pb.swift
│   └── health_check.pb.swift
├── membership/
│   ├── membership_services.pb.swift
│   ├── membership_services.grpc.swift
│   ├── membership_core.pb.swift
│   └── opaque_models.pb.swift
├── authentication/
│   ├── auth_services.pb.swift
│   ├── auth_services.grpc.swift
│   └── verification_models.pb.swift
├── device/
│   ├── device_services.pb.swift
│   ├── device_services.grpc.swift
│   ├── device_models.pb.swift
│   └── application_settings.pb.swift
├── protocol/
│   ├── key_exchange.pb.swift
│   ├── protocol_state.pb.swift
│   └── key_materials.pb.swift
├── account/
│   └── account_models.pb.swift
└── security/
    └── secure_request.pb.swift
```

## Step 3: Update Service Clients

### Service Architecture

Based on the proto definitions, we have these services:

1. **MembershipServices** (`membership/membership_services.proto`)
   - Package: `ecliptix.proto.membership`
   - Generated client: `Ecliptix_Proto_Membership_MembershipServicesAsyncClient`
   - Methods:
     - `OpaqueRegistrationInitRequest(SecureEnvelope) -> SecureEnvelope`
     - `OpaqueRegistrationCompleteRequest(SecureEnvelope) -> SecureEnvelope`
     - `OpaqueSignInInitRequest(SecureEnvelope) -> SecureEnvelope`
     - `OpaqueSignInCompleteRequest(SecureEnvelope) -> SecureEnvelope`
     - `Logout(SecureEnvelope) -> SecureEnvelope`

2. **AuthVerificationServices** (`authentication/auth_services.proto`)
   - Package: `ecliptix.proto.membership`
   - Generated client: `Ecliptix_Proto_Membership_AuthVerificationServicesAsyncClient`
   - Methods:
     - `ValidateMobileNumber(SecureEnvelope) -> SecureEnvelope`
     - `CheckMobileNumberAvailability(SecureEnvelope) -> SecureEnvelope`
     - `VerifyOtp(SecureEnvelope) -> SecureEnvelope`
     - `InitiateVerification(SecureEnvelope) -> stream SecureEnvelope`

3. **DeviceService** (`device/device_services.proto`)
   - Package: `ecliptix.proto.device`
   - Generated client: `Ecliptix_Proto_Device_DeviceServiceAsyncClient`
   - Methods:
     - `RegisterDevice(SecureEnvelope) -> SecureEnvelope`
     - `EstablishSecureChannel(SecureEnvelope) -> SecureEnvelope`
     - `RestoreSecureChannel(RestoreChannelRequest) -> RestoreChannelResponse`
     - `AuthenticatedEstablishSecureChannel(AuthenticatedEstablishRequest) -> SecureEnvelope`

### Update MembershipServiceClient.swift

After generation, update the file to import and use generated types:

```swift
import Foundation
import GRPC
import EcliptixCore
// Import generated protobuf modules
import Ecliptix_Proto_Membership
import Ecliptix_Proto_Common

public final class MembershipServiceClient: BaseRPCService {

    // Generated gRPC clients
    private var membershipClient: Ecliptix_Proto_Membership_MembershipServicesAsyncClient {
        get throws {
            let channel = try channelManager.getChannel()
            return Ecliptix_Proto_Membership_MembershipServicesAsyncClient(channel: channel)
        }
    }

    private var authClient: Ecliptix_Proto_Membership_AuthVerificationServicesAsyncClient {
        get throws {
            let channel = try channelManager.getChannel()
            return Ecliptix_Proto_Membership_AuthVerificationServicesAsyncClient(channel: channel)
        }
    }

    // MARK: - Registration Init
    public func registrationInit(
        envelope: Ecliptix_Proto_Common_SecureEnvelope
    ) async -> Result<Ecliptix_Proto_Common_SecureEnvelope, NetworkFailure> {

        return await executeRPCCall(
            serviceType: .registrationInit,
            request: envelope
        ) { request, callOptions in
            try await self.membershipClient.opaqueRegistrationInitRequest(request, callOptions: callOptions)
        }
    }

    // ... similar updates for other methods
}
```

### Create AuthVerificationServiceClient.swift

Split authentication verification into its own client:

```swift
import Foundation
import GRPC
import EcliptixCore
import Ecliptix_Proto_Membership
import Ecliptix_Proto_Common

public final class AuthVerificationServiceClient: BaseRPCService {

    private var authClient: Ecliptix_Proto_Membership_AuthVerificationServicesAsyncClient {
        get throws {
            let channel = try channelManager.getChannel()
            return Ecliptix_Proto_Membership_AuthVerificationServicesAsyncClient(channel: channel)
        }
    }

    public func validateMobileNumber(
        envelope: Ecliptix_Proto_Common_SecureEnvelope
    ) async -> Result<Ecliptix_Proto_Common_SecureEnvelope, NetworkFailure> {
        // Implementation
    }

    public func checkMobileAvailability(
        envelope: Ecliptix_Proto_Common_SecureEnvelope
    ) async -> Result<Ecliptix_Proto_Common_SecureEnvelope, NetworkFailure> {
        // Implementation
    }

    public func verifyOTP(
        envelope: Ecliptix_Proto_Common_SecureEnvelope
    ) async -> Result<Ecliptix_Proto_Common_SecureEnvelope, NetworkFailure> {
        // Implementation
    }
}
```

### Update DeviceServiceClient.swift

```swift
import Foundation
import GRPC
import EcliptixCore
import Ecliptix_Proto_Device
import Ecliptix_Proto_Common

public final class DeviceServiceClient: BaseRPCService {

    private var deviceClient: Ecliptix_Proto_Device_DeviceServiceAsyncClient {
        get throws {
            let channel = try channelManager.getChannel()
            return Ecliptix_Proto_Device_DeviceServiceAsyncClient(channel: channel)
        }
    }

    public func registerDevice(
        envelope: Ecliptix_Proto_Common_SecureEnvelope
    ) async -> Result<Ecliptix_Proto_Common_SecureEnvelope, NetworkFailure> {

        return await executeRPCCall(
            serviceType: .registerDevice,
            request: envelope
        ) { request, callOptions in
            try await self.deviceClient.registerDevice(request, callOptions: callOptions)
        }
    }

    // ... other methods
}
```

## Step 4: Update BaseRPCService

The `BaseRPCService.executeSecureEnvelopeCall` method currently uses a placeholder `SecureEnvelope` type. After generation, update it to use the generated type:

```swift
// Change from:
protected func executeSecureEnvelopeCall(
    serviceType: RPCServiceType,
    envelope: SecureEnvelope,  // Placeholder type
    call: @escaping (SecureEnvelope, CallOptions) async throws -> SecureEnvelope
) async -> Result<SecureEnvelope, NetworkFailure>

// To:
import Ecliptix_Proto_Common

protected func executeSecureEnvelopeCall(
    serviceType: RPCServiceType,
    envelope: Ecliptix_Proto_Common_SecureEnvelope,
    call: @escaping (Ecliptix_Proto_Common_SecureEnvelope, CallOptions) async throws -> Ecliptix_Proto_Common_SecureEnvelope
) async -> Result<Ecliptix_Proto_Common_SecureEnvelope, NetworkFailure>
```

## Step 5: Type Mapping

The Swift protobuf generator creates types with the following naming pattern:

| Proto Package | Proto Message | Generated Swift Type |
|---------------|---------------|---------------------|
| `ecliptix.proto.common` | `SecureEnvelope` | `Ecliptix_Proto_Common_SecureEnvelope` |
| `ecliptix.proto.membership` | `RegistrationRequest` | `Ecliptix_Proto_Membership_RegistrationRequest` |
| `ecliptix.proto.device` | `DeviceInfo` | `Ecliptix_Proto_Device_DeviceInfo` |

Service clients follow the pattern:
```
<Package>_<Service>AsyncClient
```

Examples:
- `Ecliptix_Proto_Membership_MembershipServicesAsyncClient`
- `Ecliptix_Proto_Device_DeviceServiceAsyncClient`

## Step 6: Build and Test

After updating the service clients:

```bash
cd /home/user/ecliptix-ios

# Build the project
swift build

# Run tests
swift test
```

## Step 7: Update ViewModels

Once service clients are wired up, update the ViewModels to use the real implementations:

### RegistrationViewModel.swift

```swift
public func startRegistration() {
    executeAsync {
        Log.info("[Registration] Starting registration for: \(self.mobileNumber)")

        // Create envelope (encrypted by protocol layer)
        let envelope = try await self.createRegistrationEnvelope()

        // Call real service
        let result = await self.membershipService.registrationInit(envelope: envelope)

        switch result {
        case .success(let responseEnvelope):
            // Process response
            try self.processRegistrationResponse(responseEnvelope)

        case .failure(let networkFailure):
            throw NetworkError.from(networkFailure)
        }

    } onSuccess: { _ in
        self.currentStep = .otpVerification
    }
}
```

### SignInViewModel.swift

Similar updates to use real service calls instead of placeholders.

## Common Issues and Solutions

### Issue: Import not found
```
error: no such module 'Ecliptix_Proto_Membership'
```

**Solution:** Run `./generate-protos.sh` to generate the protobuf code.

### Issue: Method not found on client
```
error: value of type 'Ecliptix_Proto_Membership_MembershipServicesAsyncClient' has no member 'registrationInit'
```

**Solution:** Check the proto file for the exact method name. Proto uses PascalCase, which gets converted to camelCase in Swift:
- Proto: `OpaqueRegistrationInitRequest` → Swift: `opaqueRegistrationInitRequest`

### Issue: Type mismatch
```
error: cannot convert value of type 'SecureEnvelope' to expected argument type 'Ecliptix_Proto_Common_SecureEnvelope'
```

**Solution:** Update the type definitions to use the generated protobuf types throughout the codebase.

## Testing Strategy

1. **Unit Tests:** Test each service client method with mock gRPC responses
2. **Integration Tests:** Test end-to-end flow with a test server
3. **Network Tests:** Test retry logic, timeout handling, error cases

## Next Migration Steps

After protobuf integration is complete:

1. ✅ Protobuf generation and service wiring
2. ⏭️ OPAQUE protocol integration (user will provide native library)
3. ⏭️ UI integration with ViewModels
4. ⏭️ End-to-end testing with C# backend
5. ⏭️ Production deployment

## Resources

- [PROTOBUF_SETUP.md](./PROTOBUF_SETUP.md) - Setup instructions
- [MembershipServiceClient+Example.swift](./Packages/EcliptixNetworking/Sources/Services/MembershipServiceClient+Example.swift) - Implementation examples
- [SwiftProtobuf Documentation](https://github.com/apple/swift-protobuf)
- [gRPC Swift Documentation](https://github.com/grpc/grpc-swift)
