import Crypto
import EcliptixCore
import Foundation

public final class EntropyValidator {

    public static let minimumShannonEntropy: Double = 7.5

    public static let minimumChiSquarePValue: Double = 0.01
    public static let maximumChiSquarePValue: Double = 0.99

    public static let maximumRepetitionRate: Double = 0.1

    public static func validate(_ data: Data) -> EntropyValidationResult {
        guard !data.isEmpty else {
            return EntropyValidationResult(
                isValid: false,
                shannonEntropy: 0.0,
                chiSquarePValue: 0.0,
                repetitionRate: 1.0,
                message: "Data is empty"
            )
        }

        let shannonEntropy = calculateShannonEntropy(data)
        let chiSquarePValue = calculateChiSquarePValue(data)
        let repetitionRate = calculateRepetitionRate(data)

        let hasGoodEntropy = shannonEntropy >= minimumShannonEntropy
        let hasGoodDistribution = chiSquarePValue >= minimumChiSquarePValue &&
                                   chiSquarePValue <= maximumChiSquarePValue
        let hasLowRepetition = repetitionRate <= maximumRepetitionRate

        let isValid = hasGoodEntropy && hasGoodDistribution && hasLowRepetition

        var messages: [String] = []
        if !hasGoodEntropy {
            messages.append("Low Shannon entropy: \(String(format: "%.2f", shannonEntropy)) < \(minimumShannonEntropy)")
        }
        if !hasGoodDistribution {
            messages.append("Poor distribution: χ² p-value = \(String(format: "%.4f", chiSquarePValue))")
        }
        if !hasLowRepetition {
            messages.append("High repetition rate: \(String(format: "%.2f%%", repetitionRate * 100))")
        }

        let message = isValid ? "Entropy validation passed" : messages.joined(separator: "; ")

        Log.debug("[EntropyValidator] Shannon: \(String(format: "%.2f", shannonEntropy)), χ²: \(String(format: "%.4f", chiSquarePValue)), Rep: \(String(format: "%.2f%%", repetitionRate * 100))")

        return EntropyValidationResult(
            isValid: isValid,
            shannonEntropy: shannonEntropy,
            chiSquarePValue: chiSquarePValue,
            repetitionRate: repetitionRate,
            message: message
        )
    }

    public static func quickValidate(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        let entropy = calculateShannonEntropy(data)
        return entropy >= minimumShannonEntropy
    }

    public static func shannonEntropy(of data: Data) -> Double {
        var frequencies = [UInt8: Int]()
        for byte in data {
            frequencies[byte, default: 0] += 1
        }

        let totalBytes = Double(data.count)
        var entropy: Double = 0.0

        for count in frequencies.values {
            let probability = Double(count) / totalBytes
            if probability > 0 {
                entropy -= probability * log2(probability)
            }
        }

        return entropy
    }

    private static func calculateShannonEntropy(_ data: Data) -> Double {
        return shannonEntropy(of: data)
    }

    private static func calculateChiSquarePValue(_ data: Data) -> Double {
        var frequencies = [Int](repeating: 0, count: 256)
        for byte in data {
            frequencies[Int(byte)] += 1
        }

        let expectedFrequency = Double(data.count) / 256.0

        var chiSquare: Double = 0.0
        for observed in frequencies {
            let diff = Double(observed) - expectedFrequency
            chiSquare += (diff * diff) / expectedFrequency
        }

        let degreesOfFreedom = 255.0

        let mean = degreesOfFreedom
        let stdDev = sqrt(2.0 * degreesOfFreedom)
        let z = (chiSquare - mean) / stdDev

        let pValue = erfcApproximation(abs(z) / sqrt(2.0))

        return max(0.0, min(1.0, pValue))
    }

    private static func erfcApproximation(_ x: Double) -> Double {
        let t = 1.0 / (1.0 + 0.5 * x)
        let tau = t * exp(-x * x - 1.26551223 +
                          t * (1.00002368 +
                          t * (0.37409196 +
                          t * (0.09678418 +
                          t * (-0.18628806 +
                          t * (0.27886807 +
                          t * (-1.13520398 +
                          t * (1.48851587 +
                          t * (-0.82215223 +
                          t * 0.17087277)))))))))
        return tau
    }

