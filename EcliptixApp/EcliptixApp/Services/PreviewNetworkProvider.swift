import EcliptixCore
import EcliptixNetworking
import Foundation

final class PreviewNetworkProvider: NetworkProviderProtocol {

    func executeUnaryRequest(
        connectId: UInt32,
        serviceType: NetworkProvider.RPCServiceType,
        plainBuffer: Data,
        allowDuplicates: Bool,
        waitForRecovery: Bool,
        onCompleted: @escaping (Data) async throws -> Void
    ) async -> Result<Void, NetworkFailure> {
        return .failure(NetworkFailure(
            type: .unavailable,
            message: "Preview mode - network not available"
        ))
    }

    func executeStreamingRequest(
        connectId: UInt32,
        serviceType: NetworkProvider.RPCServiceType,
        plainBuffer: Data,
        allowDuplicates: Bool,
        waitForRecovery: Bool,
        onMessage: @escaping (Data) async throws -> Void
    ) async -> Result<Void, NetworkFailure> {
        return .failure(NetworkFailure(
            type: .unavailable,
            message: "Preview mode - network not available"
        ))
    }
}
