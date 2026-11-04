package com.galaxyssi.chat

import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec
import org.json.JSONObject

internal enum class HealthBackupIssue { FORMAT, OLDER_VERSION, NEWER_VERSION, UNLOCK, DAMAGED, OTHER_PROFILE, SOURCE_CHANGED, MISSING_MANIFEST }
internal class HealthBackupException(val issue: HealthBackupIssue) : IOException(issue.name)

internal data class HealthBackupOriginal(
    val id: String, val name: String, val mime: String, val bytes: Long, val sha256: String,
    val importedAt: Long, val source: String, val present: Boolean
) {
    init {
        require(HealthProfilePolicy.uuid(id) && name.isNotBlank() && name.length <= 240 && mime.length <= 120 &&
            bytes > 0 && HEALTH_BACKUP_HASH.matches(sha256) && importedAt > 0 && source.length <= 120)
    }

    fun json() = JSONObject().put("id", id).put("name", name).put("mime", mime).put("bytes", bytes)
        .put("sha256", sha256).put("imported_at", importedAt).put("source", source).put("present", present)

    companion object {
        fun from(j: JSONObject) = HealthBackupOriginal(j.getString("id"), j.getString("name"), j.getString("mime"),
            j.getLong("bytes"), j.getString("sha256"), j.getLong("imported_at"), j.getString("source"), j.getBoolean("present"))
        fun from(value: HealthOriginal, present: Boolean) = with(value) {
            HealthBackupOriginal(id, name, mime, size, sha256, importedAt, source, present)
        }
    }
}

internal data class HealthBackupManifest(
    val id: String, val createdAt: Long, val owner: String, val records: Long, val originals: Int, val missing: Int,
    val linked: Long, val originalBytes: Long, val first: Long, val last: Long
) {
    init {
        require(HealthProfilePolicy.uuid(id) && createdAt > 0 && owner.length <= 120 && owner.none(Char::isISOControl))
        require(records >= 0 && originals in 0..HealthBackupCodec.MAX_ORIGINALS && missing in 0..originals &&
            linked in 0..records && originalBytes >= 0 && first >= 0 && last >= first)
        require(if (records == 0L) first == 0L && last == 0L else first > 0)
    }

    fun json() = JSONObject().put("id", id).put("created_at", createdAt).put("profile", "self").put("owner", owner)
        .put("records", records).put("originals", originals).put("missing", missing).put("linked", linked)
        .put("original_bytes", originalBytes).put("first", first).put("last", last)

    companion object {
        fun from(j: JSONObject): HealthBackupManifest {
            if (j.getString("profile") != "self") throw HealthBackupException(HealthBackupIssue.OTHER_PROFILE)
            return HealthBackupManifest(j.getString("id"), j.getLong("created_at"), j.getString("owner"),
                j.getLong("records"), j.getInt("originals"), j.getInt("missing"), j.getLong("linked"),
                j.getLong("original_bytes"), j.getLong("first"), j.getLong("last"))
        }
    }
}

private val HEALTH_BACKUP_HASH = Regex("[0-9a-f]{64}")

internal object HealthBackupCodec {
    const val VERSION = 1
    const val MAX_ORIGINALS = 100_000
    const val EXTENSION = "ghbackup"
    private const val MAX_FRAME = 256 * 1024
    private const val SALT_BYTES = 16
    private const val PROOF_BYTES = 32
    private const val ITERATIONS = 600_000
    private const val END = 0x47484245
    private val magic = "GSSIHBAK".toByteArray(Charsets.US_ASCII)
    private val random = SecureRandom()

    fun passwordAllowed(password: CharArray) = password.size in 12..256 && password.any { !it.isWhitespace() }

