import Foundation
import EcliptixCore

// MARK: - Network Cache
/// Implements caching for network requests to reduce bandwidth and improve performance
/// Migrated from: Ecliptix.Core/Services/Network/Caching/NetworkCache.cs
@MainActor
public final class NetworkCache {

    // MARK: - Cache Entry

    /// Cached response entry
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

    // MARK: - Properties

    private let configuration: NetworkCacheConfiguration

    /// In-memory cache storage
    private var memoryCache: [String: CacheEntry] = [:]
    private let memoryCacheLock = NSLock()

    /// Cache statistics
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    private var cacheEvictions: Int = 0

    /// Cleanup timer
    private var cleanupTimer: Timer?

    // MARK: - Initialization

    public init(configuration: NetworkCacheConfiguration = .default) {
        self.configuration = configuration

        // Start cleanup timer
        startCleanupTimer()
    }

    deinit {
        cleanupTimer?.invalidate()
    }

    // MARK: - Cache Operations

    /// Retrieves cached response if available and not expired
    /// Migrated from: GetCachedResponseAsync()
    public func getCachedResponse(requestKey: String) -> Data? {
        memoryCacheLock.lock()
        defer { memoryCacheLock.unlock() }

        guard let entry = memoryCache[requestKey] else {
            cacheMisses += 1
            return nil
        }

        // Check if expired
        if entry.isExpired {
            memoryCache.removeValue(forKey: requestKey)
            cacheMisses += 1
            Log.debug("[NetworkCache] ⏰ Cache EXPIRED for key: \(requestKey)")
            return nil
        }

        cacheHits += 1
        Log.debug("[NetworkCache] ✅ Cache HIT for key: \(requestKey) (age: \(String(format: "%.1f", entry.age))s)")
        return entry.responseData
    }

    /// Stores response in cache
    /// Migrated from: CacheResponseAsync()
    public func cacheResponse(
        requestKey: String,
        responseData: Data,
        timeToLive: TimeInterval? = nil,
        etag: String? = nil
    ) {
        memoryCacheLock.lock()
        defer { memoryCacheLock.unlock() }

        // Check if caching is enabled
        guard configuration.enabled else {
            return
        }

        // Check size limits
        if responseData.count > configuration.maxCacheEntrySize {
            Log.warning("[NetworkCache] ⚠️ Response too large to cache: \(responseData.count) bytes (max: \(configuration.maxCacheEntrySize))")
            return
        }

        // Evict if cache is full
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
        Log.debug("[NetworkCache] 💾 Cached response for key: \(requestKey) (size: \(responseData.count) bytes, TTL: \(String(format: "%.0f", ttl))s)")
    }

    /// Invalidates cached response
    /// Migrated from: InvalidateCacheAsync()
    public func invalidate(requestKey: String) {
        memoryCacheLock.lock()
        defer { memoryCacheLock.unlock() }

        if memoryCache.removeValue(forKey: requestKey) != nil {
            Log.debug("[NetworkCache] 🗑️ Invalidated cache for key: \(requestKey)")
        }
    }

    /// Invalidates all cached responses matching a pattern
    /// Migrated from: InvalidateCacheByPatternAsync()
    public func invalidateByPattern(_ pattern: String) {
        memoryCacheLock.lock()
        defer { memoryCacheLock.unlock() }

        let keysToRemove = memoryCache.keys.filter { $0.contains(pattern) }
        for key in keysToRemove {
            memoryCache.removeValue(forKey: key)
        }

        if !keysToRemove.isEmpty {
            Log.debug("[NetworkCache] 🗑️ Invalidated \(keysToRemove.count) cache entries matching pattern: \(pattern)")
        }
    }

    /// Clears all cached responses
    /// Migrated from: ClearCacheAsync()
    public func clearAll() {
        memoryCacheLock.lock()
        defer { memoryCacheLock.unlock() }

        let count = memoryCache.count
        memoryCache.removeAll()

        Log.info("[NetworkCache] 🗑️ Cleared all \(count) cache entries")
    }

    // MARK: - Cache Policy Checks

    /// Checks if request should use cache based on policy
    /// Migrated from: ShouldUseCacheForRequest()
    public func shouldUseCache(for policy: CachePolicy) -> Bool {
        switch policy {
        case .networkOnly:
            return false
        case .cacheFirst, .cacheOnly, .networkFirst:
            return true
        }
    }

