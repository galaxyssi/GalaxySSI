package com.galaxyssi.chat

import java.io.InputStream
import java.io.OutputStream

internal data class HealthOriginalSaveScope(val originalId: String, val streamId: String)

internal class HealthOriginalSaveChanged : IllegalStateException("The reviewed health original is no longer available")

internal object HealthOriginalSave {
    fun saveVerified(
        originals: HealthOriginalStore,
        scope: HealthOriginalSaveScope,
        open: () -> OutputStream,
        readBack: () -> InputStream,
        removeIncomplete: () -> Unit,
    ) {
        val original = originals.original(scope.originalId)
        if (original == null || original.streamId != scope.streamId || original.reviewOnly || !originals.present(original))
            throw HealthOriginalSaveChanged()
        var opened = false
        try {
            open().use { output ->
                opened = true
                originals.copyVerified(original, output)
            }
            HealthPrivateExportFile.verify(readBack(), HealthExportDigest(original.size, original.sha256))
        } catch (failure: Exception) {
            if (opened) runCatching(removeIncomplete)
            throw failure
        }
    }
}
