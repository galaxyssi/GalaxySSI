package com.galaxyssi.chat

internal object KnowledgeEmbeddingModel {
    const val ID = "bge-small-zh-v1.5-q8_0"
    const val FILE = "$ID.gguf"
    const val BYTES = 26_472_640L
    const val SHA256 = "5a88d266870fbd27c6f329df60de80e2d4cf3bbd5e6f080bd5c1b2e5abb12039"
    private const val PATH = "CompendiumLabs/bge-small-zh-v1.5-gguf/resolve/5bf683e6a1bd454bbb60ba051088c50731d63fcb/$FILE"
    val urls = listOf("https://huggingface.co/$PATH", "https://hf-mirror.com/$PATH")
    val spec = KnowledgeVectorSpec(SHA256, 512, 512)
}
