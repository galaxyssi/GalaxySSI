package com.galaxyssi.chat.voice.audio

import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream

object PcmWaveFileAdapter {
    fun write(snapshot: PcmSnapshot, directory: File, stem: String): File {
        require(snapshot.samples.isNotEmpty()) { "PCM snapshot is empty" }
        directory.mkdirs()
        val safeStem = stem.replace(Regex("[^A-Za-z0-9._-]"), "_").take(80).ifBlank { "voice" }
        val target = File(directory, "$safeStem.wav")
        val temporary = File(directory, "$safeStem.wav.partial")
        BufferedOutputStream(FileOutputStream(temporary)).use { output ->
            val dataBytes = snapshot.samples.size * 2
            output.write("RIFF".toByteArray(Charsets.US_ASCII))
            output.writeLe32(36 + dataBytes)
            output.write("WAVEfmt ".toByteArray(Charsets.US_ASCII))
            output.writeLe32(16)
            output.writeLe16(1)
            output.writeLe16(1)
            output.writeLe32(snapshot.sampleRateHz)
            output.writeLe32(snapshot.sampleRateHz * 2)
            output.writeLe16(2)
            output.writeLe16(16)
            output.write("data".toByteArray(Charsets.US_ASCII))
            output.writeLe32(dataBytes)
            snapshot.samples.forEach { output.writeLe16(it.toInt()) }
        }
        if (target.exists()) target.delete()
        check(temporary.renameTo(target)) { "Unable to finalize PCM wave file" }
        return target
    }

    private fun BufferedOutputStream.writeLe16(value: Int) {
        write(value and 0xff)
        write(value ushr 8 and 0xff)
    }

    private fun BufferedOutputStream.writeLe32(value: Int) {
        write(value and 0xff)
        write(value ushr 8 and 0xff)
        write(value ushr 16 and 0xff)
        write(value ushr 24 and 0xff)
    }
}
