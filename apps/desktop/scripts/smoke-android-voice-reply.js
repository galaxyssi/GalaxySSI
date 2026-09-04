const fs = require("node:fs");
const path = require("node:path");
const { createAdb } = require("./android-adb");
const { probeChatHistory, requireProbeMatch } = require("./android-chat-history-probe");
const { snapshotSecureState } = require("./android-secure-state-probe");

const root = path.resolve(__dirname, "..");
const workspaceRoot = path.resolve(root, "..");
const androidDir = path.join(workspaceRoot, "android");
const apkPath = path.join(androidDir, "app", "build", "outputs", "apk", "debug", "app-debug.apk");
const packageName = "com.galaxyssi.chat";
const activityName = `${packageName}/.MainActivity`;
const outDir = path.join(root, "ui-smoke");
const voiceDump = path.join(outDir, "android-voice-reply.xml");
const chatDump = path.join(outDir, "android-voice-reply-chat.xml");
const historyDump = path.join(outDir, "android-voice-reply-history.json");
const appStorePrefs = "shared_prefs/galaxyssi_app_store.xml";
const trustPrefs = "shared_prefs/galaxyssi_signal_trust.xml";

function log(message) {
  console.log(`[android-voice-reply-smoke] ${message}`);
}

function fail(message) {
  throw new Error(message);
}

const adb = createAdb(root, log);

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function readAppFile(file) {
  try {
    return adb(["shell", "run-as", packageName, "cat", file]);
  } catch {
    return "";
  }
}

function restoreAppFile(file, snapshot) {
  if (!snapshot) {
    adb(["shell", "run-as", packageName, "rm", "-f", file]);
    return;
  }
  adb(["shell", "run-as", packageName, "mkdir", "-p", "shared_prefs"]);
  adb(["shell", "run-as", packageName, "tee", file], { input: snapshot, stdio: ["pipe", "ignore", "pipe"] });
}

async function resolveHermesContactId() {
  const state = await snapshotSecureState({ adb, packageName, activityName });
  const contacts = Array.isArray(state.contacts) ? state.contacts : [];
  const target = contacts.find((contact) =>
    contact.deleted !== true &&
    contact.trust_state !== "deleted" &&
    (
      contact.agent_id === "hermes" ||
      contact.id === "hermes" ||
      String(contact.id || "").endsWith(":hermes") ||
      String(contact.galaxyssi_id || "").endsWith(":hermes")
    )
  );
  return String(target?.id || target?.galaxyssi_id || "hermes");
}

function dumpWindow(remoteName, targetPath) {
  adb(["shell", "uiautomator", "dump", `/sdcard/${remoteName}`]);
  adb(["pull", `/sdcard/${remoteName}`, targetPath]);
  return fs.readFileSync(targetPath, "utf8");
}

async function waitForWindowText(targetPath, remoteName, requiredText, attempts = 10) {
  let xml = "";
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    await sleep(700);
    xml = dumpWindow(remoteName, targetPath);
    if (xml.includes(requiredText)) return xml;
  }
  return xml;
}

async function main() {
  if (!fs.existsSync(apkPath)) {
    fail(`Android debug APK missing. Build it first: ${apkPath}`);
  }
  fs.mkdirSync(outDir, { recursive: true });

  const token = `VOICE_REPLY_TAIL_${Date.now()}`;
  const longReply = [
    "GalaxySSI voice reply smoke.",
    "This message intentionally spans many words so the voice response panel must preserve the complete assistant answer.",
    "Segment alpha confirms the beginning.",
    "Segment beta confirms the middle.",
    "Segment gamma confirms the lower panel can scroll without truncating the reply.",
    "Segment delta confirms chat history stores the same text.",
    token
  ].join(" ");
  log("installing debug APK");
  adb(["install", "-r", apkPath], { stdio: "inherit" });
  adb(["shell", "pm", "grant", packageName, "android.permission.RECORD_AUDIO"]);
  adb(["shell", "input", "keyevent", "KEYCODE_WAKEUP"]);
  adb(["shell", "am", "force-stop", packageName]);

  const originalAppStore = readAppFile(appStorePrefs);
  const originalTrust = readAppFile(trustPrefs);

  try {
    log("opening voice page with debug pairing");
    adb([
      "shell", "am", "start", "-n", activityName,
      "--ez", "galaxyssi_debug_pairing", "true",
      "--ez", "galaxyssi_debug_open_voice", "true"
    ]);
    const readyXml = await waitForWindowText(
      voiceDump,
      "galaxyssi-voice-reply.xml",
      "com.galaxyssi.chat:id/wakePage",
      12
    );
    if (!readyXml.includes("com.galaxyssi.chat:id/wakePage")) {
      fail(`Voice page did not open before reply injection. Dump saved at ${voiceDump}`);
    }
    const targetContactId = await resolveHermesContactId();
    const payloadB64 = Buffer.from(JSON.stringify({
      sender: targetContactId,
      contact_id: targetContactId,
      content: longReply,
      delivery_trace: [
        { stage: "desktop_reply_publish_queued", detail: "smoke" },
        { stage: "desktop_reply_broker_ack", detail: "smoke" }
      ]
    }), "utf8").toString("base64");

    log(`injecting a long Hermes reply for ${targetContactId} and verifying the voice reply panel keeps the tail`);
    adb([
      "shell", "am", "start", "-n", activityName,
      "--ez", "galaxyssi_debug_open_voice", "true",
      "--es", "galaxyssi_debug_incoming_b64", payloadB64
    ]);
    await sleep(1200);
    const voiceXml = await waitForWindowText(voiceDump, "galaxyssi-voice-reply.xml", token, 12);
    if (!voiceXml.includes(token)) {
      fail(`Voice reply panel did not show the complete reply tail ${token}. Dump saved at ${voiceDump}`);
    }

    log("opening Hermes chat and verifying the same reply is persisted");
    adb(["shell", "am", "start", "-n", activityName, "--es", "galaxyssi_debug_open_contact", targetContactId]);
    const chatXml = await waitForWindowText(chatDump, "galaxyssi-voice-reply-chat.xml", token, 12);
    const history = await probeChatHistory({
      adb,
      packageName,
      activityName,
      contactId: targetContactId,
      contentToken: token,
      requiredStages: [
        "desktop_reply_publish_queued",
        "desktop_reply_broker_ack",
        "received",
        "decrypted",
        "persisted"
      ]
    });
    fs.writeFileSync(historyDump, `${JSON.stringify(history, null, 2)}\n`);
    if (!chatXml.includes(token)) {
      fail(`Hermes chat did not show the complete reply tail ${token}. Dumps saved at ${chatDump} and ${historyDump}`);
    }
    requireProbeMatch(history, "voice reply history");

    log(`OK: voice reply panel and Hermes chat preserve full replies. Dumps: ${voiceDump}, ${chatDump}`);
  } finally {
    const targetContactId = await resolveHermesContactId();
    try {
      await probeChatHistory({
        adb,
        packageName,
        activityName,
        contactId: targetContactId,
        contentToken: token,
        deleteMatches: true
      });
    } catch {
      // Preserve the original failure; smoke messages use unique tokens.
    }
    adb(["shell", "am", "force-stop", packageName]);
    log("restoring original app state");
    restoreAppFile(appStorePrefs, originalAppStore);
    restoreAppFile(trustPrefs, originalTrust);
    adb(["shell", "am", "force-stop", packageName]);
  }
}

main().catch((error) => {
  console.error(`[android-voice-reply-smoke] failed: ${error.stack || error.message || error}`);
  process.exit(1);
});
