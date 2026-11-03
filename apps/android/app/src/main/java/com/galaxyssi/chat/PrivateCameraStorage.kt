package com.galaxyssi.chat

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import java.time.LocalDate

internal object PrivateCameraStorage {
    private const val DIRECTORY = "composer-attachments-v1/camera"
    private const val PROVIDER_ROOT = "composer_camera"

    internal fun createFile(filesDir: File, date: LocalDate = LocalDate.now()): File {
        val month = File(filesDir, "$DIRECTORY/${date.year}/${date.monthValue.toString().padStart(2, '0')}")
        check(month.mkdirs() || month.isDirectory) { "Camera storage is unavailable" }
        return File.createTempFile("photo-", ".jpg", month)
    }

    fun createOutput(context: Context): Uri {
        val file = createFile(context.filesDir)
        return try {
            FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        } catch (error: Exception) {
            file.delete()
            throw error
        }
    }

    private fun resolveOutput(context: Context, uri: Uri): File? {
        if (uri.authority != "${context.packageName}.files" ||
            uri.pathSegments.firstOrNull() != PROVIDER_ROOT) return null
        val root = File(context.filesDir, DIRECTORY).canonicalFile
        val relative = uri.pathSegments.drop(1).joinToString("/")
        val file = File(root, relative).canonicalFile
        return file.takeIf { it.toPath().startsWith(root.toPath()) && it.isFile }
    }

    fun finish(context: Context, output: Uri, accepted: Boolean): Uri? {
        try {
            val file = resolveOutput(context, output)
            // A pending capture from an older installation may still use MediaStore.
            if (file == null) {
                if (output.authority == "media") {
                    if (accepted) return output
                    context.contentResolver.delete(output, null, null)
                }
                return null
            }
            if (!accepted || file.length() == 0L) {
                file.delete()
                return null
            }
            return LocalAttachmentUris.forFile(context, file, file.name, "image/jpeg")
        } finally {
            context.revokeUriPermission(output,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
    }
}
