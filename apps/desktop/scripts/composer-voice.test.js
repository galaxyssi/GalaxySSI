const test = require("node:test");
const assert = require("node:assert/strict");
const { createCapture, appendTranscript, ERRORS } = require("../src/composer_voice_capture");
const { transcribeComposerSpeech, MAX_AUDIO_BYTES } = require("../src/composer_stt");
const flush = () => new Promise((resolve) => setImmediate(resolve));

function fixture(overrides = {}) {
  let clock = 1000;
  let context = "conversation-a";
  let stopped = 0;
  let calls = 0;
  const states = [], errors = [], texts = [], recordings = [];
  class Recorder extends EventTarget {
    static isTypeSupported() { return true; }
    constructor(stream, options) {
      super(); this.mimeType = options.mimeType; this.state = "inactive"; recordings.push(this);
    }
    start() { this.state = "recording"; }
    stop() {
      this.state = "inactive";
      const event = new Event("dataavailable");
      event.data = new Blob(["recording"]);
      this.dispatchEvent(event);
      this.dispatchEvent(new Event("stop"));
    }
  }
  const stream = { getTracks: () => [{ stop: () => stopped++ }] };
  const capture = createCapture({
    getUserMedia: async () => stream, Recorder,
    transcribe: async () => { calls++; return { ok: true, text: "hello" }; },
    language: () => "auto", context: () => context,
    onText: (text) => texts.push(text), onState: (state) => states.push(state), onError: (e) => errors.push(e),
    now: () => clock, setTimer: () => 1, clearTimer: () => {}, ...overrides
  });
  return { capture, states, errors, texts, recordings, stream, advance: (ms) => { clock += ms; },
    changeContext: () => { context = "conversation-b"; }, get stopped() { return stopped; }, get calls() { return calls; } };
}

test("hold/release transcribes locally, stops microphone, and returns to idle", async () => {
  const f = fixture();
  await f.capture.begin(1, 100);
  assert.equal(f.states.at(-1).phase, "recording");
  f.advance(1000); f.capture.finish(true, 1); await flush();
  assert.deepEqual(f.texts, ["hello"]);
  assert.equal(f.calls, 1); assert.equal(f.stopped, 1);
  assert.equal(f.states.at(-1).phase, "idle"); assert.equal(f.capture.busy, false);
});

for (const reason of ["cancel", "swipe", "short", "wrong-context"]) {
  test(`${reason} does not insert a transcript`, async () => {
    const f = fixture(); await f.capture.begin(1, 100);
    if (reason !== "short") f.advance(1000);
    if (reason === "swipe") f.capture.move(1, 0);
    if (reason === "wrong-context") f.changeContext();
    f.capture.finish(reason !== "cancel", 1); await flush();
    assert.deepEqual(f.texts, []); assert.equal(f.stopped, 1); assert.equal(f.capture.busy, false);
    if (["cancel", "swipe", "short"].includes(reason)) assert.equal(f.calls, 0);
  });
}

test("release during permission prompt does not start recording later", async () => {
  let resolve;
  const f = fixture({ getUserMedia: () => new Promise((r) => { resolve = r; }) });
  const start = f.capture.begin(1, 0); f.capture.finish(true, 1);
  resolve(f.stream); await start;
  assert.equal(f.recordings.length, 0); assert.equal(f.stopped, 1); assert.equal(f.calls, 0);
});

test("cancel pending transcription ignores late results and wipes audio", async () => {
  let resolve, audio;
  const f = fixture({ transcribe: (payload) => { audio = payload.audio; return new Promise((r) => { resolve = r; }); } });
  await f.capture.begin(); f.advance(1000); f.capture.finish(true); await flush();
  f.capture.cancel(); resolve({ ok: true, text: "late" }); await flush();
  assert.deepEqual(f.texts, []); assert.ok(audio.every((n) => n === 0));
});

test("second press and unrelated pointer release cannot interrupt current recording", async () => {
  const f = fixture(); await f.capture.begin(1); await f.capture.begin(2);
  f.capture.finish(true, 2); assert.equal(f.recordings[0].state, "recording");
  assert.equal(f.recordings.length, 1); f.capture.cancel();
});

for (const name of ["NotAllowedError", "NotFoundError", "NotReadableError"]) {
  test(`microphone ${name} is actionable and resets capture`, async () => {
    const f = fixture({ getUserMedia: async () => { throw { name }; } });
    await f.capture.begin(); assert.deepEqual(f.errors, [ERRORS[name]]); assert.equal(f.capture.busy, false);
  });
}

test("backend error releases state and allows another recording", async () => {
  const f = fixture({ transcribe: async () => ({ ok: false, code: "stt_no_speech" }) });
  for (let n = 0; n < 2; n++) {
    await f.capture.begin(); f.advance(1000); f.capture.finish(true); await flush();
    assert.equal(f.capture.busy, false);
  }
  assert.equal(f.errors.length, 2); assert.equal(f.stopped, 2);
});

test("recorder failure closes tracks and cannot submit partial audio", async () => {
  const f = fixture(); await f.capture.begin(); f.advance(1000);
  f.recordings[0].dispatchEvent(new Event("error")); await flush();
  assert.equal(f.calls, 0); assert.equal(f.capture.busy, false); assert.ok(f.stopped > 0);
});

test("dictation appends to the existing draft without replacing it", () => {
  assert.equal(appendTranscript("draft", " hello "), "draft hello");
  assert.equal(appendTranscript("draft\n", "hello"), "draft\nhello");
  assert.equal(appendTranscript("", "hello"), "hello");
  assert.equal(appendTranscript("draft", " "), "draft");
});

const bridgeOptions = (fetchImpl) => ({ startBackend: async () => {}, origin: "http://127.0.0.1:8765", token: () => "secret", fetchImpl });
test("IPC bridge sends binary only to authenticated loopback, without retry or base64", async () => {
  const audio = new Uint8Array([1, 2, 3]); let body;
  const result = await transcribeComposerSpeech({ audio, mimeType: "audio/webm;codecs=opus", language: "zh-CN" }, bridgeOptions(async (url, options) => {
    assert.equal(url, "http://127.0.0.1:8765/api/stt/transcribe");
    assert.equal(options.headers["X-GalaxySSI-Token"], "secret");
    assert.equal(options.headers["Content-Type"], "audio/webm");
    body = options.body; assert.deepEqual([...body], [1, 2, 3]);
    return { ok: true, json: async () => ({ text: "hello" }) };
  }));
  assert.equal(result.text, "hello"); assert.ok(body.every((n) => n === 0)); assert.ok(audio.every((n) => n === 0));
});

for (const audio of [undefined, [], new Uint8Array(), new Uint8Array(MAX_AUDIO_BYTES + 1)]) {
  test(`IPC rejects invalid audio ${audio?.length}`, async () => {
    const result = await transcribeComposerSpeech({ audio }, bridgeOptions(() => assert.fail("must not fetch")));
    assert.equal(result.code, "stt_invalid_audio");
  });
}

test("IPC failure has a stable code and does not retry recorded speech", async () => {
  let calls = 0;
  const result = await transcribeComposerSpeech({ audio: new Uint8Array([1]), mimeType: "audio/webm" }, bridgeOptions(async () => {
    calls++; throw { name: "TimeoutError" };
  }));
  assert.equal(result.code, "stt_timeout"); assert.equal(calls, 1);
});