    private static func calculateRepetitionRate(_ data: Data) -> Double {
        guard data.count > 1 else { return 0.0 }

        var repetitions = 0
        var previousByte = data[0]

        for i in 1..<data.count {
            if data[i] == previousByte {
                repetitions += 1
            }
            previousByte = data[i]
        }

        return Double(repetitions) / Double(data.count - 1)
    }

    public static func detectPatterns(_ data: Data) -> [EntropyPattern] {
        var patterns: [EntropyPattern] = []

        if data.allSatisfy({ $0 == 0 }) {
            patterns.append(.allZeros)
        }

        if data.allSatisfy({ $0 == 0xFF }) {
            patterns.append(.allOnes)
        }

        if isSequentialPattern(data) {
            patterns.append(.sequential)
        }

        if let repeatLength = detectRepeatingPattern(data) {
            patterns.append(.repeating(length: repeatLength))
        }

        let uniqueBytes = Set(data)
        if uniqueBytes.count == 1 {
            patterns.append(.singleByte(byte: data[0]))
        }

        return patterns
    }

    private static func isSequentialPattern(_ data: Data) -> Bool {
        guard data.count > 2 else { return false }

        let threshold = Int(Double(data.count) * 0.9)

        var sequentialCount = 0
        for i in 1..<data.count {
            if data[i] == data[i-1] &+ 1 {
                sequentialCount += 1
            }
        }

        return sequentialCount >= threshold
    }

    private static func detectRepeatingPattern(_ data: Data) -> Int? {
        guard data.count >= 4 else { return nil }

        for patternLength in 1...(data.count / 2) {
            let pattern = data.prefix(patternLength)
            var isRepeating = true

            var position = patternLength
            while position < data.count {
                let remaining = data.count - position
                let checkLength = min(patternLength, remaining)
                let segment = data[position..<(position + checkLength)]

                if segment != pattern.prefix(checkLength) {
                    isRepeating = false
                    break
                }

                position += patternLength
            }

            if isRepeating {
                return patternLength
            }
        }

        return nil
    }

    public static func validateSystemRNG(size: Int = 32) throws -> EntropyValidationResult {
        var bytes = Data(count: size)
        let result = bytes.withUnsafeMutableBytes { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else {
                return -1
            }
            return SecRandomCopyBytes(kSecRandomDefault, size, baseAddress)
        }

        guard result == 0 else {
            throw EntropyError.systemRNGFailed
        }

        return validate(bytes)
    }
}

public struct EntropyValidationResult {

    public let isValid: Bool

    public let shannonEntropy: Double

    public let chiSquarePValue: Double

    public let repetitionRate: Double

    public let message: String

    public var qualityLevel: EntropyQuality {
        if shannonEntropy >= 7.8 {
            return .excellent
        } else if shannonEntropy >= 7.5 {
            return .good
        } else if shannonEntropy >= 7.0 {
            return .fair
        } else {
            return .poor
        }
    }
}

public enum EntropyQuality {
    case excellent
    case good
    case fair
    case poor

    public var description: String {
        switch self {
        case .excellent:
            return "Excellent"
        case .good:
            return "Good"
        case .fair:
            return "Fair"
        case .poor:
            return "Poor"
        }
    }
}

public enum EntropyPattern: Equatable {
    case allZeros
    case allOnes
    case sequential
    case repeating(length: Int)
    case singleByte(byte: UInt8)

    public var description: String {
        switch self {
        case .allZeros:
            return "All zeros detected"
        case .allOnes:
            return "All ones (0xFF) detected"
        case .sequential:
            return "Sequential pattern detected"
        case .repeating(let length):
            return "Repeating pattern (length: \(length)) detected"
        case .singleByte(let byte):
            return "Single byte repeated (0x\(String(byte, radix: 16, uppercase: true)))"
        }
    }
}

public enum EntropyError: LocalizedError {
    case lowEntropy(String)
    case systemRNGFailed
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .lowEntropy(let msg):
            return "Low entropy detected: \(msg)"
        case .systemRNGFailed:
            return "System RNG (SecRandomCopyBytes) failed"
        case .invalidData:
            return "Invalid data for entropy validation"
        }
    }
}
