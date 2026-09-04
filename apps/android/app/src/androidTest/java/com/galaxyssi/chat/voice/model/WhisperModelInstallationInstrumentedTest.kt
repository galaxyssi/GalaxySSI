package com.galaxyssi.chat.voice.model

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.galaxyssi.chat.WhisperModelManager
import com.whispercpp.whisper.WhisperContext
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WhisperModelInstallationInstrumentedTest {
    @Test
    fun bundledTinyIsVerifiedAndLoadedOnlyFromPrivateStorage() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val tiny = WhisperModelCatalog.require("tiny")

        val installed = WhisperModelManager.ensureVerifiedFile(context, tiny)

        assertTrue(installed.canonicalPath.startsWith(context.filesDir.canonicalPath))
        assertEquals(tiny.expectedSizeBytes, installed.length())
        assertEquals(tiny.sha256, WhisperModelVerifier.sha256(installed))
        assertTrue(WhisperModelManager.isAvailable(context, tiny))
        WhisperContext.createContextFromFile(installed.absolutePath).release()
    }

    @Test
    fun largeProfilesAreNotBundledAsAssets() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        listOf("medium", "large", "large_v3_turbo").forEach { id ->
            val profile = WhisperModelCatalog.require(id)
            assertFalse(profile.bundled)
            assertTrue(runCatching { context.assets.open(profile.fileName).close() }.isFailure)
        }
    }
}
