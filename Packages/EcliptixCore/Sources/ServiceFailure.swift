import Foundation

// MARK: - Service Failure Types
/// Represents failures that can occur in internal services
public enum ServiceFailure: LocalizedError, Equatable {
    case secureStoreKeyNotFound(String)
    case secureStoreAccessDenied(String, String?)
    case secureStoreEncryptionFailed(String)
    case secureStoreDecryptionFailed(String)
    case networkError(String)
    case invalidData(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .secureStoreKeyNotFound(let message):
            return "Secure Store Key Not Found: \(message)"
        case .secureStoreAccessDenied(let message, let detail):
            if let detail = detail {
                return "Secure Store Access Denied: \(message) - \(detail)"
            }
            return "Secure Store Access Denied: \(message)"
        case .secureStoreEncryptionFailed(let message):
            return "Encryption Failed: \(message)"
        case .secureStoreDecryptionFailed(let message):
            return "Decryption Failed: \(message)"
        case .networkError(let message):
            return "Network Error: \(message)"
        case .invalidData(let message):
            return "Invalid Data: \(message)"
        case .unknown(let message):
            return "Unknown Error: \(message)"
        }
    }

    public var message: String {
        return errorDescription ?? "Unknown error"
    }

    public static func == (lhs: ServiceFailure, rhs: ServiceFailure) -> Bool {
        return lhs.message == rhs.message
    }
}

// MARK: - Application Error Messages
public struct ApplicationErrorMessages {
    public struct SecureStorageProvider {
        public static let applicationSettingsNotFound = "Application settings not found in secure storage"
        public static let corruptSettingsData = "Settings data is corrupted or invalid"
        public static let failedToEncryptData = "Failed to encrypt data for secure storage"
        public static let failedToDecryptData = "Failed to decrypt data from secure storage"
        public static let failedToWriteToStorage = "Failed to write to secure storage"
        public static let failedToAccessStorage = "Failed to access secure storage"
        public static let failedToDeleteFromStorage = "Failed to delete from secure storage"
        public static let secureStorageDirectoryCreationFailed = "Failed to create secure storage directory at %@"
    }
}
