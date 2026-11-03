package com.galaxyssi.chat.voice.audio

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.res.AssetManager
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.LongBuffer
import java.security.MessageDigest

/** CPU-only, one inference thread; owns no microphone or ASR state. */
internal class SileroSpeechProbabilityModel(private val assets: AssetManager) : SpeechProbabilityModel {
    private var session: OrtSession? = null
    private val audio = directFloats(576)
    private val state = directFloats(256)
    private val nextState = directFloats(256)
    private val output = directFloats(1)
    private val tensors = mutableListOf<OnnxTensor>()
    private var inputs = emptyMap<String, OnnxTensor>()
    private var outputs = emptyMap<String, OnnxTensor>()

    override fun prepare() {
        if (session != null) return
        val bytes = assets.open(MODEL_PATH).use { it.readBytes() }
        try {
            val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
                .joinToString("") { "%02x".format(it) }
            check(digest == MODEL_SHA256) { "Bundled speech detector checksum mismatch" }
            val environment = OrtEnvironment.getEnvironment()
            OrtSession.SessionOptions().use { options ->
                options.setIntraOpNumThreads(1)
                options.setInterOpNumThreads(1)
                options.addConfigEntry("session.intra_op.allow_spinning", "0")
                options.addConfigEntry("session.inter_op.allow_spinning", "0")
                session = environment.createSession(bytes, options)
            }
            fun tensor(buffer: FloatBuffer, vararg shape: Long): OnnxTensor =
                OnnxTensor.createTensor(environment, buffer, shape).also(tensors::add)
            val sampleRate = OnnxTensor.createTensor(environment, LongBuffer.wrap(longArrayOf(16_000)), longArrayOf())
                .also(tensors::add)
            inputs = mapOf("input" to tensor(audio, 1, 576), "state" to tensor(state, 2, 1, 128), "sr" to sampleRate)
            outputs = mapOf("output" to tensor(output, 1, 1), "stateN" to tensor(nextState, 2, 1, 128))
            check(session!!.inputNames == inputs.keys && session!!.outputNames == outputs.keys)
            reset()
        } catch (error: Throwable) {
            close()
            throw error
        } finally {
            bytes.fill(0)
        }
    }

    override fun probability(samples: FloatArray): Float {
        require(samples.size == NeuralSpeechVad.WINDOW_SAMPLES)
        val current = checkNotNull(session) { "Speech detector is not prepared" }
        samples.forEachIndexed { index, value -> audio.put(index + 64, value) }
        current.run(inputs, outputs).use {
            repeat(256) { index -> state.put(index, nextState.get(index)) }
            repeat(64) { index -> audio.put(index, samples[448 + index]) }
            return output.get(0)
        }
    }

    override fun reset() {
        listOf(audio, state, nextState, output).forEach { buffer ->
            repeat(buffer.capacity()) { buffer.put(it, 0f) }
        }
    }

    override fun close() {
        reset()
        tensors.forEach { runCatching { it.close() } }
        tensors.clear()
        inputs = emptyMap()
        outputs = emptyMap()
        session?.close()
        session = null
    }

    companion object {
        const val MODEL_PATH = "voice/vad/silero_vad_16k_op15.onnx"
        const val MODEL_SHA256 = "7ed98ddbad84ccac4cd0aeb3099049280713df825c610a8ed34543318f1b2c49"

        private fun directFloats(count: Int): FloatBuffer = ByteBuffer.allocateDirect(count * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer()
    }
}
