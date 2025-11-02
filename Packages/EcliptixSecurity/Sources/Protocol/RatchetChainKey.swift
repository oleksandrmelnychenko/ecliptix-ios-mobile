import EcliptixCore
import Foundation

protocol KeyProvider: AnyObject {
    func executeWithKey<T>(
        keyIndex: UInt32,
        operation: (Data) throws -> T
    ) throws -> T
}

public final class RatchetChainKey: Equatable {

    private weak var keyProvider: KeyProvider?
    public let index: UInt32

    init(index: UInt32, keyProvider: KeyProvider) {
        self.index = index
        self.keyProvider = keyProvider
    }

    public func withKeyMaterial<T>(
        operation: (Data) throws -> T
    ) throws -> T {
        guard let provider = keyProvider else {
            throw ProtocolFailure.generic("Key provider has been deallocated")
        }
        return try provider.executeWithKey(keyIndex: index, operation: operation)
    }

    public func readKeyMaterial(into destination: inout Data) throws {
        guard destination.count >= CryptographicConstants.aesKeySize else {
            throw ProtocolFailure.bufferTooSmall(
                "Destination buffer must be at least \(CryptographicConstants.aesKeySize) bytes, but was \(destination.count)"
            )
        }

        var tempBuffer = Data(count: CryptographicConstants.aesKeySize)
        defer {

            CryptographicHelpers.secureWipe(&tempBuffer)
        }

        try withKeyMaterial { keyMaterial in
            tempBuffer = Data(keyMaterial.prefix(CryptographicConstants.aesKeySize))
        }

        destination.replaceSubrange(0..<CryptographicConstants.aesKeySize, with: tempBuffer)
    }
    public static func == (lhs: RatchetChainKey, rhs: RatchetChainKey) -> Bool {
        return lhs.index == rhs.index && lhs.keyProvider === rhs.keyProvider
    }
}
