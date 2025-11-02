import Foundation

public struct RetryStrategyConfiguration: Sendable {

    public let maxRetries: Int

    public let initialDelay: TimeInterval

    public let maxDelay: TimeInterval

    public let backoffMultiplier: Double

    public let useJitter: Bool

    public let jitterMin: Double

    public let jitterMax: Double

    public init(
        maxRetries: Int = 5,
        initialDelay: TimeInterval = 2.0,
        maxDelay: TimeInterval = 60.0,
        backoffMultiplier: Double = 2.0,
        useJitter: Bool = true,
        jitterMin: Double = 0.8,
        jitterMax: Double = 1.2
    ) {
        self.maxRetries = maxRetries
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.backoffMultiplier = backoffMultiplier
        self.useJitter = useJitter
        self.jitterMin = jitterMin
        self.jitterMax = jitterMax
    }

    public static let `default` = RetryStrategyConfiguration()

    public static let aggressive = RetryStrategyConfiguration(
        maxRetries: 10,
        initialDelay: 1.0,
        maxDelay: 30.0,
        backoffMultiplier: 1.5
    )

    public static let conservative = RetryStrategyConfiguration(
        maxRetries: 3,
        initialDelay: 5.0,
        maxDelay: 120.0,
        backoffMultiplier: 3.0
    )

    public static let noRetry = RetryStrategyConfiguration(
        maxRetries: 0,
        initialDelay: 0,
        maxDelay: 0,
        backoffMultiplier: 1.0,
        useJitter: false
    )
}

extension RetryStrategyConfiguration {

    public func calculateDelay(for attempt: Int) -> TimeInterval {
        guard attempt >= 0 else { return 0 }
        guard attempt < maxRetries else { return maxDelay }

        let exponentialDelay = initialDelay * pow(backoffMultiplier, Double(attempt))

        let cappedDelay = min(exponentialDelay, maxDelay)

        if useJitter {
            let jitterFactor = Double.random(in: jitterMin...jitterMax)
            return cappedDelay * jitterFactor
        }

        return cappedDelay
    }

    public func canRetry(attempt: Int) -> Bool {
        return attempt < maxRetries
    }

    public var maximumTotalDuration: TimeInterval {
        guard maxRetries > 0 else { return 0 }

        var totalDelay: TimeInterval = 0
        for attempt in 0..<maxRetries {
            totalDelay += calculateDelay(for: attempt)
        }

        return totalDelay
    }
}

extension RetryStrategyConfiguration: CustomStringConvertible {
    public var description: String {
        """
        RetryStrategyConfiguration(
          maxRetries: \(maxRetries),
          initialDelay: \(String(format: "%.1fs", initialDelay)),
          maxDelay: \(String(format: "%.1fs", maxDelay)),
          backoffMultiplier: \(String(format: "%.1fx", backoffMultiplier)),
          useJitter: \(useJitter),
          estimatedMaxDuration: ~\(String(format: "%.1fs", maximumTotalDuration))
        )
        """
    }
}
