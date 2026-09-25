import assert from "node:assert/strict";
import test from "node:test";
import worker from "./index.js";

const token = "0123456789abcdef0123456789abcdef";
function wav(samples = 16000) {
  const bytes = new Uint8Array(44 + samples * 2);
  const view = new DataView(bytes.buffer);
  const label = (offset, value) => [...value].forEach((letter, i) => { bytes[offset + i] = letter.charCodeAt(0); });
  label(0, "RIFF"); view.setUint32(4, bytes.length - 8, true);
  label(8, "WAVE"); label(12, "fmt "); view.setUint32(16, 16, true);
  view.setUint16(20, 1, true); view.setUint16(22, 1, true);
  view.setUint32(24, 16000, true); view.setUint32(28, 32000, true);
  view.setUint16(32, 2, true); view.setUint16(34, 16, true);
  label(36, "data"); view.setUint32(40, samples * 2, true);
  return bytes;
}
function request(audio, authorization = token) {
  return new Request("https://example.workers.dev/transcribe", {
    method: "POST", headers: { authorization: `Bearer ${authorization}`, "content-type": "audio/wav" }, body: audio,
  });
}

test("accepts an authenticated 16 kHz WAV and returns the model transcript", async () => {
  let called = false;
  const env = { DEVICE_TOKEN: token, AI: { run: async (model, input) => {
    called = true;
    assert.equal(model, "@cf/openai/whisper-large-v3-turbo");
    assert.equal(Buffer.from(input.audio, "base64").length, wav().length);
    return { text: "几点了" };
  } } };
  const response = await worker.fetch(request(wav()), env);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { text: "几点了" });
  assert.equal(called, true);
});

test("rejects an incorrect device token without calling AI", async () => {
  const response = await worker.fetch(request(wav(), "wrong"), {
    DEVICE_TOKEN: token, AI: { run: () => { throw Error("must not run"); } },
  });
  assert.equal(response.status, 401);
});

test("rejects malformed or oversized audio", async () => {
  const env = { DEVICE_TOKEN: token, AI: { run: () => { throw Error("must not run"); } } };
  assert.equal((await worker.fetch(request(new Uint8Array(20)), env)).status, 400);
  assert.equal((await worker.fetch(request(wav(360000)), env)).status, 413);
});
