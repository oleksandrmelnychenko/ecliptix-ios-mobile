import EcliptixCore
import Foundation

@MainActor
public final class NetworkCache {

    private struct CacheEntry {
        let responseData: Data
        let cachedAt: Date
        let expiresAt: Date
        let requestKey: String
        let etag: String?

        var isExpired: Bool {
            return Date() > expiresAt
        }

        var age: TimeInterval {
            return Date().timeIntervalSince(cachedAt)
        }
    }

    private let configuration: NetworkCacheConfiguration

    private var memoryCache: [String: CacheEntry] = [:]

    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    private var cacheEvictions: Int = 0

    nonisolated(unsafe) private var cleanupTimer: Timer?

    public init(configuration: NetworkCacheConfiguration = .default) {
        self.configuration = configuration

        startCleanupTimer()
    }

    deinit {
        cleanupTimer?.invalidate()
    }

    public func getCachedResponse(requestKey: String) -> Data? {
        guard let entry = memoryCache[requestKey] else {
            cacheMisses += 1
            return nil
        }

        if entry.isExpired {
            memoryCache.removeValue(forKey: requestKey)
            cacheMisses += 1
            Log.debug("[NetworkCache] ⏰ Cache EXPIRED for key: \(requestKey)")
            return nil
        }

        cacheHits += 1
        Log.debug("[NetworkCache] [OK] Cache HIT for key: \(requestKey) (age: \(String(format: "%.1f", entry.age))s)")
        return entry.responseData
    }

    public func cacheResponse(
        requestKey: String,
        responseData: Data,
        timeToLive: TimeInterval? = nil,
        etag: String? = nil
    ) {

        guard configuration.enabled else {
            return
        }

        if responseData.count > configuration.maxCacheEntrySize {
            Log.warning("[NetworkCache] [WARNING] Response too large to cache: \(responseData.count) bytes (max: \(configuration.maxCacheEntrySize))")
            return
        }

        if memoryCache.count >= configuration.maxCacheEntries {
            evictOldestEntry()
        }

        let ttl = timeToLive ?? configuration.defaultTimeToLive
        let entry = CacheEntry(
            responseData: responseData,
            cachedAt: Date(),
            expiresAt: Date().addingTimeInterval(ttl),
            requestKey: requestKey,
            etag: etag
        )

        memoryCache[requestKey] = entry
        Log.debug("[NetworkCache]  Cached response for key: \(requestKey) (size: \(responseData.count) bytes, TTL: \(String(format: "%.0f", ttl))s)")
    }

    public func invalidate(requestKey: String) {

        if memoryCache.removeValue(forKey: requestKey) != nil {
            Log.debug("[NetworkCache]  Invalidated cache for key: \(requestKey)")
        }
    }

    public func invalidateByPattern(_ pattern: String) {

        let keysToRemove = memoryCache.keys.filter { $0.contains(pattern) }
        for key in keysToRemove {
            memoryCache.removeValue(forKey: key)
        }

        if !keysToRemove.isEmpty {
            Log.debug("[NetworkCache]  Invalidated \(keysToRemove.count) cache entries matching pattern: \(pattern)")
        }
    }

    public func clearAll() {

        let count = memoryCache.count
        memoryCache.removeAll()

        Log.info("[NetworkCache]  Cleared all \(count) cache entries")
    }

    public func shouldUseCache(for policy: CachePolicy) -> Bool {
        switch policy {
        case .networkOnly:
            return false
        case .cacheFirst, .cacheOnly, .networkFirst:
            return true
        }
    }

    public func shouldCacheResponse(for policy: CachePolicy) -> Bool {
        switch policy {
        case .networkOnly, .cacheOnly:
            return false
        case .cacheFirst, .networkFirst:
            return true
        }
    }

    private func evictOldestEntry() {
        guard let oldestKey = memoryCache
            .min(by: { $0.value.cachedAt < $1.value.cachedAt })?
            .key
        else {
            return
        }

        memoryCache.removeValue(forKey: oldestKey)
        cacheEvictions += 1
        Log.debug("[NetworkCache]  Evicted oldest cache entry: \(oldestKey)")
    }

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(
            withTimeInterval: configuration.cleanupInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.cleanupExpiredEntries()
            }
        }
    }

    private func cleanupExpiredEntries() async {
        let expiredKeys = memoryCache.filter { $0.value.isExpired }.map { $0.key }

        for key in expiredKeys {
            memoryCache.removeValue(forKey: key)
        }

        if !expiredKeys.isEmpty {
            Log.debug("[NetworkCache]  Cleaned up \(expiredKeys.count) expired cache entries")
        }
    }

    public func getStatistics() -> CacheStatistics {

        let totalSize = memoryCache.values.reduce(0) { $0 + $1.responseData.count }
        let totalRequests = cacheHits + cacheMisses
        let hitRate = totalRequests > 0 ? Double(cacheHits) / Double(totalRequests) : 0.0

        return CacheStatistics(
            entryCount: memoryCache.count,
            totalSizeBytes: totalSize,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses,
            cacheEvictions: cacheEvictions,
            hitRate: hitRate
        )
    }

    public func resetStatistics() {

        cacheHits = 0
        cacheMisses = 0
        cacheEvictions = 0

        Log.debug("[NetworkCache]  Reset cache statistics")
    }
}

public enum CachePolicy {

    case networkOnly

    case cacheFirst

    case networkFirst

    case cacheOnly
}

public struct NetworkCacheConfiguration: Sendable {

    public let enabled: Bool

    public let maxCacheEntries: Int

    public let maxCacheEntrySize: Int

    public let defaultTimeToLive: TimeInterval

    public let cleanupInterval: TimeInterval

    public init(
        enabled: Bool = true,
        maxCacheEntries: Int = 100,
        maxCacheEntrySize: Int = 1024 * 1024,
        defaultTimeToLive: TimeInterval = 300.0,
        cleanupInterval: TimeInterval = 60.0
    ) {
        self.enabled = enabled
        self.maxCacheEntries = maxCacheEntries
        self.maxCacheEntrySize = maxCacheEntrySize
        self.defaultTimeToLive = defaultTimeToLive
        self.cleanupInterval = cleanupInterval
    }

    public static let `default` = NetworkCacheConfiguration()

    public static let aggressive = NetworkCacheConfiguration(
        maxCacheEntries: 200,
        maxCacheEntrySize: 5 * 1024 * 1024,
        defaultTimeToLive: 900.0
    )

    public static let conservative = NetworkCacheConfiguration(
        maxCacheEntries: 50,
        maxCacheEntrySize: 512 * 1024,
        defaultTimeToLive: 120.0
    )

    public static let disabled = NetworkCacheConfiguration(
        enabled: false,
        maxCacheEntries: 0,
        maxCacheEntrySize: 0,
        defaultTimeToLive: 0
    )
}

public struct CacheStatistics {
    public let entryCount: Int
    public let totalSizeBytes: Int
    public let cacheHits: Int
    public let cacheMisses: Int
    public let cacheEvictions: Int
    public let hitRate: Double

    public var averageEntrySizeBytes: Int {
        guard entryCount > 0 else { return 0 }
        return totalSizeBytes / entryCount
    }

    public var hitRatePercentage: Double {
        return hitRate * 100.0
    }
}
