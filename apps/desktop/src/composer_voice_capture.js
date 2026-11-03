(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.galaxyssiComposerVoice = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  const ERRORS = {
    NotAllowedError: "Microphone permission was denied. Check system microphone privacy settings.",
    NotFoundError: "No microphone was found. Connect a microphone and try again.",
    NotReadableError: "The microphone is busy or unavailable.",
    stt_audio_too_short: "Recording is too short. Hold the microphone button while speaking.",
    stt_no_speech: "No speech was detected. Please try again.",
    stt_busy: "Speech recognition is still running. Please wait.",
    stt_runtime_missing: "Local speech recognition is missing. Install the Desktop backend dependencies.",
    stt_model_unavailable: "Could not prepare the local speech model. Check the model download connection and retry.",
    stt_timeout: "Local speech recognition timed out. The model may still be preparing.",
    stt_backend_unavailable: "The local speech service is unavailable. Please try again.",
    stt_invalid_audio: "The recording could not be decoded. Please record again.",
    stt_audio_too_long: "The recording exceeds two minutes. Please use a shorter recording.",
    stt_audio_too_large: "The recording is too large. Please use a shorter recording.",
    stt_transcription_failed: "Local speech recognition failed. Please try again."
  };

  function appendTranscript(draft, transcript) {
    const text = String(transcript || "").trim();
    return text ? `${draft}${draft && !/\s$/.test(draft) ? " " : ""}${text}` : draft;
  }

  function createCapture(options) {
    const { getUserMedia, Recorder, transcribe, context, onText, onState, onError } = options;
    const now = options.now || Date.now;
    const setTimer = options.setTimer || setInterval;
    const clearTimer = options.clearTimer || clearInterval;
    let current = null;
    let generation = 0;

    function emit(session, phase) {
      if (current === session) onState({ phase, cancelPending: session.cancelPending, elapsed: now() - (session.started || now()) });
    }
    function stopTracks(session) {
      session.stream?.getTracks().forEach((track) => track.stop());
      session.stream = null;
    }
    function idle(session) {
      if (current !== session) return;
      clearTimer(session.timer);
      current = null;
      onState({ phase: "idle", elapsed: 0, cancelPending: false });
    }
    function report(error) {
      onError(ERRORS[error.code || error.name] || ERRORS.stt_transcription_failed);
    }
    async function complete(session) {
      stopTracks(session);
      clearTimer(session.timer);
      let audio;
      try {
        if (session.cancelled || current !== session || context() !== session.context) return;
        if (now() - session.started < 300 || !session.chunks.length) {
          report({ code: "stt_audio_too_short" });
          return;
        }
        emit(session, "transcribing");
        const blob = new Blob(session.chunks, { type: session.recorder.mimeType || "audio/webm" });
        session.chunks = [];
        audio = new Uint8Array(await blob.arrayBuffer());
        if (current !== session) return;
        const result = await transcribe({ audio, mimeType: blob.type, language: options.language() });
        if (current !== session || generation !== session.generation || context() !== session.context) return;
        if (!result.ok) report(result);
        else if (!result.text?.trim()) report({ code: "stt_no_speech" });
        else onText(result.text);
      } catch (error) {
        if (current === session) report(error);
      } finally {
        audio?.fill(0);
        session.chunks = [];
        idle(session);
      }
    }
    async function begin(pointerId = null, startY = null) {
      if (current) return;
      const session = {
        pointerId, startY, context: context(), generation: ++generation,
        holding: true, cancelled: false, cancelPending: false, chunks: [], timer: null
      };
      current = session;
      emit(session, "starting");
      try {
        session.stream = await getUserMedia({ audio: {
          channelCount: 1, noiseSuppression: true, echoCancellation: true, autoGainControl: false
        } });
        if (current !== session || !session.holding || context() !== session.context) {
          stopTracks(session);
          idle(session);
          return;
        }
        const mimeType = ["audio/webm;codecs=opus", "audio/ogg;codecs=opus", "audio/webm"]
          .find((value) => Recorder.isTypeSupported(value));
        const recorder = new Recorder(session.stream, { ...(mimeType ? { mimeType } : {}), audioBitsPerSecond: 48_000 });
        session.recorder = recorder;
        recorder.addEventListener("dataavailable", (event) => {
          if (!session.cancelled && event.data?.size) session.chunks.push(event.data);
        });
        recorder.addEventListener("stop", () => complete(session), { once: true });
        recorder.addEventListener("error", () => {
          if (current === session) { cancel(); report({ name: "NotReadableError" }); }
        }, { once: true });
        session.started = now();
        recorder.start(250);
        emit(session, "recording");
        session.timer = setTimer(() => {
          if (context() !== session.context) { cancel(); return; }
          emit(session, "recording");
          if (now() - session.started >= 119_000) finish(true);
        }, 200);
      } catch (error) {
        stopTracks(session);
        if (current === session) { report(error); idle(session); }
      }
    }
    function move(pointerId, y) {
      const session = current;
      if (!session?.holding || session.pointerId !== pointerId) return;
      session.cancelPending = Number.isFinite(session.startY) && session.startY - y >= 64;
      emit(session, session.recorder ? "recording" : "starting");
    }
    function finish(accept, pointerId) {
      const session = current;
      if (!session?.holding || (pointerId !== undefined && pointerId !== session.pointerId)) return;
      session.holding = false;
      session.cancelled = !accept || session.cancelPending;
      clearTimer(session.timer);
      if (session.recorder?.state === "recording") session.recorder.stop();
      else { stopTracks(session); idle(session); }
    }
    function cancel() {
      const session = current;
      if (!session) return;
      session.cancelled = true;
      session.holding = false;
      generation += 1;
      if (session.recorder?.state === "recording") session.recorder.stop();
      stopTracks(session);
      session.chunks = [];
      idle(session);
    }
    return { begin, move, finish, cancel, get busy() { return current !== null; } };
  }
  return { createCapture, appendTranscript, ERRORS };
});
