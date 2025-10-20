import Foundation
import UIKit
import Crypto
import EcliptixCore

// MARK: - Application Secure Storage Provider
/// Provides secure storage for application settings (migrated from C# ApplicationSecureStorageProvider)
/// This is a direct port of the desktop application's secure storage implementation
public final class ApplicationSecureStorageProvider {
    private static let settingsKey = "ApplicationInstanceSettings"

    private let fileStorage: EncryptedFileStorage
    private let logger: Logger

    public init(logger: Logger = Log) throws {
        // Initialize encrypted file storage
        // Note: In production, the encryption key should be stored in Keychain
        self.fileStorage = try EncryptedFileStorage()
        self.logger = logger
    }

    // MARK: - Set Application Settings Culture
    public func setApplicationSettingsCulture(_ culture: String?) async -> Result<Unit, ServiceFailure> {
        let settingsResult = await getApplicationInstanceSettings()

        switch settingsResult {
        case .failure(let error):
            return .failure(error)
        case .success(var settings):
            settings.culture = culture
            return await storeSettings(settings)
        }
    }

    // MARK: - Set Application Instance
    public func setApplicationInstance(isNewInstance: Bool) async -> Result<Unit, ServiceFailure> {
        let settingsResult = await getApplicationInstanceSettings()

        switch settingsResult {
        case .failure(let error):
            return .failure(error)
        case .success(var settings):
            settings.isNewInstance = isNewInstance
            return await storeSettings(settings)
        }
    }

    // MARK: - Set Application IP Country
    public func setApplicationIPCountry(country: String, ipAddress: String) async -> Result<Unit, ServiceFailure> {
        let settingsResult = await getApplicationInstanceSettings()

        switch settingsResult {
        case .failure(let error):
            return .failure(error)
        case .success(var settings):
            settings.country = country
            settings.ipAddress = ipAddress
            return await storeSettings(settings)
        }
    }

    // MARK: - Set Application Membership
    public func setApplicationMembership(_ membership: MembershipInfo?) async -> Result<Unit, ServiceFailure> {
        let settingsResult = await getApplicationInstanceSettings()

        switch settingsResult {
        case .failure(let error):
            return .failure(error)
        case .success(var settings):
            settings.membership = membership
            return await storeSettings(settings)
        }
    }

    // MARK: - Get Application Instance Settings
    public func getApplicationInstanceSettings() async -> Result<ApplicationInstanceSettings, ServiceFailure> {
        let getResult = await tryGetByKey(Self.settingsKey)

        switch getResult {
        case .failure(let error):
            return .failure(error)
        case .success(let option):
            if let data = option.value {
                do {
                    let decoder = JSONDecoder()
                    let settings = try decoder.decode(ApplicationInstanceSettings.self, from: data)
                    return .success(settings)
                } catch {
                    return .failure(.invalidData(ApplicationErrorMessages.SecureStorageProvider.corruptSettingsData))
                }
            } else {
                return .failure(.secureStoreKeyNotFound(ApplicationErrorMessages.SecureStorageProvider.applicationSettingsNotFound))
            }
        }
    }

    // MARK: - Initialize Application Instance Settings
    public func initApplicationInstanceSettings(defaultCulture: String?) async -> Result<InstanceSettingsResult, ServiceFailure> {
        let getResult = await tryGetByKey(Self.settingsKey)

        switch getResult {
        case .failure(let error):
            logger.warning("[SETTINGS-INIT-RECOVERY] Storage access failed, creating fresh settings. Error: \(error.message)")
            return await createAndStoreNewSettings(defaultCulture: defaultCulture)

        case .success(let option):
            if let data = option.value {
                do {
                    let decoder = JSONDecoder()
                    let settings = try decoder.decode(ApplicationInstanceSettings.self, from: data)
                    return .success(InstanceSettingsResult(settings: settings, isNewInstance: false))
                } catch {
                    logger.warning("[SETTINGS-INIT-RECOVERY] Settings parsing failed, creating fresh settings. Error: \(error.localizedDescription)")
                    return await createAndStoreNewSettings(defaultCulture: defaultCulture)
                }
            } else {
                return await createAndStoreNewSettings(defaultCulture: defaultCulture)
            }
        }
    }

