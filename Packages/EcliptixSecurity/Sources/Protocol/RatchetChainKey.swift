import Foundation
import EcliptixCore

// MARK: - Key Provider Protocol
/// Protocol for providing access to key material at specific ratchet indices
/// Migrated from: IKeyProvider in RatchetChainKey.cs
protocol KeyProvider: AnyObject {
    func executeWithKey<T>(
        keyIndex: UInt32,
        operation: (Data) -> Result<T, ProtocolFailure>
    ) -> Result<T, ProtocolFailure>
}

// MARK: - Ratchet Chain Key
/// Represents a key at a specific ratchet index with secure access to key material
/// Migrated from: Ecliptix.Protocol.System.Core.RatchetChainKey.cs
public final class RatchetChainKey: Equatable {

    private weak var keyProvider: KeyProvider?
    public let index: UInt32

    init(index: UInt32, keyProvider: KeyProvider) {
        self.index = index
        self.keyProvider = keyProvider
    }

    // MARK: - With Key Material
    /// Executes an operation with access to the key material
    /// The key material is only accessible during the operation closure
    /// Migrated from: WithKeyMaterial<T>()
    public func withKeyMaterial<T>(
        operation: (Data) -> Result<T, ProtocolFailure>
    ) -> Result<T, ProtocolFailure> {
        guard let provider = keyProvider else {
            return .failure(.generic("Key provider has been deallocated"))
        }
        return provider.executeWithKey(keyIndex: index, operation: operation)
    }

    // MARK: - Read Key Material
    /// Reads key material into a destination buffer
    /// Migrated from: ReadKeyMaterial(Span<byte> destination)
    public func readKeyMaterial(into destination: inout Data) -> Result<Unit, ProtocolFailure> {
        guard destination.count >= CryptographicConstants.aesKeySize else {
            return .failure(.bufferTooSmall(
                "Destination buffer must be at least \(CryptographicConstants.aesKeySize) bytes, but was \(destination.count)"
            ))
        }

        var tempBuffer = Data(count: CryptographicConstants.aesKeySize)
        let result = withKeyMaterial { keyMaterial in
            tempBuffer = Data(keyMaterial.prefix(CryptographicConstants.aesKeySize))
            return Result<Unit, ProtocolFailure>.success(.value)
        }

        if case .success = result {
            destination.replaceSubrange(0..<CryptographicConstants.aesKeySize, with: tempBuffer)
        }

        // Securely wipe temp buffer
        CryptographicHelpers.secureWipe(&tempBuffer)

        return result
    }

    // MARK: - Equatable
    public static func == (lhs: RatchetChainKey, rhs: RatchetChainKey) -> Bool {
        return lhs.index == rhs.index && lhs.keyProvider === rhs.keyProvider
    }
}
