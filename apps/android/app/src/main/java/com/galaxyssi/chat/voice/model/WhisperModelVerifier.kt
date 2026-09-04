package com.galaxyssi.chat.voice.model

import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

enum class WhisperVerificationFailure {
    MISSING,
    NOT_A_FILE,
    SIZE_MISMATCH,
    SHA256_MISMATCH,
    IO_ERROR
}

data class WhisperVerificationResult(
    val valid: Boolean,
    val actualSizeBytes: Long = 0L,
    val actualSha256: String = "",
    val failure: WhisperVerificationFailure? = null,
    val detail: String = ""
)

object WhisperModelVerifier {
    private const val BUFFER_SIZE = 1024 * 1024

    fun verify(file: File, profile: WhisperModelProfile): WhisperVerificationResult {
        if (!file.exists()) {
            return WhisperVerificationResult(false, failure = WhisperVerificationFailure.MISSING)
        }
        if (!file.isFile) {
            return WhisperVerificationResult(false, failure = WhisperVerificationFailure.NOT_A_FILE)
        }
        val actualSize = file.length()
        if (actualSize != profile.expectedSizeBytes) {
            return WhisperVerificationResult(
                valid = false,
                actualSizeBytes = actualSize,
                failure = WhisperVerificationFailure.SIZE_MISMATCH,
                detail = "Expected ${profile.expectedSizeBytes} bytes but found $actualSize"
            )
        }
        return runCatching {
            val actualSha = sha256(file)
            if (actualSha == profile.sha256) {
                WhisperVerificationResult(true, actualSize, actualSha)
            } else {
                WhisperVerificationResult(
                    valid = false,
                    actualSizeBytes = actualSize,
                    actualSha256 = actualSha,
                    failure = WhisperVerificationFailure.SHA256_MISMATCH,
                    detail = "SHA-256 does not match the pinned model profile"
                )
            }
        }.getOrElse { error ->
            WhisperVerificationResult(
                valid = false,
                actualSizeBytes = actualSize,
                failure = WhisperVerificationFailure.IO_ERROR,
                detail = error.message.orEmpty()
            )
        }
    }

    fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(BUFFER_SIZE)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                if (read > 0) digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { byte -> "%02x".format(byte) }
    }
}
