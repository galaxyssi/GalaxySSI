const MAX_WAV_BYTES = 700_000;
const json = (value, status = 200) => new Response(JSON.stringify(value), {
  status,
  headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
});

function authorized(request, secret) {
  const supplied = request.headers.get("authorization")?.replace(/^Bearer /, "") || "";
  if (!secret || secret.length < 32 || supplied.length !== secret.length) return false;
  let mismatch = 0;
  for (let i = 0; i < secret.length; i++) mismatch |= secret.charCodeAt(i) ^ supplied.charCodeAt(i);
  return mismatch === 0;
}

async function boundedBytes(request) {
  const announced = Number(request.headers.get("content-length"));
  if (announced > MAX_WAV_BYTES) throw new RangeError("audio too large");
  const reader = request.body?.getReader();
  if (!reader) throw new TypeError("missing audio");
  const chunks = [];
  let length = 0;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    length += value.length;
    if (length > MAX_WAV_BYTES) {
      await reader.cancel();
      throw new RangeError("audio too large");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return bytes;
}

function validWav(bytes) {
  if (bytes.length < 44) return false;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const label = (offset) => String.fromCharCode(...bytes.subarray(offset, offset + 4));
  return label(0) === "RIFF" && label(8) === "WAVE" && label(12) === "fmt " &&
    label(36) === "data" && view.getUint32(16, true) === 16 &&
    view.getUint16(20, true) === 1 && view.getUint16(22, true) === 1 &&
    view.getUint32(24, true) === 16000 && view.getUint16(34, true) === 16 &&
    view.getUint32(40, true) === bytes.length - 44;
}

function base64(bytes) {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 8192)
    binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
  return btoa(binary);
}

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;
    if (path === "/health" && request.method === "GET") return json({ ok: true });
    if (path !== "/transcribe") return json({ error: "not found" }, 404);
    if (request.method !== "POST") return json({ error: "method not allowed" }, 405);
    if (!env.AI || !env.DEVICE_TOKEN) return json({ error: "proxy not configured" }, 503);
    if (!authorized(request, env.DEVICE_TOKEN)) return json({ error: "unauthorized" }, 401);
    try {
      const bytes = await boundedBytes(request);
      if (!validWav(bytes)) return json({ error: "expected 16 kHz mono PCM16 WAV" }, 400);
      const result = await env.AI.run("@cf/openai/whisper-large-v3-turbo", {
        audio: base64(bytes), task: "transcribe", condition_on_previous_text: false,
      });
      return json({ text: String(result?.text || "").trim().slice(0, 4000) });
    } catch (error) {
      if (error instanceof RangeError) return json({ error: "audio too large" }, 413);
      if (error instanceof TypeError) return json({ error: "invalid audio" }, 400);
      return json({ error: "transcription unavailable" }, 502);
    }
  },
};
