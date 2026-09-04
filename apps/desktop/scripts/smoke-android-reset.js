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

function log(message) {
  console.log(`[android-reset-smoke] ${message}`);
}

function fail(message) {
  throw new Error(message);
}

const adb = createAdb(root, log);

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
  if (process.env.GALAXYSSI_ALLOW_DESTRUCTIVE_RESET !== "1") {
    fail("Destructive reset smoke is disabled. Run only on a disposable test device with GALAXYSSI_ALLOW_DESTRUCTIVE_RESET=1.");
  }
  if (!fs.existsSync(apkPath)) {
    fail(`Android debug APK missing. Build it first: ${apkPath}`);
  }

  log("installing debug APK");
  adb(["install", "-r", apkPath], { stdio: "inherit" });
  adb(["shell", "input", "keyevent", "KEYCODE_WAKEUP"]);
  adb(["shell", "am", "force-stop", packageName]);
  adb(["shell", "am", "start", "-n", activityName]);
  await sleep(2500);

  log("seeding contacts before destructive reset");
  adb([
    "shell",
    "am",
    "start",
    "-n",
    activityName,
    "--ez",
    "galaxyssi_debug_pairing",
    "true",
    "--ez",
    "galaxyssi_debug_status",
    "true"
  ]);
  await sleep(2500);
  const beforeReset = await snapshotSecureState({ adb, packageName, activityName });
  const beforeContacts = Array.isArray(beforeReset.contacts) ? beforeReset.contacts : [];
  if (!beforeContacts.some((contact) => contact.type === "pc_connector") ||
      !beforeContacts.some((contact) => contact.name === "Codex Agent")) {
    fail("Debug setup did not create connector contacts before reset");
  }

  log("executing debug destructive reset");
  adb(["shell", "am", "start", "-n", activityName, "--ez", "galaxyssi_debug_destroy_all_data", "true"]);
  await sleep(3000);

  const afterReset = await snapshotSecureState({ adb, packageName, activityName });
  const welcomeHistory = await probeChatHistory({
    adb,
    packageName,
    activityName,
    contactId: "system",
    contentToken: "GalaxySSI"
  });

  if (!afterReset.local_identity_sha256 ||
      afterReset.local_identity_sha256 === beforeReset.local_identity_sha256) {
    fail("Destructive reset did not rotate the local Signal identity store");
  }
  if ((afterReset.contacts || []).length !== 0) {
    fail("Destructive reset left connector contacts in the app store");
  }
  if ((afterReset.friend_requests || []).length !== 0) {
    fail("Destructive reset did not leave an empty New Friends list");
  }
  if (afterReset.trust?.pc_verified) {
    fail("Destructive reset left trusted PC fingerprints");
  }
  requireProbeMatch(welcomeHistory, "fresh-install welcome history");

  log("destructive reset rotated identity, cleared contacts/trust, and recreated welcome notification");
  adb(["shell", "am", "force-stop", packageName]);
}

main().catch((error) => {
  console.error(`[android-reset-smoke] failed: ${error.stack || error.message || error}`);
  process.exit(1);
});
