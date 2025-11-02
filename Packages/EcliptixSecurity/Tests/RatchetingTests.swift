import Crypto
import XCTest

@testable import EcliptixSecurity
@testable import EcliptixCore

final class RatchetingTests: XCTestCase {
    func testCreateChainStep() throws {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        let step = try ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: initialChainKey
        )

        let index = try step.getCurrentIndex()
        XCTAssertEqual(index, 0)
    }
    func testCreateChainStepWithInvalidKeySize() throws {
        let invalidChainKey = Data(count: 16)

        XCTAssertThrowsError(try ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: invalidChainKey
        ))
    }
    func testKeyDerivation() throws {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        let step = try ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: initialChainKey
        )

        let ratchetKey = try step.getOrDeriveKeyFor(targetIndex: 1)
        XCTAssertEqual(ratchetKey.index, 1)

        let currentIndex = try step.getCurrentIndex()
        XCTAssertEqual(currentIndex, 1)
    }
    func testMultipleKeyDerivations() throws {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        let step = try ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: initialChainKey
        )

        for index: UInt32 in 1...3 {
            let ratchetKey = try step.getOrDeriveKeyFor(targetIndex: index)
            XCTAssertEqual(ratchetKey.index, index)
        }

        let currentIndex = try step.getCurrentIndex()
        XCTAssertEqual(currentIndex, 3)
    }
    func testKeyCaching() throws {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        let step = try ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: initialChainKey
        )

        let firstKey = try step.getOrDeriveKeyFor(targetIndex: 1)

        let secondKey = try step.getOrDeriveKeyFor(targetIndex: 1)

        XCTAssertEqual(firstKey.index, secondKey.index)
    }
    func testCannotDerivePastIndex() throws {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        let step = try ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: initialChainKey
        )

        _ = try step.getOrDeriveKeyFor(targetIndex: 5)

        let cachedKey = try step.getOrDeriveKeyFor(targetIndex: 3)
        XCTAssertEqual(cachedKey.index, 3)

    }
    func testSkipKeys() throws {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        let step = try ProtocolChainStep.create(
            stepType: .receiving,
            initialChainKey: initialChainKey
        )

        try step.skipKeysUntil(targetIndex: 10)

        let currentIndex = try step.getCurrentIndex()
        XCTAssertEqual(currentIndex, 10)
    }
    func testKeyMaterialAccess() throws {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        let step = try ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: initialChainKey
        )

        let ratchetKey = try step.getOrDeriveKeyFor(targetIndex: 1)

        var destination = Data(count: CryptographicConstants.aesKeySize)
        try ratchetKey.readKeyMaterial(into: &destination)

        XCTAssertEqual(destination.count, CryptographicConstants.aesKeySize)
        XCTAssertNotEqual(destination, Data(count: CryptographicConstants.aesKeySize))
    }
    func testChainStepWithDHKeys() throws {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        let x25519 = X25519KeyExchange()
        let (privateKey, publicKey) = x25519.generateKeyPair()
        let privateBytes = x25519.privateKeyToBytes(privateKey)
        let publicBytes = x25519.publicKeyToBytes(publicKey)

        let step = try ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: initialChainKey,
            initialDhPrivateKey: privateBytes,
            initialDhPublicKey: publicBytes
        )

        let dhPublicKey = step.getDhPublicKey()
        XCTAssertNotNil(dhPublicKey)
        XCTAssertEqual(dhPublicKey?.count, CryptographicConstants.x25519KeySize)
        XCTAssertEqual(dhPublicKey, publicBytes)
    }
    func testChainStepWithOnlyPrivateDHKey() throws {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        let privateKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519PrivateKeySize
        )

        XCTAssertThrowsError(try ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: initialChainKey,
            initialDhPrivateKey: privateKey,
            initialDhPublicKey: nil
        ))
    }
    func testKeyDerivationIsDeterministic() throws {
        let initialChainKey = CryptographicHelpers.generateRandomBytes(
            count: CryptographicConstants.x25519KeySize
        )

        let step1 = try ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: initialChainKey
        )

        let step2 = try ProtocolChainStep.create(
            stepType: .sending,
            initialChainKey: Data(initialChainKey)
        )

        let ratchetKey1 = try step1.getOrDeriveKeyFor(targetIndex: 5)
        let ratchetKey2 = try step2.getOrDeriveKeyFor(targetIndex: 5)

        var data1 = Data(count: CryptographicConstants.aesKeySize)
        var data2 = Data(count: CryptographicConstants.aesKeySize)

        try ratchetKey1.readKeyMaterial(into: &data1)
        try ratchetKey2.readKeyMaterial(into: &data2)

        XCTAssertEqual(data1, data2)
    }

}
