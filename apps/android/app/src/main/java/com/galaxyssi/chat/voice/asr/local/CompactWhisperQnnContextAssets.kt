package com.galaxyssi.chat.voice.asr.local

internal object CompactWhisperQnnContextAssets {
    fun forPackage(model: QnnWhisperPackage): List<QnnContextWrapperAsset> = when (model.id) {
        "whisper-tiny-qnn-float-s26u" -> wrappers(
            root = "voice/qnn/whisper-tiny-s26u",
            encoderSize = 865L,
            encoderSha = "8e21ada842d67862d695f1b19c61d60ef00d419e08a68ad1b18b578145107fa0",
            decoderSize = 2_051L,
            decoderSha = "5b3f0979ddd5dedc947c57b2275ec0799f4ac0a642ea3e905e3772d77b54edb0"
        )
        "whisper-base-qnn-float-s26u" -> wrappers(
            root = "voice/qnn/whisper-base-s26u",
            encoderSize = 1_109L,
            encoderSha = "dbe0f7dc631274fe25981e28060cb39fd66708a7f76f95a4b0cca84e78584d5e",
            decoderSize = 2_823L,
            decoderSha = "a4e05ce03997917633c46e655021476cb76ce36b39fc8c3be2ed430bc855f12c"
        )
        "whisper-small-qnn-w8a16-s26u" -> wrappers(
            root = "voice/qnn/whisper-small-w8a16-s26u",
            encoderSize = 1_849L,
            encoderSha = "616b9e235ab0b22901e423824417ea94536f719fca70ea27dc3c6c02e3414957",
            decoderSize = 5_163L,
            decoderSha = "f7be711e78a3051140198c3bfb9ddd17c1a77d994700b3166fac68990b6acd06"
        )
        "whisper-small-qnn-float-s26u" -> wrappers(
            root = "voice/qnn/whisper-small-float-s26u",
            encoderSize = 1_849L,
            encoderSha = "affcde4bbb489e9962099647732979110e9b3b2011eb26352c03d655fba636a9",
            decoderSize = 5_163L,
            decoderSha = "8d29e31180e95880d8fd96cfacc0dd976516be2e4efc9e00e99f2c88cd3caac0"
        )
        else -> error("Unsupported compact QNN Whisper package")
    }

    private fun wrappers(
        root: String,
        encoderSize: Long,
        encoderSha: String,
        decoderSize: Long,
        decoderSha: String
    ) = listOf(
        QnnContextWrapperAsset(
            assetPath = "$root/encoder_context.onnx",
            installedName = "encoder_context.onnx",
            sizeBytes = encoderSize,
            sha256 = encoderSha
        ),
        QnnContextWrapperAsset(
            assetPath = "$root/decoder_context.onnx",
            installedName = "decoder_context.onnx",
            sizeBytes = decoderSize,
            sha256 = decoderSha
        )
    )
}
