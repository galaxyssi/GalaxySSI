const MAX_AUDIO_BYTES = 8 * 1024 * 1024;
const MEDIA_TYPES = new Set(["audio/webm", "audio/ogg", "audio/wav", "audio/x-wav"]);

async function transcribeComposerSpeech(payload = {}, { startBackend, origin, token, fetchImpl = fetch }) {
  const input = payload.audio;
  if (!(input instanceof Uint8Array) || !input.length || input.length > MAX_AUDIO_BYTES) {
    return { ok: false, code: "stt_invalid_audio" };
  }
  const audio = Buffer.from(input);
  try {
    const mimeType = String(payload.mimeType || "").split(";", 1)[0];
    if (!MEDIA_TYPES.has(mimeType)) return { ok: false, code: "stt_invalid_audio" };
    await startBackend();
    const response = await fetchImpl(`${origin}/api/stt/transcribe`, {
      method: "POST",
      headers: {
        "Content-Type": mimeType,
        "X-GalaxySSI-Token": token(),
        "X-GalaxySSI-Language": String(payload.language || "auto").slice(0, 16)
      },
      body: audio,
      signal: AbortSignal.timeout(180_000)
    });
    const result = await response.json();
    if (!response.ok) return { ok: false, code: result?.detail?.code || "stt_transcription_failed" };
    return { ok: true, text: String(result.text || ""), language: result.language };
  } catch (error) {
    return { ok: false, code: error.name === "TimeoutError" ? "stt_timeout" : "stt_backend_unavailable" };
  } finally {
    audio.fill(0);
    input.fill(0);
  }
}

module.exports = { transcribeComposerSpeech, MAX_AUDIO_BYTES };
