import XCTest
import Crypto
@testable import EcliptixSecurity
@testable import EcliptixCore

final class RatchetingTests: XCTestCase {

    // MARK: - Test Chain Step Creation
    func testCreateChainStep() {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        let result = ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: initialChainKey
        )

        XCTAssertTrue(result.isSuccess)
        if case .success(let step) = result {
            let indexResult = step.getCurrentIndex()
            XCTAssertTrue(indexResult.isSuccess)
            if case .success(let index) = indexResult {
                XCTAssertEqual(index, 0)
            }
        }
    }

    // MARK: - Test Invalid Chain Key Size
    func testCreateChainStepWithInvalidKeySize() {
        let invalidChainKey = Data(count: 16) // Wrong size

        let result = ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: invalidChainKey
        )

        XCTAssertTrue(result.isFailure)
    }

    // MARK: - Test Key Derivation
    func testKeyDerivation() {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        let result = ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: initialChainKey
        )

        guard case .success(let step) = result else {
            XCTFail("Failed to create chain step")
            return
        }

        // Derive key for index 1
        let keyResult = step.getOrDeriveKeyFor(targetIndex: 1)

        XCTAssertTrue(keyResult.isSuccess)
        if case .success(let ratchetKey) = keyResult {
            XCTAssertEqual(ratchetKey.index, 1)

            // Verify current index was updated
            let indexResult = step.getCurrentIndex()
            if case .success(let currentIndex) = indexResult {
                XCTAssertEqual(currentIndex, 1)
            }
        }
    }

    // MARK: - Test Multiple Key Derivations
    func testMultipleKeyDerivations() {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        let result = ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: initialChainKey
        )

        guard case .success(let step) = result else {
            XCTFail("Failed to create chain step")
            return
        }

        // Derive keys for indices 1, 2, 3
        for index: UInt32 in 1...3 {
            let keyResult = step.getOrDeriveKeyFor(targetIndex: index)
            XCTAssertTrue(keyResult.isSuccess)

            if case .success(let ratchetKey) = keyResult {
                XCTAssertEqual(ratchetKey.index, index)
            }
        }

        // Verify final index
        let indexResult = step.getCurrentIndex()
        if case .success(let currentIndex) = indexResult {
            XCTAssertEqual(currentIndex, 3)
        }
    }

    // MARK: - Test Key Caching
    func testKeyCaching() {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        let result = ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: initialChainKey
        )

        guard case .success(let step) = result else {
            XCTFail("Failed to create chain step")
            return
        }

        // Derive key for index 1
        let firstKeyResult = step.getOrDeriveKeyFor(targetIndex: 1)
        guard case .success(let firstKey) = firstKeyResult else {
            XCTFail("Failed to derive first key")
            return
        }

        // Get same key again (should use cache)
        let secondKeyResult = step.getOrDeriveKeyFor(targetIndex: 1)
        guard case .success(let secondKey) = secondKeyResult else {
            XCTFail("Failed to get cached key")
            return
        }

        // Keys should have same index
        XCTAssertEqual(firstKey.index, secondKey.index)
    }

    // MARK: - Test Cannot Go Backwards
    func testCannotDerivePastIndex() {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        let result = ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: initialChainKey
        )

        guard case .success(let step) = result else {
            XCTFail("Failed to create chain step")
            return
        }

        // Derive key for index 5
        _ = step.getOrDeriveKeyFor(targetIndex: 5)

        // Try to derive key for index 3 (should fail)
        let backwardsResult = step.getOrDeriveKeyFor(targetIndex: 3)
        XCTAssertTrue(backwardsResult.isFailure)
    }

    // MARK: - Test Skip Keys
    func testSkipKeys() {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        let result = ProtocolChainStep.create(
            stepType: .receiving,
            initialChainKey: initialChainKey
        )

        guard case .success(let step) = result else {
            XCTFail("Failed to create chain step")
            return
        }

        // Skip keys until index 10
        let skipResult = step.skipKeysUntil(targetIndex: 10)
        XCTAssertTrue(skipResult.isSuccess)

        // Verify current index
        let indexResult = step.getCurrentIndex()
        if case .success(let currentIndex) = indexResult {
            XCTAssertEqual(currentIndex, 10)
        }
    }

    // MARK: - Test Key Material Access
    func testKeyMaterialAccess() {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        let result = ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: initialChainKey
        )

        guard case .success(let step) = result else {
            XCTFail("Failed to create chain step")
            return
        }

        // Derive key
        let keyResult = step.getOrDeriveKeyFor(targetIndex: 1)
        guard case .success(let ratchetKey) = keyResult else {
            XCTFail("Failed to derive key")
            return
        }

        // Access key material
        var destination = Data(count: CryptographicConstants.aesKeySize)
        let readResult = ratchetKey.readKeyMaterial(into: &destination)

        XCTAssertTrue(readResult.isSuccess)
        XCTAssertEqual(destination.count, CryptographicConstants.aesKeySize)
        XCTAssertNotEqual(destination, Data(count: CryptographicConstants.aesKeySize)) // Should not be all zeros
    }

    // MARK: - Test DH Keys
    func testChainStepWithDHKeys() {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        let x25519 = X25519KeyExchange()
        let (privateKey, publicKey) = x25519.generateKeyPair()
        let privateBytes = x25519.privateKeyToBytes(privateKey)
        let publicBytes = x25519.publicKeyToBytes(publicKey)

        let result = ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: initialChainKey,
            initialDhPrivateKey: privateBytes,
            initialDhPublicKey: publicBytes
        )

        XCTAssertTrue(result.isSuccess)

        if case .success(let step) = result {
            let dhPublicKey = step.getDhPublicKey()
            XCTAssertNotNil(dhPublicKey)
            XCTAssertEqual(dhPublicKey?.count, CryptographicConstants.x25519KeySize)
            XCTAssertEqual(dhPublicKey, publicBytes)
        }
    }

    // MARK: - Test Invalid DH Keys
    func testChainStepWithOnlyPrivateDHKey() {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        let privateKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519PrivateKeySize
        )

        let result = ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: initialChainKey,
            initialDhPrivateKey: privateKey,
            initialDhPublicKey: nil // Missing public key
        )

        XCTAssertTrue(result.isFailure)
    }

    // MARK: - Test Key Determinism
    func testKeyDerivationIsDeterministic() {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        // Create two chain steps with same initial key
        let result1 = ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: initialChainKey
        )

        let result2 = ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: Data(initialChainKey) // Copy
        )

        guard case .success(let step1) = result1,
              case .success(let step2) = result2 else {
            XCTFail("Failed to create chain steps")
            return
        }

        // Derive same key index on both
        let keyResult1 = step1.getOrDeriveKeyFor(targetIndex: 5)
        let keyResult2 = step2.getOrDeriveKeyFor(targetIndex: 5)

        guard case .success(let ratchetKey1) = keyResult1,
              case .success(let ratchetKey2) = keyResult2 else {
            XCTFail("Failed to derive keys")
            return
        }

        // Read key materials
        var data1 = Data(count: CryptographicConstants.aesKeySize)
        var data2 = Data(count: CryptographicConstants.aesKeySize)

        _ = ratchetKey1.readKeyMaterial(into: &data1)
        _ = ratchetKey2.readKeyMaterial(into: &data2)

        // Keys should be identical (deterministic derivation)
        XCTAssertEqual(data1, data2)
    }

    // MARK: - Test Disposal
    func testDisposal() {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        let result = ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: initialChainKey
        )

        guard case .success(let step) = result else {
            XCTFail("Failed to create chain step")
            return
        }

        // Dispose the chain step
        step.dispose()

        // Operations should fail after disposal
        let keyResult = step.getOrDeriveKeyFor(targetIndex: 1)
        XCTAssertTrue(keyResult.isFailure)
    }
}
