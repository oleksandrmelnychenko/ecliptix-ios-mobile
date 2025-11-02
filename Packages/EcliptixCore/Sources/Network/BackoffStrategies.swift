import Foundation


public protocol BackoffStrategy {
    func calculateDelay(for attempt: Int) -> TimeInterval
}


public struct DecorrelatedJitterBackoffV2: BackoffStrategy {

    private let medianFirstRetryDelay: TimeInterval
    private let maxDelay: TimeInterval
    private let fastFirst: Bool

    public init(
        medianFirstRetryDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        fastFirst: Bool = false
    ) {
        self.medianFirstRetryDelay = medianFirstRetryDelay
        self.maxDelay = maxDelay
        self.fastFirst = fastFirst
    }

    public func calculateDelay(for attempt: Int) -> TimeInterval {
        if attempt == 0 && fastFirst {
            return 0
        }

        if attempt == 0 {
            let min = medianFirstRetryDelay * 0.5
            let max = medianFirstRetryDelay * 1.5
            return TimeInterval.random(in: min...max)
        }

        let previousDelay = calculatePreviousDelay(for: attempt)
        let randomMax = min(maxDelay, previousDelay * 3.0)
        let delay = TimeInterval.random(in: 0...randomMax)

        return min(maxDelay, delay)
    }

    private func calculatePreviousDelay(for attempt: Int) -> TimeInterval {
        if attempt <= 0 {
            return medianFirstRetryDelay
        }
        return calculateDelay(for: attempt - 1)
    }

    public func generateDelays(retryCount: Int) -> [TimeInterval] {
        var delays: [TimeInterval] = []
        delays.reserveCapacity(retryCount)

        for attempt in 0..<retryCount {
            if attempt == 0 {
                if fastFirst {
                    delays.append(0)
                } else {
                    let min = medianFirstRetryDelay * 0.5
                    let max = medianFirstRetryDelay * 1.5
                    delays.append(TimeInterval.random(in: min...max))
                }
            } else {
                let previousDelay = delays[attempt - 1]
                let randomMax = min(maxDelay, previousDelay * 3.0)
                let delay = TimeInterval.random(in: 0...randomMax)
                delays.append(min(maxDelay, delay))
            }
        }

        return delays
    }
}


public struct ExponentialBackoff: BackoffStrategy {

    private let initialDelay: TimeInterval
    private let maxDelay: TimeInterval
    private let factor: Double
    private let useJitter: Bool
    private let fastFirst: Bool

    public init(
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        factor: Double = 2.0,
        useJitter: Bool = true,
        fastFirst: Bool = false
    ) {
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.factor = factor
        self.useJitter = useJitter
        self.fastFirst = fastFirst
    }

    public func calculateDelay(for attempt: Int) -> TimeInterval {
        if attempt == 0 && fastFirst {
            return 0
        }

        let exponentialDelay = initialDelay * pow(factor, Double(attempt))
        let cappedDelay = min(exponentialDelay, maxDelay)

        if useJitter {
            let jitterRange = cappedDelay * 0.2
            let jitter = Double.random(in: -jitterRange...jitterRange)
            return max(0, cappedDelay + jitter)
        }

        return cappedDelay
    }

    public func generateDelays(retryCount: Int) -> [TimeInterval] {
        (0..<retryCount).map { calculateDelay(for: $0) }
    }
}


public struct LinearBackoff: BackoffStrategy {

    private let initialDelay: TimeInterval
    private let increment: TimeInterval
    private let maxDelay: TimeInterval
    private let useJitter: Bool

    public init(
        initialDelay: TimeInterval = 1.0,
        increment: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        useJitter: Bool = true
    ) {
        self.initialDelay = initialDelay
        self.increment = increment
        self.maxDelay = maxDelay
        self.useJitter = useJitter
    }

    public func calculateDelay(for attempt: Int) -> TimeInterval {
        let linearDelay = initialDelay + (increment * Double(attempt))
        let cappedDelay = min(linearDelay, maxDelay)

        if useJitter {
            let jitterRange = increment * 0.2
            let jitter = Double.random(in: -jitterRange...jitterRange)
            return max(0, cappedDelay + jitter)
        }

        return cappedDelay
    }

    public func generateDelays(retryCount: Int) -> [TimeInterval] {
        (0..<retryCount).map { calculateDelay(for: $0) }
    }
}


public struct FixedBackoff: BackoffStrategy {

    private let delay: TimeInterval

    public init(delay: TimeInterval = 1.0) {
        self.delay = delay
    }

    public func calculateDelay(for attempt: Int) -> TimeInterval {
        return delay
    }

    public func generateDelays(retryCount: Int) -> [TimeInterval] {
        Array(repeating: delay, count: retryCount)
    }
}



extension BackoffStrategy {

    public func describeDelays(retryCount: Int) -> String {
        if let generatable = self as? (any BackoffStrategyGeneratable) {
            let delays = generatable.generateDelays(retryCount: retryCount)
            let delayStrings = delays.enumerated().map { index, delay in
                "  Attempt \(index + 1): \(String(format: "%.2fs", delay))"
            }
            return delayStrings.joined(separator: "\n")
        }
        return "Delays cannot be pre-generated for this strategy"
    }
}

public protocol BackoffStrategyGeneratable {
    func generateDelays(retryCount: Int) -> [TimeInterval]
}

extension DecorrelatedJitterBackoffV2: BackoffStrategyGeneratable {}
extension ExponentialBackoff: BackoffStrategyGeneratable {}
extension LinearBackoff: BackoffStrategyGeneratable {}
extension FixedBackoff: BackoffStrategyGeneratable {}
