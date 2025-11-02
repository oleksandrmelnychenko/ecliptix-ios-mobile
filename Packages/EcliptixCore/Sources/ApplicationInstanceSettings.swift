import Foundation

public struct ApplicationInstanceSettings: Codable, Sendable {

    public var appInstanceId: UUID

    public var deviceId: UUID

    public var culture: String

    public var membership: MembershipInfo?

    public var systemDeviceIdentifier: String?

    public var serverPublicKey: Data?

    public var ipCountry: IpCountry?

    public var createdAt: Date

    public var updatedAt: Date

    public init(
        appInstanceId: UUID = UUID(),
        deviceId: UUID = UUID(),
        culture: String = "en-US",
        membership: MembershipInfo? = nil,
        systemDeviceIdentifier: String? = nil,
        serverPublicKey: Data? = nil,
        ipCountry: IpCountry? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.appInstanceId = appInstanceId
        self.deviceId = deviceId
        self.culture = culture
        self.membership = membership
        self.systemDeviceIdentifier = systemDeviceIdentifier
        self.serverPublicKey = serverPublicKey
        self.ipCountry = ipCountry
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct MembershipInfo: Codable, Sendable {

    public var uniqueIdentifier: UUID

    public var mobileNumber: String?

    public var displayName: String?

    public var email: String?

    public init(
        uniqueIdentifier: UUID,
        mobileNumber: String? = nil,
        displayName: String? = nil,
        email: String? = nil
    ) {
        self.uniqueIdentifier = uniqueIdentifier
        self.mobileNumber = mobileNumber
        self.displayName = displayName
        self.email = email
    }
}

public struct IpCountry: Codable, Sendable {

    public var country: String

    public var countryName: String?

    public var city: String?

    public var region: String?

    public var ipAddress: String?

    public var fetchedAt: Date

    public init(
        country: String,
        countryName: String? = nil,
        city: String? = nil,
        region: String? = nil,
        ipAddress: String? = nil,
        fetchedAt: Date = Date()
    ) {
        self.country = country
        self.countryName = countryName
        self.city = city
        self.region = region
        self.ipAddress = ipAddress
        self.fetchedAt = fetchedAt
    }
}

public protocol ApplicationInstanceSettingsStorage: Sendable {

    func loadSettings() async throws -> ApplicationInstanceSettings?

    func saveSettings(_ settings: ApplicationInstanceSettings) async throws

    func clearSettings() async throws

    func updateMembership(_ membership: MembershipInfo?) async throws

    func updateIpCountry(_ ipCountry: IpCountry) async throws
}
public struct DefaultCultureSettings {
    public static let defaultCultureCode = "en-US"
    public static let supportedCultures = ["en-US", "uk-UA", "ru-RU"]

    public static func isSupported(_ culture: String) -> Bool {
        return supportedCultures.contains(culture)
    }
}
