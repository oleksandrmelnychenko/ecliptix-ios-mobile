import COpaqueClient
import EcliptixCore
import Foundation

public final class OpaqueClient {

    private var clientHandle: OpaqueClientHandleRef?
    private var stateHandle: OpaqueClientStateRef?
    private let serverPublicKey: Data

    public init(serverPublicKey: Data) throws {
        guard serverPublicKey.count == 32 else {
            throw OpaqueError.invalidInput("Server public key must be 32 bytes")
        }

        self.serverPublicKey = serverPublicKey

        var handle: OpaqueClientHandleRef?
        let rc: Int32 = serverPublicKey.withUnsafeBytes { keyBuf in
            opaque_client_create(
                keyBuf.bindMemory(to: UInt8.self).baseAddress,
                serverPublicKey.count,
                &handle
            )
        }

        guard rc == 0, let clientHandle = handle else {
            throw OpaqueError.nativeError(rc, "opaque_client_create")
        }

        self.clientHandle = clientHandle

        Log.info("[OpaqueClient] Initialized with server public key")
    }

    deinit {
        destroyState()
        destroyClient()
    }

    public func createRegistrationRequest(password: Data) throws -> Data {
        guard let clientHandle = clientHandle else {
            throw OpaqueError.nullHandle("client handle")
        }

        if stateHandle == nil {
            try createState()
        }

        guard let stateHandle = stateHandle else {
            throw OpaqueError.nullHandle("state handle")
        }

        var requestData = Data(count: 256)
        let capacity = requestData.count

        let rc: Int32 = requestData.withUnsafeMutableBytes { requestBytes -> Int32 in
            guard let requestPtr = requestBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1
            }
            return password.withUnsafeBytes { pwBytes -> Int32 in
                let pwPtr = pwBytes.bindMemory(to: UInt8.self).baseAddress
                return opaque_client_create_registration_request(
                    clientHandle,
                    pwPtr, password.count,
                    stateHandle,
                    requestPtr, capacity
                )
            }
        }

        guard rc == 0 else {
            throw OpaqueError.nativeError(rc, "create_registration_request")
        }

