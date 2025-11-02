import EcliptixCore
import Foundation

public final class ApplicationInstanceSettingsKeychainStorage: ApplicationInstanceSettingsStorage {

    private let keychainStorage: KeychainStorage
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let settingsKey = "ecliptix.application.instance.settings"
    private let membershipKey = "ecliptix.application.membership"
    private let ipCountryKey = "ecliptix.application.ipcountry"

    public init(keychainStorage: KeychainStorage = KeychainStorage()) {
        self.keychainStorage = keychainStorage
    }

    public func loadSettings() async throws -> ApplicationInstanceSettings? {
        do {
            guard let data = try keychainStorage.retrieve(forKey: settingsKey) else {
                return nil
            }

            let settings = try decoder.decode(ApplicationInstanceSettings.self, from: data)
            Log.info("[SettingsStorage] Loaded application instance settings")
            return settings

        } catch {
            Log.warning("[SettingsStorage] Failed to load settings: \(error.localizedDescription)")
            throw StorageError.loadFailed(error.localizedDescription)
        }
    }

    public func saveSettings(_ settings: ApplicationInstanceSettings) async throws {
        do {
            var mutableSettings = settings
            mutableSettings.updatedAt = Date()

            let data = try encoder.encode(mutableSettings)
            try keychainStorage.save(data, forKey: settingsKey)

            Log.info("[SettingsStorage] Saved application instance settings")

        } catch {
            Log.error("[SettingsStorage] Failed to save settings: \(error.localizedDescription)")
            throw StorageError.saveFailed(error.localizedDescription)
        }
    }

    public func clearSettings() async throws {
        do {
            try keychainStorage.delete(forKey: settingsKey)
            try? keychainStorage.delete(forKey: membershipKey)
            try? keychainStorage.delete(forKey: ipCountryKey)

            Log.info("[SettingsStorage] Cleared all application instance settings")

        } catch {
            Log.warning("[SettingsStorage] Failed to clear settings: \(error.localizedDescription)")
            throw StorageError.deleteFailed(error.localizedDescription)
        }
    }

    public func updateMembership(_ membership: MembershipInfo?) async throws {
        guard var settings = try await loadSettings() else {
            throw StorageError.notFound("No settings found to update")
        }

        settings.membership = membership
        try await saveSettings(settings)

        Log.info("[SettingsStorage] Updated membership: \(membership != nil ? "Set" : "Cleared")")
    }

    public func updateIpCountry(_ ipCountry: IpCountry) async throws {
        guard var settings = try await loadSettings() else {
            throw StorageError.notFound("No settings found to update")
        }

        settings.ipCountry = ipCountry
        try await saveSettings(settings)

        Log.info("[SettingsStorage] Updated IP country: \(ipCountry.country)")
    }

    public func initializeIfNeeded(culture: String = DefaultCultureSettings.defaultCultureCode) async throws -> (settings: ApplicationInstanceSettings, isNew: Bool) {

        if let existingSettings = try await loadSettings() {
            Log.info("[SettingsStorage] Using existing application instance settings")
            return (existingSettings, false)
        }

        let newSettings = ApplicationInstanceSettings(
            appInstanceId: UUID(),
            deviceId: UUID(),
            culture: culture
        )

        try await saveSettings(newSettings)

        Log.info("[SettingsStorage] Created new application instance settings - AppInstanceId: \(newSettings.appInstanceId), DeviceId: \(newSettings.deviceId)")

        return (newSettings, true)
    }
}
public enum StorageError: LocalizedError {
    case notFound(String)
    case loadFailed(String)
    case saveFailed(String)
    case deleteFailed(String)
    case serializationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let message):
            return "Not found: \(message)"
        case .loadFailed(let message):
            return "Load failed: \(message)"
        case .saveFailed(let message):
            return "Save failed: \(message)"
        case .deleteFailed(let message):
            return "Delete failed: \(message)"
        case .serializationFailed(let message):
            return "Serialization failed: \(message)"
        }
    }
}
