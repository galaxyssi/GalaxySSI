const crypto = require("node:crypto");

const debugPreferencesPath = "shared_prefs/galaxyssi_debug.xml";

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function readAppFile(adb, packageName, file) {
  try {
    return adb(["shell", "run-as", packageName, "cat", file]);
  } catch {
    return "";
  }
}

function decodeXml(value) {
  return String(value)
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&");
}

function preferenceString(xml, name) {
  const pattern = new RegExp(`<string name="${name}">([\\s\\S]*?)<\\/string>`);
  const match = String(xml).match(pattern);
  return match ? decodeXml(match[1]) : "";
}

async function requestSecureState({
  adb,
  packageName,
  activityName,
  action = "snapshot",
  state,
  contactId,
  patch,
  expectedPcFingerprint,
  timeoutMs = 30_000
}) {
  const requestId = crypto.randomUUID();
  const request = {
    request_id: requestId,
    action
  };
  if (state) request.state = state;
  if (contactId) request.contact_id = contactId;
  if (patch) request.patch = patch;
  if (expectedPcFingerprint) request.expected_pc_fingerprint = expectedPcFingerprint;
  const payload = Buffer.from(JSON.stringify(request), "utf8").toString("base64");
  adb([
    "shell",
    "am",
    "start",
    "-n",
    activityName,
    "--es",
    "galaxyssi_debug_secure_state_probe_b64",
    payload
  ]);

  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await sleep(200);
    const xml = readAppFile(adb, packageName, debugPreferencesPath);
    const raw = preferenceString(xml, "secure_state_probe_result");
    if (!raw) continue;
    const result = JSON.parse(raw);
    if (result.request_id !== requestId) continue;
    if (!result.ok || result.error) {
      throw new Error(`Android secure state probe failed: ${result.error || "unknown error"}`);
    }
    if (result.storage !== "android-keystore-aes-gcm") {
      throw new Error(`Android secure state probe used unexpected storage: ${result.storage || "unknown"}`);
    }
    return result;
  }
  throw new Error(`Android secure state probe timed out for ${action}`);
}

async function snapshotSecureState(options) {
  const result = await requestSecureState({ ...options, action: "snapshot" });
  return result.state || {};
}

async function replaceSecureAppStore(options, state) {
  const result = await requestSecureState({
    ...options,
    action: "replace_app_store",
    state
  });
  return result.state || {};
}

async function patchSecureContact(options, contactId, patch) {
  const result = await requestSecureState({
    ...options,
    action: "patch_contact",
    contactId,
    patch
  });
  return result.state || {};
}

module.exports = {
  patchSecureContact,
  replaceSecureAppStore,
  requestSecureState,
  snapshotSecureState
};
