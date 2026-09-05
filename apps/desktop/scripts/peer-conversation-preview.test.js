const assert = require("node:assert/strict");
const test = require("node:test");

const { attachmentKind, messagePreview, hasClientRoute } = require("../src/peer_conversation_preview");

const labels = {
  voice: "Voice",
  image: "Image",
  file: "File",
  fallback: "Paired device"
};

test("shows message text when the latest peer message has no attachment", () => {
  assert.equal(messagePreview({ content: "Hello from Galaxy" }, labels), "Hello from Galaxy");
});

test("hides generated voice attachment names behind a voice label", () => {
  assert.equal(
    messagePreview({ attachments: [{ name: "voice-178793028213-6bc6.opus" }] }, labels),
    "Voice"
  );
  assert.equal(attachmentKind({ name: "recording.bin", mime_type: "audio/ogg" }), "voice");
});

test("shows image and file labels instead of attachment names", () => {
  assert.equal(messagePreview({ attachments: [{ name: "holiday.JPG" }] }, labels), "Image");
  assert.equal(messagePreview({ attachments: [{ name: "report.pdf" }] }, labels), "File");
  assert.equal(
    messagePreview({ attachments: [{ name: "photo.png" }, { name: "notes.txt" }] }, labels),
    "File"
  );
});

test("uses localized labels supplied by the renderer", () => {
  assert.equal(
    messagePreview({ attachments: [{ name: "voice-local.opus" }] }, { ...labels, voice: "语音" }),
    "语音"
  );
});

test("detects whether an incoming message route is already in the paired client directory", () => {
  const clients = [
    { client_route_id: "old-route" },
    { client_route_id: "new-route" }
  ];
  assert.equal(hasClientRoute(clients, "new-route"), true);
  assert.equal(hasClientRoute(clients, "missing-route"), false);
  assert.equal(hasClientRoute([], "new-route"), false);
});
