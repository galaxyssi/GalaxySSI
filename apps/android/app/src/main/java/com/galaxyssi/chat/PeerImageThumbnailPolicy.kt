package com.galaxyssi.chat

import java.io.File
import java.security.MessageDigest

internal object PeerImageThumbnailPolicy {
    const val LEGACY_FILE_NAME = ".peer-image-thumbnail-v1.sasie"

    fun cacheIdentity(attachment: PeerChatAttachment): String {
        val source = attachment.uri.ifBlank { attachment.artifactUri }
            .ifBlank { attachment.transferId }
            .ifBlank { attachment.sha256 }
            .ifBlank { "${attachment.name}:${attachment.sizeBytes}" }
        return "$source\u0000${attachment.sha256}"
    }

    fun storedFile(original: File, attachment: PeerChatAttachment): File {
        // Imports share monthly directories; a directory is not an image identity.
        val identity = "${original.name}\u0000${attachment.sha256}"
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(identity.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        return File(original.parentFile, ".peer-image-thumbnail-v2-$digest.sasie")
    }
}