    /// Checks if response should be cached based on policy
    /// Migrated from: ShouldCacheResponse()
    public func shouldCacheResponse(for policy: CachePolicy) -> Bool {
        switch policy {
        case .networkOnly, .cacheOnly:
            return false
        case .cacheFirst, .networkFirst:
            return true
        }
    }

    // MARK: - Cache Eviction

    /// Evicts oldest cache entry
    private func evictOldestEntry() {
        guard let oldestKey = memoryCache
            .min(by: { $0.value.cachedAt < $1.value.cachedAt })?
            .key
        else {
            return
        }

        memoryCache.removeValue(forKey: oldestKey)
        cacheEvictions += 1
        Log.debug("[NetworkCache] 🗑️ Evicted oldest cache entry: \(oldestKey)")
    }

    // MARK: - Cleanup

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(
            withTimeInterval: configuration.cleanupInterval,
            repeats: true
        ) { [weak self] _ in
            self?.cleanupExpiredEntries()
        }
    }

    private func cleanupExpiredEntries() {
        memoryCacheLock.lock()
        defer { memoryCacheLock.unlock() }

        let expiredKeys = memoryCache.filter { $0.value.isExpired }.map { $0.key }

        for key in expiredKeys {
            memoryCache.removeValue(forKey: key)
        }

        if !expiredKeys.isEmpty {
            Log.debug("[NetworkCache] 🧹 Cleaned up \(expiredKeys.count) expired cache entries")
        }
    }

    // MARK: - Statistics

    /// Returns cache statistics
    public func getStatistics() -> CacheStatistics {
        memoryCacheLock.lock()
        defer { memoryCacheLock.unlock() }

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

    /// Resets cache statistics
    public func resetStatistics() {
        memoryCacheLock.lock()
        defer { memoryCacheLock.unlock() }

        cacheHits = 0
        cacheMisses = 0
        cacheEvictions = 0

        Log.debug("[NetworkCache] 📊 Reset cache statistics")
    }
}

// MARK: - Cache Policy

/// Cache policy for network requests
/// Migrated from: CachePolicy.cs
public enum CachePolicy {
    /// Always use network, never cache
    case networkOnly

    /// Try cache first, fallback to network
    case cacheFirst

    /// Try network first, fallback to cache
    case networkFirst

    /// Only use cache, fail if not cached
    case cacheOnly
}

// MARK: - Configuration

/// Configuration for network cache
/// Migrated from: NetworkCacheConfiguration.cs
public struct NetworkCacheConfiguration {

    /// Whether caching is enabled
    public let enabled: Bool

    /// Maximum number of cache entries
    public let maxCacheEntries: Int

    /// Maximum size of a single cache entry (in bytes)
    public let maxCacheEntrySize: Int

    /// Default time-to-live for cache entries (in seconds)
    public let defaultTimeToLive: TimeInterval

    /// Cleanup interval for expired entries (in seconds)
    public let cleanupInterval: TimeInterval

    public init(
        enabled: Bool = true,
        maxCacheEntries: Int = 100,
        maxCacheEntrySize: Int = 1024 * 1024, // 1 MB
        defaultTimeToLive: TimeInterval = 300.0, // 5 minutes
        cleanupInterval: TimeInterval = 60.0 // 1 minute
    ) {
        self.enabled = enabled
        self.maxCacheEntries = maxCacheEntries
        self.maxCacheEntrySize = maxCacheEntrySize
        self.defaultTimeToLive = defaultTimeToLive
        self.cleanupInterval = cleanupInterval
    }

    // MARK: - Presets

    /// Default configuration
    public static let `default` = NetworkCacheConfiguration()

    /// Aggressive caching (more entries, longer TTL)
    public static let aggressive = NetworkCacheConfiguration(
        maxCacheEntries: 200,
        maxCacheEntrySize: 5 * 1024 * 1024, // 5 MB
        defaultTimeToLive: 900.0 // 15 minutes
    )

    /// Conservative caching (fewer entries, shorter TTL)
    public static let conservative = NetworkCacheConfiguration(
        maxCacheEntries: 50,
        maxCacheEntrySize: 512 * 1024, // 512 KB
        defaultTimeToLive: 120.0 // 2 minutes
    )

    /// Disabled caching
    public static let disabled = NetworkCacheConfiguration(
        enabled: false,
        maxCacheEntries: 0,
        maxCacheEntrySize: 0,
        defaultTimeToLive: 0
    )
}

// MARK: - Statistics

/// Cache statistics
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
