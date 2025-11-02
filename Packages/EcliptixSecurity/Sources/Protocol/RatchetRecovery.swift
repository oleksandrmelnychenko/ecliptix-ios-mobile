import Crypto
import EcliptixCore
import Foundation

public final class RatchetRecovery: @unchecked Sendable, KeyProvider {
    private var skippedMessageKeys: [UInt32: Data] = [:]
    private let maxSkippedMessages: UInt32
    private let lock = NSLock()

    private let storage: SkippedMessageKeysStorage?
    private let connectId: String?
    private let membershipId: UUID?
    private var isDirty: Bool = false

    public init(maxSkippedMessages: UInt32 = 1000) {
        self.maxSkippedMessages = maxSkippedMessages
        self.storage = nil
        self.connectId = nil
        self.membershipId = nil
    }

    public init(
        maxSkippedMessages: UInt32 = 1000,
        storage: SkippedMessageKeysStorage,
        connectId: String,
        membershipId: UUID
    ) async throws {
        self.maxSkippedMessages = maxSkippedMessages
        self.storage = storage
        self.connectId = connectId
        self.membershipId = membershipId

        do {
            self.skippedMessageKeys = try await storage.loadKeys(
                connectId: connectId,
                membershipId: membershipId
            )
            Log.info("[RatchetRecovery] [OK] Loaded \(skippedMessageKeys.count) skipped keys from storage")
        } catch {
            Log.warning("[RatchetRecovery] Failed to load skipped keys, starting fresh: \(error.localizedDescription)")
            self.skippedMessageKeys = [:]
        }
    }

    deinit {

        for (_, var key) in skippedMessageKeys {
            CryptographicHelpers.secureWipe(&key)
        }
    }

    public func tryRecoverMessageKey(messageIndex: UInt32) -> RatchetChainKey? {
        lock.lock()
        defer { lock.unlock() }

        if skippedMessageKeys[messageIndex] != nil {
            return RatchetChainKey(index: messageIndex, keyProvider: self)
        }

        return nil
    }

    public func storeSkippedMessageKeys(
        currentChainKey: Data,
        fromIndex: UInt32,
        toIndex: UInt32
    ) throws {
        guard toIndex > fromIndex else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        let skippedCount = toIndex - fromIndex
        if UInt32(skippedMessageKeys.count) + skippedCount > maxSkippedMessages {
            throw ProtocolFailure.generic("Too many skipped messages: \(skippedMessageKeys.count + Int(skippedCount)) > \(maxSkippedMessages)")
        }

        var chainKey = Data(currentChainKey)
        defer {

            CryptographicHelpers.secureWipe(&chainKey)
        }

        for index in fromIndex..<toIndex {

            let messageKey = try deriveMessageKey(from: chainKey, index: index)

            skippedMessageKeys[index] = messageKey

            chainKey = try advanceChainKey(chainKey)
        }

        isDirty = true

        Task { [weak self] in
            await self?.persistIfNeeded()
        }
    }
    private func deriveMessageKey(from chainKey: Data, index: UInt32) throws -> Data {
        do {
            let messageKey = try HKDFKeyDerivation.deriveKey(
                inputKeyMaterial: chainKey,
                salt: nil,
                info: Data(CryptographicConstants.msgInfo),
                outputByteCount: CryptographicConstants.aesKeySize
            )
            return messageKey
        } catch {
            throw ProtocolFailure.generic("Failed to derive message key for index \(index): \(error.localizedDescription)")
        }
    }
    private func advanceChainKey(_ chainKey: Data) throws -> Data {
        do {
            let nextChainKey = try HKDFKeyDerivation.deriveKey(
                inputKeyMaterial: chainKey,
                salt: nil,
                info: Data(CryptographicConstants.chainInfo),
                outputByteCount: CryptographicConstants.x25519KeySize
            )
            return nextChainKey
        } catch {
            throw ProtocolFailure.generic("Failed to advance chain key: \(error.localizedDescription)")
        }
    }

    public func cleanupOldKeys(beforeIndex: UInt32) {
        lock.lock()
        defer { lock.unlock() }

        let keysToRemove = skippedMessageKeys.keys.filter { $0 < beforeIndex }
        guard !keysToRemove.isEmpty else { return }

        for key in keysToRemove {
            if var removedKey = skippedMessageKeys.removeValue(forKey: key) {
                CryptographicHelpers.secureWipe(&removedKey)
            }
        }

        isDirty = true

        Task { [weak self] in
            await self?.persistIfNeeded()
        }
    }

    private func persistIfNeeded() async {
        guard let storage = storage,
              let connectId = connectId,
              let membershipId = membershipId else {
            return
        }

        let shouldPersist = lock.withLock { isDirty }
        guard shouldPersist else { return }

        let keysToPersist = lock.withLock {
            let keys = skippedMessageKeys
            isDirty = false
            return keys
        }

        do {
            try await storage.saveKeys(
                keysToPersist,
                connectId: connectId,
                membershipId: membershipId
            )
            Log.debug("[RatchetRecovery] [OK] Persisted \(keysToPersist.count) skipped keys")
        } catch {
            Log.error("[RatchetRecovery] Failed to persist skipped keys: \(error.localizedDescription)")

            lock.withLock {
                isDirty = true
            }
        }
    }

    public func flushToStorage() async throws {
        guard let storage = storage,
              let connectId = connectId,
              let membershipId = membershipId else {
            return
        }

        let keysToPersist = lock.withLock {
            let keys = skippedMessageKeys
            isDirty = false
            return keys
        }

        try await storage.saveKeys(
            keysToPersist,
            connectId: connectId,
            membershipId: membershipId
        )
        Log.info("[RatchetRecovery] [OK] Flushed \(keysToPersist.count) skipped keys to storage")
    }

    public func clearStorage() async throws {
        guard let storage = storage,
              let connectId = connectId,
              let membershipId = membershipId else {
            return
        }

        try await storage.deleteKeys(connectId: connectId, membershipId: membershipId)
        Log.info("[RatchetRecovery] Cleared skipped keys from storage")
    }
    public func executeWithKey<T>(
        keyIndex: UInt32,
        operation: (Data) throws -> T
    ) throws -> T {
        lock.lock()

        guard let keyMaterial = skippedMessageKeys[keyIndex] else {
            lock.unlock()
            throw ProtocolFailure.generic("Skipped key with index \(keyIndex) not found")
        }

        let result = try operation(keyMaterial)

        if var removedKey = skippedMessageKeys.removeValue(forKey: keyIndex) {
            CryptographicHelpers.secureWipe(&removedKey)
        }

        isDirty = true

        lock.unlock()

        Task { [weak self] in
            await self?.persistIfNeeded()
        }

        return result
    }
}
