package com.signalasi.chat

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.ByteArrayInputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.security.KeyStore
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.Cipher
import javax.crypto.CipherInputStream
import javax.crypto.CipherOutputStream
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal object AttachmentAtRestCipher {
    private const val KEYSTORE = "AndroidKeyStore"
    private const val KEY_ALIAS = "signalasi_attachment_storage_v1"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128
    private const val COPY_BUFFER_BYTES = 64 * 1024
    private val magic = "SASIENC1".toByteArray(Charsets.US_ASCII)

    data class Metadata(val plaintextLength: Long)

    fun encryptFile(
        source: File,
        destination: File,
        keyOverride: SecretKey? = null
    ) {
        require(source.isFile) { "Attachment source is unavailable" }
        source.inputStream().buffered().use { input ->
            encryptStream(input, source.length(), destination, keyOverride)
        }
    }

    fun encryptBytes(
        plaintext: ByteArray,
        destination: File,
        keyOverride: SecretKey? = null
    ) {
        ByteArrayInputStream(plaintext).use { input ->
            encryptStream(input, plaintext.size.toLong(), destination, keyOverride)
        }
    }

    fun encryptStream(
        input: InputStream,
        plaintextLength: Long,
        destination: File,
        keyOverride: SecretKey? = null,
        onPlaintext: ((ByteArray, Int) -> Unit)? = null
    ) {
        require(plaintextLength >= 0L) { "Attachment length is invalid" }
        destination.parentFile?.let { check(it.mkdirs() || it.isDirectory) }
        val temporary = File(destination.parentFile, ".${destination.name}.encrypting")
        temporary.delete()
        val header = header(plaintextLength)
        val cipher = Cipher.getInstance(TRANSFORMATION).apply {
            init(Cipher.ENCRYPT_MODE, keyOverride ?: key())
            updateAAD(header)
        }
        val iv = requireNotNull(cipher.iv).copyOf().also {
            require(it.size == IV_BYTES) { "Attachment encryption IV is invalid" }
        }
        var copied = 0L
        try {
            FileOutputStream(temporary).use { fileOutput ->
                DataOutputStream(BufferedOutputStream(fileOutput)).use { output ->
                    output.write(header)
                    output.write(iv)
                    CipherOutputStream(NonClosingOutputStream(output), cipher).use { encrypted ->
                        val buffer = ByteArray(COPY_BUFFER_BYTES)
                        try {
                            while (true) {
                                val read = input.read(buffer)
                                if (read < 0) break
                                if (read == 0) continue
                                copied += read
                                require(copied <= plaintextLength) { "Attachment source exceeded its declared length" }
                                onPlaintext?.invoke(buffer, read)
                                encrypted.write(buffer, 0, read)
                            }
                        } finally {
                            buffer.fill(0)
                        }
                    }
                    output.flush()
                    fileOutput.fd.sync()
                }
            }
            require(copied == plaintextLength) { "Attachment source was truncated" }
            require(metadata(temporary).plaintextLength == plaintextLength)
            destination.delete()
            check(temporary.renameTo(destination)) { "Encrypted attachment could not be committed" }
        } finally {
            iv.fill(0)
            header.fill(0)
            temporary.takeIf { it.exists() }?.delete()
        }
    }

    fun openDecryptedInput(file: File, keyOverride: SecretKey? = null): InputStream {
        val source = DataInputStream(BufferedInputStream(FileInputStream(file)))
        var header: ByteArray? = null
        var iv: ByteArray? = null
        return try {
            header = ByteArray(headerSize()).also(source::readFully)
            val parsed = parseHeader(requireNotNull(header))
            iv = ByteArray(IV_BYTES).also(source::readFully)
            val cipher = Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.DECRYPT_MODE, keyOverride ?: key(), GCMParameterSpec(TAG_BITS, requireNotNull(iv)))
                updateAAD(requireNotNull(header))
            }
            LengthCheckedInputStream(CipherInputStream(source, cipher), parsed.plaintextLength)
        } catch (error: Throwable) {
            source.close()
            throw error
        } finally {
            header?.fill(0)
            iv?.fill(0)
        }
    }

    fun decryptBytes(file: File, keyOverride: SecretKey? = null): ByteArray =
        openDecryptedInput(file, keyOverride).use { input -> input.readBytes() }

    fun copyDecrypted(
        file: File,
        output: OutputStream,
        keyOverride: SecretKey? = null
    ): Long = openDecryptedInput(file, keyOverride).use { input ->
        val buffer = ByteArray(COPY_BUFFER_BYTES)
        var copied = 0L
        try {
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                if (read == 0) continue
                output.write(buffer, 0, read)
                copied += read
            }
            copied
        } finally {
            buffer.fill(0)
        }
    }

    fun metadata(file: File): Metadata {
        require(file.isFile && file.length() >= (headerSize() + IV_BYTES + TAG_BITS / 8)) {
            "Encrypted attachment is unavailable"
        }
        DataInputStream(BufferedInputStream(FileInputStream(file))).use { input ->
            val header = ByteArray(headerSize()).also(input::readFully)
            return try {
                parseHeader(header)
            } finally {
                header.fill(0)
            }
        }
    }

    fun isEncrypted(file: File): Boolean = runCatching { metadata(file) }.isSuccess

    private fun header(plaintextLength: Long): ByteArray = java.nio.ByteBuffer
        .allocate(headerSize())
        .order(java.nio.ByteOrder.BIG_ENDIAN)
        .put(magic)
        .putLong(plaintextLength)
        .array()

    private fun parseHeader(header: ByteArray): Metadata {
        require(header.size == headerSize())
        require(header.copyOfRange(0, magic.size).contentEquals(magic)) {
            "Attachment encryption header is invalid"
        }
        val length = java.nio.ByteBuffer.wrap(header, magic.size, Long.SIZE_BYTES)
            .order(java.nio.ByteOrder.BIG_ENDIAN)
            .long
        require(length >= 0L) { "Attachment plaintext length is invalid" }
        return Metadata(length)
    }

    private fun headerSize(): Int = magic.size + Long.SIZE_BYTES

    @Synchronized
    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build()
        )
        return generator.generateKey()
    }

    private class LengthCheckedInputStream(
        input: InputStream,
        private val expectedLength: Long
    ) : java.io.FilterInputStream(input) {
        private var count = 0L

        override fun read(): Int {
            val value = super.read()
            if (value >= 0) count++ else verifyLength()
            return value
        }

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            val read = super.read(buffer, offset, length)
            if (read > 0) count += read else if (read < 0) verifyLength()
            return read
        }

        override fun close() {
            var failure: Throwable? = null
            try {
                val drain = ByteArray(8 * 1024)
                try {
                    while (read(drain) >= 0) Unit
                } finally {
                    drain.fill(0)
                }
            } catch (error: Throwable) {
                failure = error
            }
            try {
                super.close()
            } catch (error: Throwable) {
                if (failure == null) failure = error else failure.addSuppressed(error)
            }
            failure?.let { throw it }
        }

        private fun verifyLength() {
            require(count == expectedLength) { "Encrypted attachment length check failed" }
        }
    }

    private class NonClosingOutputStream(output: OutputStream) : java.io.FilterOutputStream(output) {
        override fun close() {
            flush()
        }
    }
}

