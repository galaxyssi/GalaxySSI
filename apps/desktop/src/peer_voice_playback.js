const { spawnSync } = require("node:child_process");

const MAX_PLAYBACK_BYTES = 32 * 1024 * 1024;

function containsAscii(bytes, text, searchLimit = 512) {
  const target = Buffer.from(text, "ascii");
  const limit = Math.min(bytes.length, searchLimit);
  return bytes.subarray(0, limit).indexOf(target) >= 0;
}

function isOggOpus(bytes) {
  return bytes.length >= 36
    && bytes[0] === 0x4f
    && bytes[1] === 0x67
    && bytes[2] === 0x67
    && bytes[3] === 0x53
    && containsAscii(bytes, "OpusHead");
}

function exactArrayBuffer(bytes) {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}

function preparePeerVoicePlayback(arrayBuffer, mimeType, options = {}) {
  const source = Buffer.from(arrayBuffer);
  if (!isOggOpus(source)) {
    const result = { mimeType, arrayBuffer: exactArrayBuffer(source) };
    source.fill(0);
    return result;
  }

  const run = options.spawnSyncImpl || spawnSync;
  const remuxed = run(options.ffmpegPath || "ffmpeg", [
    "-hide_banner", "-loglevel", "error", "-i", "pipe:0",
    "-map", "0:a:0", "-c:a", "copy", "-f", "webm", "pipe:1"
  ], {
    input: source,
    windowsHide: true,
    encoding: null,
    timeout: 30_000,
    maxBuffer: MAX_PLAYBACK_BYTES
  });
  source.fill(0);
  if (remuxed.status !== 0 || !Buffer.isBuffer(remuxed.stdout) || remuxed.stdout.length === 0) {
    remuxed.stdout?.fill?.(0);
    throw new Error("Could not prepare the voice message for playback");
  }
  const output = remuxed.stdout;
  const result = {
    mimeType: "audio/webm; codecs=opus",
    arrayBuffer: exactArrayBuffer(output)
  };
  output.fill(0);
  return result;
}

module.exports = { isOggOpus, preparePeerVoicePlayback };