    // MARK: - Create and Store New Settings
    private func createAndStoreNewSettings(defaultCulture: String?) async -> Result<InstanceSettingsResult, ServiceFailure> {
        let newSettings = ApplicationInstanceSettings(
            appInstanceId: UUID(),
            deviceId: UUID(),
            systemDeviceIdentifier: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            serverPublicKey: nil,
            culture: defaultCulture,
            country: nil,
            ipAddress: nil,
            isNewInstance: true,
            membership: nil
        )

        let storeResult = await storeSettings(newSettings)

        if case .failure(let error) = storeResult {
            logger.warning("[SETTINGS-INIT-RECOVERY] Failed to persist fresh settings, continuing in-memory. Error: \(error.message)")
        }

        return .success(InstanceSettingsResult(settings: newSettings, isNewInstance: true))
    }

    // MARK: - Store Settings
    private func storeSettings(_ settings: ApplicationInstanceSettings) async -> Result<Unit, ServiceFailure> {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(settings)
            return await store(Self.settingsKey, data: data)
        } catch {
            return .failure(.secureStoreEncryptionFailed(ApplicationErrorMessages.SecureStorageProvider.failedToEncryptData))
        }
    }

    // MARK: - Store Data
    private func store(_ key: String, data: Data) async -> Result<Unit, ServiceFailure> {
        do {
            try fileStorage.store(data, forKey: key)
            return .success(.value)
        } catch let error as SecurityError {
            switch error {
            case .encryptionFailed:
                return .failure(.secureStoreEncryptionFailed(ApplicationErrorMessages.SecureStorageProvider.failedToEncryptData))
            default:
                return .failure(.secureStoreAccessDenied(ApplicationErrorMessages.SecureStorageProvider.failedToWriteToStorage, error.localizedDescription))
            }
        } catch {
            return .failure(.secureStoreAccessDenied(ApplicationErrorMessages.SecureStorageProvider.failedToWriteToStorage, error.localizedDescription))
        }
    }

    // MARK: - Try Get By Key
    private func tryGetByKey(_ key: String) async -> Result<Option<Data>, ServiceFailure> {
        do {
            if let data = try fileStorage.retrieve(forKey: key) {
                return .success(.some(data))
            } else {
                return .success(.none)
            }
        } catch let error as SecurityError {
            switch error {
            case .decryptionFailed:
                return .failure(.secureStoreDecryptionFailed(ApplicationErrorMessages.SecureStorageProvider.failedToDecryptData))
            default:
                return .failure(.secureStoreAccessDenied(ApplicationErrorMessages.SecureStorageProvider.failedToAccessStorage, error.localizedDescription))
            }
        } catch {
            return .failure(.secureStoreAccessDenied(ApplicationErrorMessages.SecureStorageProvider.failedToAccessStorage, error.localizedDescription))
        }
    }

    // MARK: - Delete
    public func delete(_ key: String) async -> Result<Unit, ServiceFailure> {
        do {
            try fileStorage.delete(forKey: key)
            return .success(.value)
        } catch {
            return .failure(.secureStoreAccessDenied(ApplicationErrorMessages.SecureStorageProvider.failedToDeleteFromStorage, error.localizedDescription))
        }
    }
}

// MARK: - Supporting Types

/// Application instance settings (will be replaced by generated Protocol Buffer code)
public struct ApplicationInstanceSettings: Codable, Equatable {
    public var appInstanceId: UUID
    public var deviceId: UUID
    public var systemDeviceIdentifier: String
    public var serverPublicKey: Data?
    public var culture: String?
    public var country: String?
    public var ipAddress: String?
    public var isNewInstance: Bool
    public var membership: MembershipInfo?

    public init(
        appInstanceId: UUID,
        deviceId: UUID,
        systemDeviceIdentifier: String,
        serverPublicKey: Data? = nil,
        culture: String? = nil,
        country: String? = nil,
        ipAddress: String? = nil,
        isNewInstance: Bool = false,
        membership: MembershipInfo? = nil
    ) {
        self.appInstanceId = appInstanceId
        self.deviceId = deviceId
        self.systemDeviceIdentifier = systemDeviceIdentifier
        self.serverPublicKey = serverPublicKey
        self.culture = culture
        self.country = country
        self.ipAddress = ipAddress
        self.isNewInstance = isNewInstance
        self.membership = membership
    }
}

/// Membership information (placeholder until Protocol Buffer generation)
public struct MembershipInfo: Codable, Equatable {
    public var membershipId: UUID
    public var mobileNumber: String

    public init(membershipId: UUID, mobileNumber: String) {
        self.membershipId = membershipId
        self.mobileNumber = mobileNumber
    }
}

/// Result of initializing instance settings
public struct InstanceSettingsResult {
    public let settings: ApplicationInstanceSettings
    public let isNewInstance: Bool

    public init(settings: ApplicationInstanceSettings, isNewInstance: Bool) {
        self.settings = settings
        self.isNewInstance = isNewInstance
    }
}
