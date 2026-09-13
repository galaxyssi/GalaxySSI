package com.galaxyssi.chat

import org.json.JSONObject

/** Public adapter around the phone's bounded, digest-checked chunk assembler. */
class WatchWireChunks {
    private val assembler = GalaxySSIMqttChunkAssembler()
    fun accept(scope: String, wire: JSONObject): JSONObject? =
        if (GalaxySSIMqttWireChunking.isChunk(wire)) {
            assembler.accept(scope, wire)?.let(::JSONObject)
        } else wire
}