    fun write(output: OutputStream, password: CharArray, manifest: HealthBackupManifest,
        originals: Sequence<HealthBackupOriginal>, copy: (HealthBackupOriginal, OutputStream) -> Unit,
        records: Sequence<HealthObservation>, active: () -> Unit = {}) {
        require(passwordAllowed(password))
        val salt = ByteArray(SALT_BYTES).also(random::nextBytes)
        val header = ByteArrayOutputStream().also { DataOutputStream(it).apply { write(magic); writeInt(VERSION); write(salt) } }.toByteArray()
        keys(password, salt) { proofKey, streamKey ->
            active()
            output.write(header)
            output.write(proof(proofKey, header))
            DataOutputStream(HealthPrivateExportFile.primitive(streamKey).newEncryptingStream(HealthPrivateExportFile.borrowed(output), header)).use { stream ->
                frame(stream, manifest.json())
                val counter = Counter(manifest)
                for (original in originals) {
                    active()
                    counter.original(original)
                    frame(stream, original.json())
                    if (original.present) copy(original, stream)
                }
                for (record in records) {
                    active()
                    counter.record(record)
                    frame(stream, record.json())
                }
                counter.finish()
                stream.writeInt(END)
            }
        }
    }

    // Visitors must stage data only. The package is verified only after the authenticated EOF.
    fun verify(input: InputStream, password: CharArray, active: () -> Unit = {},
        onOriginal: (HealthBackupOriginal) -> OutputStream? = { null },
        onRecord: (HealthObservation) -> Unit = {}): HealthBackupManifest {
        val raw = DataInputStream(input)
        val actualMagic = ByteArray(magic.size)
        try { raw.readFully(actualMagic) } catch (_: EOFException) { fail(HealthBackupIssue.FORMAT) }
        if (!actualMagic.contentEquals(magic)) fail(HealthBackupIssue.FORMAT)
        val version = try { raw.readInt() } catch (_: EOFException) { fail(HealthBackupIssue.DAMAGED) }
        if (version < VERSION) fail(HealthBackupIssue.OLDER_VERSION)
        if (version > VERSION) fail(HealthBackupIssue.NEWER_VERSION)
        if (!passwordAllowed(password)) fail(HealthBackupIssue.UNLOCK)
        val salt = ByteArray(SALT_BYTES)
        val tag = ByteArray(PROOF_BYTES)
        try { raw.readFully(salt); raw.readFully(tag) } catch (_: EOFException) { fail(HealthBackupIssue.DAMAGED) }
        val header = ByteArrayOutputStream().also { DataOutputStream(it).apply { write(magic); writeInt(version); write(salt) } }.toByteArray()
        return keys(password, salt) { proofKey, streamKey ->
            active()
            if (!MessageDigest.isEqual(tag, proof(proofKey, header))) fail(HealthBackupIssue.UNLOCK)
            val stream = parse { DataInputStream(HealthPrivateExportFile.primitive(streamKey).newDecryptingStream(raw, header)) }
            stream.use {
                val manifest = parse { HealthBackupManifest.from(frame(stream)) }
                val counter = Counter(manifest)
                repeat(manifest.originals) {
                    active()
                    val original = parse { HealthBackupOriginal.from(frame(stream)).also(counter::original) }
                    if (original.present) onOriginal(original).use { output -> verifiedOriginal(stream, original, output, active) }
                }
                var seen = 0L
                while (seen < manifest.records) {
                    active()
                    onRecord(parse { HealthObservation.from(frame(stream)).also(counter::record) })
                    seen++
                }
                parse {
                    counter.finish()
                    require(stream.readInt() == END && stream.read() == -1)
                }
                manifest
            }
        }
    }

    private fun verifiedOriginal(input: DataInputStream, original: HealthBackupOriginal, output: OutputStream?, active: () -> Unit) {
        val digest = MessageDigest.getInstance("SHA-256")
        var remaining = original.bytes
        val buffer = ByteArray(64 * 1024)
        try {
            while (remaining != 0L) {
                active()
                val size = minOf(remaining, buffer.size.toLong()).toInt()
                parse { input.readFully(buffer, 0, size) }
                digest.update(buffer, 0, size)
                output?.write(buffer, 0, size)
                remaining -= size
            }
            if (digest.digest().toHex() != original.sha256) fail(HealthBackupIssue.DAMAGED)
        } finally { buffer.fill(0) }
    }

