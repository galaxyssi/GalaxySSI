package com.galaxyssi.chat.voice.model

import java.io.File

enum class WhisperLegacyMigrationState {
    NOT_FOUND,
    MIGRATED,
    ALREADY_INSTALLED,
    REJECTED
}

data class WhisperLegacyMigrationResult(
    val state: WhisperLegacyMigrationState,
    val source: File? = null,
    val failure: WhisperModelInstallFailure? = null,
    val detail: String = ""
)

object WhisperLegacyMigration {
    fun migrate(
        profile: WhisperModelProfile,
        candidates: List<File>,
        storage: WhisperModelStorage,
        deleteMigratedSource: Boolean = false
    ): WhisperLegacyMigrationResult {
        if (storage.inspect(profile).installed) {
            return WhisperLegacyMigrationResult(WhisperLegacyMigrationState.ALREADY_INSTALLED)
        }
        val existing = candidates.distinctBy { runCatching { it.canonicalPath }.getOrDefault(it.absolutePath) }
            .filter(File::isFile)
        if (existing.isEmpty()) return WhisperLegacyMigrationResult(WhisperLegacyMigrationState.NOT_FOUND)
        var lastFailure: WhisperLegacyMigrationResult? = null
        existing.forEach { candidate ->
            try {
                storage.install(candidate, profile, "legacy:${candidate.name}")
                if (deleteMigratedSource) candidate.delete()
                return WhisperLegacyMigrationResult(WhisperLegacyMigrationState.MIGRATED, candidate)
            } catch (error: WhisperModelInstallException) {
                lastFailure = WhisperLegacyMigrationResult(
                    state = WhisperLegacyMigrationState.REJECTED,
                    source = candidate,
                    failure = error.failure,
                    detail = error.message.orEmpty()
                )
            }
        }
        return requireNotNull(lastFailure)
    }
}