internal object EncryptedAttachmentUris {
    private const val AUTHORITY_SUFFIX = ".encrypted-attachments"
    private const val PATH_FILE = "file"

    fun forFile(
        context: Context,
        file: File,
        name: String = file.name,
        mimeType: String = ""
    ): Uri {
        val root = context.filesDir.canonicalFile
        val canonical = file.canonicalFile
        require(canonical.toPath().startsWith(root.toPath())) { "Attachment is outside private storage" }
        require(AttachmentAtRestCipher.isEncrypted(canonical)) { "Attachment is not encrypted" }
        val relative = root.toPath().relativize(canonical.toPath()).toString().replace('\\', '/')
        val encoded = Base64.encodeToString(relative.toByteArray(Charsets.UTF_8), Base64.URL_SAFE or Base64.NO_WRAP)
        return Uri.Builder()
            .scheme("content")
            .authority(context.packageName + AUTHORITY_SUFFIX)
            .appendPath(PATH_FILE)
            .appendPath(encoded)
            .appendQueryParameter("name", name.take(160))
            .apply { if (mimeType.isNotBlank()) appendQueryParameter("mime", mimeType.take(160)) }
            .build()
    }

    fun resolve(context: Context, uri: Uri): File? {
        if (uri.authority != context.packageName + AUTHORITY_SUFFIX || uri.pathSegments.size != 2 ||
            uri.pathSegments.firstOrNull() != PATH_FILE
        ) return null
        val relative = runCatching {
            String(Base64.decode(uri.pathSegments[1], Base64.URL_SAFE or Base64.NO_WRAP), Charsets.UTF_8)
        }.getOrNull() ?: return null
        val root = context.filesDir.canonicalFile
        val file = runCatching { File(root, relative).canonicalFile }.getOrNull() ?: return null
        return file.takeIf {
            it.toPath().startsWith(root.toPath()) && AttachmentAtRestCipher.isEncrypted(it)
        }
    }
}

internal object AttachmentAtRestStorageLifecycle {
    private val initialized = AtomicBoolean(false)
    private val legacyPlaintextRoots = listOf(
        "peer-incoming-attachments-v1",
        "peer-message-attachments-v1",
        "agent-link-outgoing-attachments-v1",
        "agent-rich-output",
        "desktop-artifacts"
    )

    fun initialize(context: Context) {
        if (!initialized.compareAndSet(false, true)) return
        legacyPlaintextRoots.forEach { name ->
            File(context.applicationContext.filesDir, name).deleteRecursively()
        }
    }
}

class EncryptedAttachmentContentProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        require(mode == "r") { "Encrypted attachments are read-only" }
        val appContext = requireNotNull(context).applicationContext
        val encrypted = EncryptedAttachmentUris.resolve(appContext, uri)
            ?: throw java.io.FileNotFoundException("Encrypted attachment is unavailable")
        val pipe = ParcelFileDescriptor.createPipe()
        Thread({
            ParcelFileDescriptor.AutoCloseOutputStream(pipe[1]).use { output ->
                runCatching { AttachmentAtRestCipher.copyDecrypted(encrypted, output) }
            }
        }, "signalasi-attachment-decrypt").apply { isDaemon = true }.start()
        return pipe[0]
    }

    override fun getType(uri: Uri): String? = uri.getQueryParameter("mime")

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor? {
        val appContext = context?.applicationContext ?: return null
        val encrypted = EncryptedAttachmentUris.resolve(appContext, uri) ?: return null
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        return MatrixCursor(columns).apply {
            val row = newRow()
            columns.forEach { column ->
                when (column) {
                    OpenableColumns.DISPLAY_NAME -> row.add(uri.getQueryParameter("name") ?: encrypted.name)
                    OpenableColumns.SIZE -> row.add(AttachmentAtRestCipher.metadata(encrypted).plaintextLength)
                    else -> row.add(null)
                }
            }
        }
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int =
        throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int =
        throw UnsupportedOperationException()
}
