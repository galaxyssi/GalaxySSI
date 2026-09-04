package com.galaxyssi.chat.voice.model

import android.os.Environment
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WhisperStorageCapacityInstrumentedTest {
    @Test
    fun reportsCapacityForPrivateAndUncreatedDownloadDirectories() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val privateModels = File(context.filesDir, "voice/whisper/capacity-test")
        val externalDownloads = File(
            requireNotNull(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)),
            "galaxyssi-asr-partials/capacity-test/nested"
        )

        assertTrue(WhisperStorageCapacity.availableBytes(privateModels) > 0L)
        assertTrue(WhisperStorageCapacity.availableBytes(externalDownloads) > 0L)

        privateModels.deleteRecursively()
        externalDownloads.deleteRecursively()
    }
}
