const assert = require("node:assert/strict");
const test = require("node:test");

const {
  isOggOpus,
  preparePeerVoicePlayback
} = require("../src/peer_voice_playback");

test("detects Ogg Opus and remuxes it to Chromium-compatible WebM", () => {
  const source = Buffer.concat([
    Buffer.from("OggS", "ascii"),
    Buffer.alloc(24),
    Buffer.from("OpusHead", "ascii"),
    Buffer.alloc(8)
  ]);
  const webm = Buffer.from([0x1a, 0x45, 0xdf, 0xa3, 0x01]);
  assert.equal(isOggOpus(source), true);
  const result = preparePeerVoicePlayback(
    source.buffer.slice(source.byteOffset, source.byteOffset + source.byteLength),
    "audio/ogg",
    { spawnSyncImpl: () => ({ status: 0, stdout: Buffer.from(webm), stderr: Buffer.alloc(0) }) }
  );

  assert.equal(result.mimeType, "audio/webm; codecs=opus");
  assert.deepEqual(Buffer.from(result.arrayBuffer), webm);
});

test("keeps already supported audio bytes unchanged", () => {
  const source = Buffer.from([0x52, 0x49, 0x46, 0x46, 0x01, 0x02]);
  const expected = Buffer.from(source);
  const input = source.buffer.slice(source.byteOffset, source.byteOffset + source.byteLength);
  const result = preparePeerVoicePlayback(
    input,
    "audio/wav"
  );

  assert.equal(result.mimeType, "audio/wav");
  assert.deepEqual(Buffer.from(result.arrayBuffer), expected);
  assert.deepEqual(Buffer.from(input), Buffer.alloc(source.length));
});
