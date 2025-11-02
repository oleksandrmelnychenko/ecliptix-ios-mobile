import EcliptixCore
import Foundation

public final class RSAChunkEncryptor {

    private static let rsaMaxChunkSize = 120

    private static let rsaEncryptedChunkSize = 256

    public static func encryptInChunks(
        certificatePinningClient: CertificatePinningClient,
        originalData: Data
    ) -> Result<Data, CertificatePinningError> {

        guard !originalData.isEmpty else {
            return .failure(.invalidInput("Original data cannot be empty"))
        }

        let chunkCount = (originalData.count + rsaMaxChunkSize - 1) / rsaMaxChunkSize
        let estimatedSize = chunkCount * rsaEncryptedChunkSize

        var combinedEncryptedPayload = Data(capacity: estimatedSize)

        var offset = 0
        while offset < originalData.count {
            let chunkSize = min(rsaMaxChunkSize, originalData.count - offset)
            let chunk = originalData.subdata(in: offset..<offset + chunkSize)

            let chunkResult = certificatePinningClient.encrypt(plaintext: chunk)

            switch chunkResult {
            case .success(let encryptedChunk):
                combinedEncryptedPayload.append(encryptedChunk)
                offset += chunkSize

            case .failure(let error):
                Log.error("[RSAChunkEncryptor] Encryption failed at offset \(offset): \(error)")
                return .failure(error)
            }
        }

        Log.info("[RSAChunkEncryptor] [OK] Encrypted \(originalData.count) bytes → \(combinedEncryptedPayload.count) bytes (\(chunkCount) chunks)")
        return .success(combinedEncryptedPayload)
    }

    public static func decryptInChunks(
        certificatePinningClient: CertificatePinningClient,
        combinedEncryptedData: Data
    ) -> Result<Data, CertificatePinningError> {

        guard !combinedEncryptedData.isEmpty else {
            return .failure(.invalidInput("Encrypted data cannot be empty"))
        }

        guard combinedEncryptedData.count % rsaEncryptedChunkSize == 0 else {
            let message = "Invalid encrypted data size: \(combinedEncryptedData.count) (must be multiple of \(rsaEncryptedChunkSize))"
            Log.error("[RSAChunkEncryptor] \(message)")
            return .failure(.invalidInput(message))
        }

        let chunkCount = combinedEncryptedData.count / rsaEncryptedChunkSize
        let estimatedSize = chunkCount * rsaMaxChunkSize

        var decryptedData = Data(capacity: estimatedSize)

        var offset = 0
        var chunkNumber = 1
        while offset < combinedEncryptedData.count {
            let chunkSize = min(rsaEncryptedChunkSize, combinedEncryptedData.count - offset)
            let encryptedChunk = combinedEncryptedData.subdata(in: offset..<offset + chunkSize)

            let chunkDecryptResult = certificatePinningClient.decrypt(ciphertext: encryptedChunk)

            switch chunkDecryptResult {
            case .success(let decryptedChunk):
                decryptedData.append(decryptedChunk)
                offset += chunkSize
                chunkNumber += 1

            case .failure(let error):
                Log.error("[RSAChunkEncryptor] Decryption failed at chunk \(chunkNumber): \(error)")
                return .failure(error)
            }
        }

        Log.info("[RSAChunkEncryptor] [OK] Decrypted \(combinedEncryptedData.count) bytes → \(decryptedData.count) bytes (\(chunkCount) chunks)")
        return .success(decryptedData)
    }
}
