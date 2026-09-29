package com.galaxyssi.chat

import android.graphics.Bitmap
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BusinessArtifactFormatDeviceTest {
    private fun verifiedArtifact() = JSONObject().apply {
        listOf("received", "container_valid", "version_name_matches", "save_api_pass",
            "download_hash_matches").forEach { put(it, true) }
    }

    @Test fun completeDeliveryRequiresEveryDeclaredArtifact() {
        assertFalse(BusinessArtifactEvidence.allArtifactsVerified(emptyList()))
        val complete = List(4) { verifiedArtifact() }
        assertTrue(BusinessArtifactEvidence.allArtifactsVerified(complete))
        for (field in listOf("received", "container_valid", "version_name_matches", "save_api_pass",
            "download_hash_matches")) {
            val partial = List(4) { verifiedArtifact() }
            partial[1].put(field, false)
            assertFalse(field, BusinessArtifactEvidence.allArtifactsVerified(partial))
            partial[1].remove(field)
            assertFalse("missing $field", BusinessArtifactEvidence.allArtifactsVerified(partial))
        }
    }

    @Test fun renamedJpegCannotPassPngVerification() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val file = File.createTempFile("business-format-", ".png", context.cacheDir)
        val bitmap = Bitmap.createBitmap(8, 8, Bitmap.Config.ARGB_8888)
        try {
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
            assertFalse(BusinessArtifactEvidence.validContainer(file, "png"))
            assertTrue(BusinessArtifactEvidence.validContainer(file, "jpg"))
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            assertTrue(BusinessArtifactEvidence.validContainer(file, "png"))
            assertFalse(BusinessArtifactEvidence.validContainer(file, "jpg"))
        } finally {
            bitmap.recycle()
            file.delete()
        }
    }

    @Test fun everyPreviewMustMatchTheRequestedFormat() {
        fun image(extension: String, valid: Boolean) = JSONObject()
            .put("extension", extension).put("container_valid", valid)
        val office = JSONObject().put("editable_office", true)
        assertTrue(BusinessArtifactEvidence.imageFormatsMatch(office, listOf(image("png", true))))
        assertFalse(BusinessArtifactEvidence.imageFormatsMatch(office,
            listOf(image("png", true), image("png", false))))
        assertFalse(BusinessArtifactEvidence.imageFormatsMatch(office, listOf(image("jpg", true))))
        assertFalse(BusinessArtifactEvidence.imageFormatsMatch(office,
            listOf(image("png", true), image("webp", false).put("type", "IMAGE"))))
        val annotation = JSONObject().put("image_extensions", JSONArray(listOf("png", "jpg", "jpeg")))
        assertTrue(BusinessArtifactEvidence.imageFormatsMatch(annotation,
            listOf(image("png", true), image("jpg", true))))
        assertFalse(BusinessArtifactEvidence.imageFormatsMatch(annotation, emptyList()))
    }
}
