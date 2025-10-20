import Foundation
import Crypto
import EcliptixCore

// MARK: - Ratchet Recovery
/// Stores and recovers skipped message keys for out-of-order message delivery
/// Migrated from: Ecliptix.Protocol.System/Core/RatchetRecovery.cs
public final class RatchetRecovery: KeyProvider {

    // MARK: - Properties
    private var skippedMessageKeys: [UInt32: Data] = [:]
    private let maxSkippedMessages: UInt32
    private let lock = NSLock()
    private var isDisposed = false

    // MARK: - Initialization
    public init(maxSkippedMessages: UInt32 = 1000) {
        self.maxSkippedMessages = maxSkippedMessages
    }

    deinit {
        dispose()
    }

    // MARK: - Try Recover Message Key
    /// Attempts to recover a previously skipped message key
    /// Migrated from: TryRecoverMessageKey()
    public func tryRecoverMessageKey(messageIndex: UInt32) -> Result<Option<RatchetChainKey>, ProtocolFailure> {
        guard !isDisposed else {
            return .failure(.generic("RatchetRecovery has been disposed"))
        }

        lock.lock()
        defer { lock.unlock() }

        if skippedMessageKeys[messageIndex] != nil {
            let messageKey = RatchetChainKey(index: messageIndex, keyProvider: self)
            return .success(.some(messageKey))
        }

        return .success(.none)
    }

    // MARK: - Store Skipped Message Keys
    /// Derives and stores message keys for skipped indices
    /// Migrated from: StoreSkippedMessageKeys()
    public func storeSkippedMessageKeys(
        currentChainKey: Data,
        fromIndex: UInt32,
        toIndex: UInt32
    ) -> Result<Unit, ProtocolFailure> {
        guard !isDisposed else {
            return .failure(.generic("RatchetRecovery has been disposed"))
        }

        guard toIndex > fromIndex else {
            return .success(.value)
        }

        lock.lock()
        defer { lock.unlock() }

        let skippedCount = toIndex - fromIndex
        if UInt32(skippedMessageKeys.count) + skippedCount > maxSkippedMessages {
            return .failure(.generic("Too many skipped messages: \(skippedMessageKeys.count + Int(skippedCount)) > \(maxSkippedMessages)"))
        }

        var chainKey = Data(currentChainKey)

        for index in fromIndex..<toIndex {
            // Derive message key
            guard case .success(let messageKey) = deriveMessageKey(from: chainKey, index: index) else {
                return .failure(.generic("Failed to derive message key for index \(index)"))
            }

            // Store it
            skippedMessageKeys[index] = messageKey

            // Advance chain key
            guard case .success(let nextChainKey) = advanceChainKey(chainKey) else {
                return .failure(.generic("Failed to advance chain key at index \(index)"))
            }

            chainKey = nextChainKey
        }

        // Secure wipe the chain key
        CryptographicHelpers.secureWipe(&chainKey)

        return .success(.value)
    }

    // MARK: - Derive Message Key
    private func deriveMessageKey(from chainKey: Data, index: UInt32) -> Result<Data, ProtocolFailure> {
        do {
            let messageKey = try HKDFKeyDerivation.deriveKey(
                inputKeyMaterial: chainKey,
                salt: nil,
                info: Data(CryptographicConstants.msgInfo),
                outputByteCount: CryptographicConstants.aesKeySize
            )
            return .success(messageKey)
        } catch {
            return .failure(.generic("Failed to derive message key for index \(index): \(error.localizedDescription)"))
        }
    }

    // MARK: - Advance Chain Key
    private func advanceChainKey(_ chainKey: Data) -> Result<Data, ProtocolFailure> {
        do {
            let nextChainKey = try HKDFKeyDerivation.deriveKey(
                inputKeyMaterial: chainKey,
                salt: nil,
                info: Data(CryptographicConstants.chainInfo),
                outputByteCount: CryptographicConstants.x25519KeySize
            )
            return .success(nextChainKey)
        } catch {
            return .failure(.generic("Failed to advance chain key: \(error.localizedDescription)"))
        }
    }

    // MARK: - Cleanup Old Keys
    /// Removes old skipped keys before a certain index
    public func cleanupOldKeys(beforeIndex: UInt32) {
        guard !isDisposed else { return }

        lock.lock()
        defer { lock.unlock() }

        let keysToRemove = skippedMessageKeys.keys.filter { $0 < beforeIndex }
        for key in keysToRemove {
            if var removedKey = skippedMessageKeys.removeValue(forKey: key) {
                CryptographicHelpers.secureWipe(&removedKey)
            }
        }
    }

    // MARK: - KeyProvider Implementation
    public func executeWithKey<T>(
        keyIndex: UInt32,
        operation: (Data) -> Result<T, ProtocolFailure>
    ) -> Result<T, ProtocolFailure> {
        guard !isDisposed else {
            return .failure(.generic("RatchetRecovery has been disposed"))
        }

        lock.lock()
        defer { lock.unlock() }

        guard let keyMaterial = skippedMessageKeys[keyIndex] else {
            return .failure(.generic("Skipped key with index \(keyIndex) not found"))
        }

        return operation(keyMaterial)
    }

    // MARK: - Dispose
    public func dispose() {
        guard !isDisposed else { return }

        lock.lock()
        defer { lock.unlock() }

        // Secure wipe all keys
        for (_, var key) in skippedMessageKeys {
            CryptographicHelpers.secureWipe(&key)
        }

        skippedMessageKeys.removeAll()
        isDisposed = true
    }
}
