const assert = require("node:assert/strict");
const test = require("node:test");

const {
  finalizePcmWavHeader,
  isOggOpus,
  preparePeerVoicePlayback
} = require("../src/peer_voice_playback");

function streamingPcmWav() {
  const wav = Buffer.alloc(54);
  wav.write("RIFF", 0, "ascii");
  wav.writeUInt32LE(0xffffffff, 4);
  wav.write("WAVEfmt ", 8, "ascii");
  wav.writeUInt32LE(16, 16);
  wav.writeUInt16LE(1, 20);
  wav.writeUInt16LE(1, 22);
  wav.writeUInt32LE(48_000, 24);
  wav.writeUInt32LE(96_000, 28);
  wav.writeUInt16LE(2, 32);
  wav.writeUInt16LE(16, 34);
  wav.write("data", 36, "ascii");
  wav.writeUInt32LE(0xffffffff, 40);
  return wav;
}

test("detects Ogg Opus and decodes it to Chromium-compatible PCM WAV", () => {
  const source = Buffer.concat([
    Buffer.from("OggS", "ascii"),
    Buffer.alloc(24),
    Buffer.from("OpusHead", "ascii"),
    Buffer.alloc(8)
  ]);
  const wav = streamingPcmWav();
  assert.equal(isOggOpus(source), true);
  const result = preparePeerVoicePlayback(
    source.buffer.slice(source.byteOffset, source.byteOffset + source.byteLength),
    "audio/ogg",
    { spawnSyncImpl: () => ({ status: 0, stdout: Buffer.from(wav), stderr: Buffer.alloc(0) }) }
  );

  assert.equal(result.mimeType, "audio/wav");
  const prepared = Buffer.from(result.arrayBuffer);
  assert.equal(prepared.readUInt32LE(4), prepared.length - 8);
  assert.equal(prepared.readUInt32LE(40), prepared.length - 44);
});

test("finalizes streaming WAV length fields for strict media players", () => {
  const wav = finalizePcmWavHeader(streamingPcmWav());
  assert.equal(wav.readUInt32LE(4), wav.length - 8);
  assert.equal(wav.readUInt32LE(40), wav.length - 44);
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
