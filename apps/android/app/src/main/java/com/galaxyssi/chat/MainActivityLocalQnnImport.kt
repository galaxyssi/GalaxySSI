package com.galaxyssi.chat

import android.content.Intent
import android.net.Uri
import android.widget.Toast

internal fun MainActivity.selectLocalQnnPackage() {
    startActivityForResult(
        Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/zip"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/zip", "application/octet-stream"))
        },
        REQUEST_IMPORT_LOCAL_QNN_PACKAGE
    )
}

internal fun MainActivity.importLocalQnnPackageFromUri(uri: Uri) {
    Toast.makeText(this, R.string.local_model_qnn_import_started, Toast.LENGTH_SHORT).show()
    cloudExecutor.execute {
        val result = runCatching {
            contentResolver.openInputStream(uri).use { input ->
                LocalModelManager.importSignedQnnDeployment(
                    context = this,
                    input = requireNotNull(input) { "Unable to open the selected QNN package" }
                )
            }
        }
        handler.post {
            result.onSuccess { profile ->
                Toast.makeText(
                    this,
                    getString(R.string.local_model_qnn_import_complete, profile.displayName),
                    Toast.LENGTH_LONG
                ).show()
                showLocalModelFeaturePage()
            }.onFailure { error ->
                Toast.makeText(
                    this,
                    getString(R.string.local_model_qnn_import_failed, error.message.orEmpty()),
                    Toast.LENGTH_LONG
                ).show()
            }
        }
    }
}