    private class Counter(private val manifest: HealthBackupManifest) {
        private val byId = HashMap<String, String>()
        private var previousOriginal = ""
        private var previousRecord = ""
        private var missing = 0
        private var linked = 0L
        private var count = 0L
        private var bytes = 0L
        private var first = Long.MAX_VALUE
        private var last = 0L

        fun original(value: HealthBackupOriginal) {
            require(byId.size < manifest.originals && value.id > previousOriginal)
            previousOriginal = value.id
            byId[value.id] = value.sha256
            if (value.present) bytes = Math.addExact(bytes, value.bytes) else missing++
        }

        fun record(value: HealthObservation) {
            if (value.profileId != "self") fail(HealthBackupIssue.OTHER_PROFILE)
            require(count < manifest.records && HealthProfilePolicy.uuid(value.id) && value.id > previousRecord &&
                value.revision > 0 && value.receivedAt > 0 && value.draft.recordId.isEmpty() && value.draft.revision == 0 &&
                HealthObservationPolicy.validate(value.draft) == null && value.source.length in 1..120)
            value.draft.evidence?.let {
                if (byId[it.originalId] != it.sha256) fail(HealthBackupIssue.MISSING_MANIFEST)
                linked++
            }
            previousRecord = value.id
            first = minOf(first, value.draft.measuredAt)
            last = maxOf(last, value.draft.measuredAt)
            count++
        }

        fun finish() {
            require(byId.size == manifest.originals && missing == manifest.missing && count == manifest.records &&
                bytes == manifest.originalBytes && linked == manifest.linked && first.takeUnless { count == 0L }.orZero() == manifest.first &&
                last == manifest.last)
        }
    }

    private fun Long?.orZero() = this ?: 0L

    private inline fun <T> parse(block: () -> T): T = try { block() }
        catch (failure: HealthBackupException) { throw failure }
        catch (_: Exception) { fail(HealthBackupIssue.DAMAGED) }

    private fun frame(stream: DataOutputStream, value: JSONObject) {
        val bytes = value.toString().toByteArray(Charsets.UTF_8)
        try { require(bytes.size in 1..MAX_FRAME); stream.writeInt(bytes.size); stream.write(bytes) }
        finally { bytes.fill(0) }
    }

    private fun frame(stream: DataInputStream): JSONObject {
        val size = stream.readInt()
        require(size in 1..MAX_FRAME)
        val bytes = ByteArray(size)
        return try { stream.readFully(bytes); JSONObject(String(bytes, Charsets.UTF_8)) }
        finally { bytes.fill(0) }
    }

    private inline fun <T> keys(password: CharArray, salt: ByteArray, block: (ByteArray, ByteArray) -> T): T {
        val spec = PBEKeySpec(password, salt, ITERATIONS, 256)
        val master = try { SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded }
            finally { spec.clearPassword() }
        try {
            val proofKey = mac(master, "GalaxySSI health backup proof v1".toByteArray(Charsets.US_ASCII))
            val streamKey = mac(master, "GalaxySSI health backup stream v1".toByteArray(Charsets.US_ASCII))
            try { return block(proofKey, streamKey) } finally { proofKey.fill(0); streamKey.fill(0) }
        } finally { master.fill(0) }
    }

    private fun proof(key: ByteArray, header: ByteArray) = mac(key, header)
    private fun mac(key: ByteArray, data: ByteArray) = Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(key, "HmacSHA256")) }.doFinal(data)
    private fun fail(issue: HealthBackupIssue): Nothing = throw HealthBackupException(issue)
    internal fun ByteArray.toHex() = joinToString("") { "%02x".format(it) }
}
