import EcliptixCore
import Foundation

public final class SecureMemoryHandle: @unchecked Sendable {

    private var buffer: UnsafeMutableRawPointer?
    private let length: Int
    private var isDisposed: Bool = false

    public var count: Int {
        return length
    }

    public init(data: Data) {
        self.length = data.count

        self.buffer = UnsafeMutableRawPointer.allocate(
            byteCount: length,
            alignment: MemoryLayout<UInt8>.alignment
        )

        data.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                buffer?.copyMemory(from: baseAddress, byteCount: length)
            }
        }

        Log.debug("[SecureMemory] Allocated \(length) bytes of secure memory")
    }

    public init(size: Int) {
        self.length = size

        self.buffer = UnsafeMutableRawPointer.allocate(
            byteCount: length,
            alignment: MemoryLayout<UInt8>.alignment
        )
        buffer?.initializeMemory(as: UInt8.self, repeating: 0, count: length)

        Log.debug("[SecureMemory] Allocated \(length) bytes of zeroed secure memory")
    }

    deinit {
        dispose()
    }

    public func readData() throws -> Data {
        guard !isDisposed, let buffer = buffer else {
            throw SecureMemoryError.disposed
        }

        return Data(bytes: buffer, count: length)
    }

    public func readBytes() throws -> [UInt8] {
        guard !isDisposed, let buffer = buffer else {
            throw SecureMemoryError.disposed
        }

        let bufferPointer = buffer.bindMemory(to: UInt8.self, capacity: length)
        return Array(UnsafeBufferPointer(start: bufferPointer, count: length))
    }

    public func withUnsafeBytes<T>(_ body: (UnsafeRawBufferPointer) throws -> T) throws -> T {
        guard !isDisposed, let buffer = buffer else {
            throw SecureMemoryError.disposed
        }

        let bufferPointer = UnsafeRawBufferPointer(start: buffer, count: length)
        return try body(bufferPointer)
    }

    public func dispose() {
        guard !isDisposed, let buffer = buffer else {
            return
        }

        secureZeroMemory(buffer, length)

        buffer.deallocate()
        self.buffer = nil
        self.isDisposed = true

        Log.debug("[SecureMemory] Disposed \(length) bytes of secure memory")
    }

    private func secureZeroMemory(_ pointer: UnsafeMutableRawPointer, _ length: Int) {
        var volatilePointer = pointer.assumingMemoryBound(to: UInt8.self)
        for _ in 0..<length {
            volatilePointer.withMemoryRebound(to: UInt8.self, capacity: 1) { ptr in
                ptr.pointee = 0
            }
            volatilePointer = volatilePointer.advanced(by: 1)
        }

        withUnsafeMutablePointer(to: &volatilePointer) { ptr in
            _ = ptr
        }
    }

    public var disposed: Bool {
        return isDisposed
    }
}
public enum SecureMemoryError: LocalizedError {
    case disposed
    case allocationFailed
    case invalidSize

    public var errorDescription: String? {
        switch self {
        case .disposed:
            return "Secure memory handle has been disposed"
        case .allocationFailed:
            return "Failed to allocate secure memory"
        case .invalidSize:
            return "Invalid memory size"
        }
    }
}
extension SecureMemoryHandle {

    public static func fromHex(_ hex: String) throws -> SecureMemoryHandle {
        guard let data = Data(hexString: hex) else {
            throw SecureMemoryError.invalidSize
        }
        return SecureMemoryHandle(data: data)
    }

    public func toHex() throws -> String {
        let data = try readData()
        return data.map { String(format: "%02x", $0) }.joined()
    }
}
private extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex

        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            let byteString = hexString[index..<nextIndex]

            guard let num = UInt8(byteString, radix: 16) else {
                return nil
            }

            data.append(num)
            index = nextIndex
        }

        self = data
    }
}