        Log.info("[OpaqueClient] Created registration request (\(requestData.count) bytes)")
        return requestData
    }

    public func finalizeRegistration(serverResponse: Data) throws -> Data {
        guard let clientHandle = clientHandle else {
            throw OpaqueError.nullHandle("client handle")
        }

        guard let stateHandle = stateHandle else {
            throw OpaqueError.nullHandle("state handle")
        }

        var recordData = Data(count: 256)
        let capacity = recordData.count

        let rc: Int32 = recordData.withUnsafeMutableBytes { recordBytes -> Int32 in
            guard let recordPtr = recordBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1
            }
            return serverResponse.withUnsafeBytes { (responseBytes: UnsafeRawBufferPointer) -> Int32 in
                guard let responsePtr = responseBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1
                }
                var masterKey = Data(count: 32)
                return masterKey.withUnsafeMutableBytes { (masterKeyBytes: UnsafeMutableRawBufferPointer) -> Int32 in
                    guard let masterKeyPtr = masterKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return -1
                    }
                    return opaque_client_finalize_registration(
                        clientHandle,
                        responsePtr, serverResponse.count,
                        masterKeyPtr, 32,
                        stateHandle,
                        recordPtr, capacity
                    )
                }
            }
        }

        guard rc == 0 else {
            throw OpaqueError.nativeError(rc, "finalize_registration")
        }

        Log.info("[OpaqueClient] [OK] Registration finalized (\(recordData.count) bytes)")

        destroyState()

        return recordData
    }

    public func generateKE1(password: Data) throws -> Data {
        guard let clientHandle = clientHandle else {
            throw OpaqueError.nullHandle("client handle")
        }

        destroyState()
        try createState()

        guard let stateHandle = stateHandle else {
            throw OpaqueError.nullHandle("state handle")
        }

        var ke1Data = Data(count: 128)
        let capacity = ke1Data.count

        let rc: Int32 = ke1Data.withUnsafeMutableBytes { ke1Bytes -> Int32 in
            guard let ke1Ptr = ke1Bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1
            }
            return password.withUnsafeBytes { pwBytes -> Int32 in
                let pwPtr = pwBytes.bindMemory(to: UInt8.self).baseAddress
                return opaque_client_generate_ke1(
                    clientHandle,
                    pwPtr, password.count,
                    stateHandle,
                    ke1Ptr, capacity
                )
            }
        }

        guard rc == 0 else {
            throw OpaqueError.nativeError(rc, "generate_ke1")
        }

        Log.info("[OpaqueClient] Generated KE1 (\(ke1Data.count) bytes)")
        return ke1Data
    }

    public func generateKE3(ke2: Data) throws -> Data {
        guard let clientHandle = clientHandle else {
            throw OpaqueError.nullHandle("client handle")
        }

        guard let stateHandle = stateHandle else {
            throw OpaqueError.nullHandle("state handle")
        }

        var ke3Data = Data(count: 128)
        let capacity = ke3Data.count

        let rc: Int32 = ke3Data.withUnsafeMutableBytes { ke3Bytes -> Int32 in
            guard let ke3Ptr = ke3Bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1
            }
            return ke2.withUnsafeBytes { ke2Bytes -> Int32 in
                let ke2Ptr = ke2Bytes.bindMemory(to: UInt8.self).baseAddress
                return opaque_client_generate_ke3(
                    clientHandle,
                    ke2Ptr, ke2.count,
                    stateHandle,
                    ke3Ptr, capacity
                )
            }
        }

        guard rc == 0 else {
            throw OpaqueError.nativeError(rc, "generate_ke3")
        }

        Log.info("[OpaqueClient] Generated KE3 (\(ke3Data.count) bytes)")
        return ke3Data
    }

    public func finishAuthentication() throws -> Data {
        guard let clientHandle = clientHandle else {
            throw OpaqueError.nullHandle("client handle")
        }

        guard let stateHandle = stateHandle else {
            throw OpaqueError.nullHandle("state handle")
        }

        var sessionKey = Data(count: 64)
        let capacity = sessionKey.count

        var masterKey = Data(count: 32)
        let rc: Int32 = sessionKey.withUnsafeMutableBytes { (keyBytes: UnsafeMutableRawBufferPointer) -> Int32 in
            guard let keyPtr = keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1
            }
            return masterKey.withUnsafeMutableBytes { (masterKeyBytes: UnsafeMutableRawBufferPointer) -> Int32 in
                guard let masterKeyPtr = masterKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1
                }
                return opaque_client_finish(
                    clientHandle,
                    stateHandle,
                    keyPtr, capacity,
                    masterKeyPtr, 32
                )
            }
        }

        guard rc == 0 else {
            throw OpaqueError.nativeError(rc, "client_finish")
        }

        Log.info("[OpaqueClient] [OK] Authentication completed, session key derived")

        destroyState()

        return sessionKey
    }

    private func createState() throws {
        var handle: OpaqueClientStateRef?
        let rc: Int32 = opaque_client_state_create(&handle)

        guard rc == 0, let stateHandle = handle else {
            throw OpaqueError.nativeError(rc, "opaque_client_state_create")
        }

        self.stateHandle = stateHandle
    }

    private func destroyState() {
        if let handle = stateHandle {
            opaque_client_state_destroy(handle)
            stateHandle = nil
        }
    }

    private func destroyClient() {
        if let handle = clientHandle {
            opaque_client_destroy(handle)
            clientHandle = nil
        }
    }
}

public enum OpaqueError: Error, CustomStringConvertible {
    case nullHandle(String)
    case invalidInput(String)
    case nativeError(Int32, String)

    public var description: String {
        switch self {
        case .nullHandle(let handle):
            return "Null handle: \(handle)"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .nativeError(let code, let operation):
            return "OPAQUE error in \(operation): code=\(code)"
        }
    }
}

public typealias OpaqueClientHandleRef = UnsafeMutableRawPointer
public typealias OpaqueClientStateRef = UnsafeMutableRawPointer

public enum OpaqueConstants {
    public static let serverPublicKeyLength = 32
    public static let registrationRequestLength = 32
    public static let registrationResponseLength = 96
    public static let registrationRecordLength = 176
    public static let ke1Length = 96
    public static let ke2Length = 304
    public static let ke3Length = 64
    public static let sessionKeyLength = 64
}
