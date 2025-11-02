import Crypto
import EcliptixCore
import Foundation

#if canImport(UIKit)
import UIKit
#endif

public final class ApplicationSecureStorageProvider {
    private static let settingsKey = "ApplicationInstanceSettings"

    private let fileStorage: EncryptedFileStorage
    private let logger: Logger

    public let protocolStateStorage: SecureProtocolStateStorage
    public let skippedMessageKeysStorage: SkippedMessageKeysStorage

    public init(
        logger: Logger = Log,
        protocolStateStorage: SecureProtocolStateStorage? = nil,
        skippedMessageKeysStorage: SkippedMessageKeysStorage? = nil
    ) throws {
        self.fileStorage = try EncryptedFileStorage()
        self.logger = logger
        self.protocolStateStorage = protocolStateStorage ?? SecureProtocolStateKeychainStorage()
        self.skippedMessageKeysStorage = skippedMessageKeysStorage ?? SkippedMessageKeysKeychainStorage()
    }
    public func setApplicationSettingsCulture(_ culture: String?) async -> Result<Void, ServiceFailure> {
        let settingsResult = await getApplicationInstanceSettings()

        switch settingsResult {
        case .failure(let error):
            return .failure(error)
        case .success(var settings):
            settings.culture = culture ?? settings.culture
            return await storeSettings(settings)
        }
    }
    public func setApplicationInstance(isNewInstance: Bool) async -> Result<Void, ServiceFailure> {

        return .success(())
    }
    public func setApplicationIPCountry(country: String, ipAddress: String) async -> Result<Void, ServiceFailure> {
        let settingsResult = await getApplicationInstanceSettings()

        switch settingsResult {
        case .failure(let error):
            return .failure(error)
        case .success(var settings):
            settings.ipCountry = IpCountry(
                country: country,
                ipAddress: ipAddress,
                fetchedAt: Date()
            )
            return await storeSettings(settings)
        }
    }
    public func setApplicationMembership(_ membership: MembershipInfo?) async -> Result<Void, ServiceFailure> {
        let settingsResult = await getApplicationInstanceSettings()

        switch settingsResult {
        case .failure(let error):
            return .failure(error)
        case .success(var settings):
            settings.membership = membership
            return await storeSettings(settings)
        }
    }
    public func getApplicationInstanceSettings() async -> Result<ApplicationInstanceSettings, ServiceFailure> {
        let getResult = await tryGetByKey(Self.settingsKey)

        switch getResult {
        case .failure(let error):
            return .failure(error)
        case .success(let dataOrNil):
            if let data = dataOrNil {
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
    public func initApplicationInstanceSettings(defaultCulture: String?) async -> Result<InstanceSettingsResult, ServiceFailure> {
        let getResult = await tryGetByKey(Self.settingsKey)

        switch getResult {
        case .failure(let error):
            logger.warning("[SETTINGS-INIT-RECOVERY] Storage access failed, creating fresh settings. Error: \(error.message)")
            return await createAndStoreNewSettings(defaultCulture: defaultCulture)

        case .success(let dataOrNil):
            if let data = dataOrNil {
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
    private func createAndStoreNewSettings(defaultCulture: String?) async -> Result<InstanceSettingsResult, ServiceFailure> {
        #if canImport(UIKit)
        let deviceIdentifier = await UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        let deviceIdentifier = UUID().uuidString
        #endif

        let newSettings = ApplicationInstanceSettings(
            appInstanceId: UUID(),
            deviceId: UUID(),
            culture: defaultCulture ?? "en-US",
            membership: nil,
            systemDeviceIdentifier: deviceIdentifier,
            serverPublicKey: nil,
            ipCountry: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let storeResult = await storeSettings(newSettings)

        if case .failure(let error) = storeResult {
            logger.warning("[SETTINGS-INIT-RECOVERY] Failed to persist fresh settings, continuing in-memory. Error: \(error.message)")
        }

        return .success(InstanceSettingsResult(settings: newSettings, isNewInstance: true))
    }
    private func storeSettings(_ settings: ApplicationInstanceSettings) async -> Result<Void, ServiceFailure> {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(settings)
            return await store(Self.settingsKey, data: data)
        } catch {
            return .failure(.secureStoreEncryptionFailed(ApplicationErrorMessages.SecureStorageProvider.failedToEncryptData))
        }
    }
    private func store(_ key: String, data: Data) async -> Result<Void, ServiceFailure> {
        do {
            try fileStorage.store(data, forKey: key)
            return .success(())
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
    private func tryGetByKey(_ key: String) async -> Result<Data?, ServiceFailure> {
        do {
            if let data = try fileStorage.retrieve(forKey: key) {
                return .success(data)
            } else {
                return .success(nil)
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
    public func delete(_ key: String) async -> Result<Void, ServiceFailure> {
        do {
            try fileStorage.delete(forKey: key)
            return .success(())
        } catch {
            return .failure(.secureStoreAccessDenied(ApplicationErrorMessages.SecureStorageProvider.failedToDeleteFromStorage, error.localizedDescription))
        }
    }
}

public struct InstanceSettingsResult {
    public let settings: ApplicationInstanceSettings
    public let isNewInstance: Bool

    public init(settings: ApplicationInstanceSettings, isNewInstance: Bool) {
        self.settings = settings
        self.isNewInstance = isNewInstance
    }
}
