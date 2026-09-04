const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const { findBackendPython } = require("./python-runtime");
const { withGalaxySSILock } = require("./smoke-lock");

const root = path.resolve(__dirname, "..");
const workspaceRoot = path.resolve(root, "..");
const androidMqttClient = path.join(
  workspaceRoot,
  "android",
  "app",
  "src",
  "main",
  "java",
  "com",
  "galaxyssi",
  "chat",
  "GalaxySSIMqttClient.kt"
);
const desktopMqttBridge = path.join(
  root,
  "core",
  "galaxyssi-link",
  "backend",
  "mqtt_bridge.py"
);

function log(message) {
  console.log(`[mqtt-persistence] ${message}`);
}

function fail(message) {
  throw new Error(message);
}

function assertAndroidPersistentSessionConfig() {
  const source = fs.readFileSync(androidMqttClient, "utf8");
  const required = [
    "isCleanSession = true",
    "isAutomaticReconnect = true",
    "private const val MQTT_QOS = 1",
    "GalaxySSILinkDeliveryStore.enqueue(",
    "retryPendingMessages()",
    "MAX_ATTACHMENT_OUTBOX_DELIVERY_ATTEMPTS"
  ];
  for (const marker of required) {
    if (!source.includes(marker)) {
      fail(`Android MQTT persistence config is missing: ${marker}`);
    }
  }
}

function assertDesktopCleanSessionConfig() {
  const source = fs.readFileSync(desktopMqttBridge, "utf8");
  const required = [
    "_persistent_mqtt_client_id()",
    "clean_session=True",
    "MQTT_SUBSCRIPTION_ACK_TIMEOUT_SECONDS",
    "_request_transport_reconnect(mqttc, \"subscription_ack_timeout\")",
    "_subscribe_topics(mqttc, requested_subscriptions)",
    "status[\"ready\"]"
  ];
  for (const marker of required) {
    if (!source.includes(marker)) {
      fail(`Desktop MQTT clean-session recovery config is missing: ${marker}`);
    }
  }
}

function runBrokerCleanSessionProbe() {
  const code = String.raw`
import sys
import hashlib
import threading
import time
import uuid
import warnings

import paho.mqtt.client as mqtt

warnings.filterwarnings("ignore", category=DeprecationWarning)

BROKER = "broker.emqx.io"
PORT = 8883
CLIENT_ID = uuid.uuid4().hex[:22]
TOPIC = hashlib.sha256((CLIENT_ID + uuid.uuid4().hex).encode()).hexdigest()
OFFLINE_PAYLOAD = "offline-qos1-" + uuid.uuid4().hex
ONLINE_PAYLOAD = "online-qos1-" + uuid.uuid4().hex

subscribed = threading.Event()
received = []
message_event = threading.Event()

def make_client(client_id, clean_session=False):
    try:
        client = mqtt.Client(client_id=client_id, clean_session=clean_session, protocol=mqtt.MQTTv311)
    except TypeError:
        client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, client_id=client_id, clean_session=clean_session, protocol=mqtt.MQTTv311)
    client.tls_set()
    client.tls_insecure_set(False)
    return client

def on_connect(client, userdata, flags, rc, *extra):
    if rc != 0:
        print("connect_rc=" + str(rc), file=sys.stderr)
        return
    client.subscribe(TOPIC, qos=1)

def on_subscribe(client, userdata, mid, granted_qos, *extra):
    subscribed.set()

def on_message(client, userdata, message):
    text = message.payload.decode("utf-8", "replace")
    received.append(text)
    if text == ONLINE_PAYLOAD:
        message_event.set()

subscriber = make_client(CLIENT_ID, clean_session=True)
subscriber.on_connect = on_connect
subscriber.on_subscribe = on_subscribe
subscriber.connect(BROKER, PORT, 30)
subscriber.loop_start()
if not subscribed.wait(12):
    subscriber.loop_stop()
    subscriber.disconnect()
    raise SystemExit("initial_subscribe_timeout")
subscriber.disconnect()
subscriber.loop_stop()

publisher = make_client(CLIENT_ID + "-publisher", clean_session=True)
publisher.connect(BROKER, PORT, 30)
publisher.loop_start()
info = publisher.publish(TOPIC, OFFLINE_PAYLOAD, qos=1, retain=False)
info.wait_for_publish(timeout=12)

subscribed.clear()
subscriber = make_client(CLIENT_ID, clean_session=True)
subscriber.on_connect = on_connect
subscriber.on_subscribe = on_subscribe
subscriber.on_message = on_message
subscriber.connect(BROKER, PORT, 30)
subscriber.loop_start()
if not subscribed.wait(12):
    subscriber.loop_stop()
    subscriber.disconnect()
    raise SystemExit("reconnect_subscribe_timeout")
time.sleep(1)
if OFFLINE_PAYLOAD in received:
    raise SystemExit("clean_session_replayed_offline_payload")
info = publisher.publish(TOPIC, ONLINE_PAYLOAD, qos=1, retain=False)
info.wait_for_publish(timeout=12)
ok = message_event.wait(15)
subscriber.disconnect()
subscriber.loop_stop()
publisher.disconnect()
publisher.loop_stop()

if not ok:
    raise SystemExit("online_message_not_delivered_after_clean_reconnect")

print("clean_session_recovery_ok topic=" + TOPIC)
`;

  execFileSync(findBackendPython(), ["-c", code], {
    cwd: root,
    stdio: "inherit",
    windowsHide: true
  });
}

async function main() {
  log("checking Android durable outbox settings");
  assertAndroidPersistentSessionConfig();
  log("checking Desktop clean MQTT session recovery settings");
  assertDesktopCleanSessionConfig();
  log("probing clean-session reconnect and live QoS1 delivery");
  runBrokerCleanSessionProbe();
  log("MQTT durable delivery and clean-session recovery smoke OK");
}

withGalaxySSILock("smoke:mqtt-persistence", main).catch((error) => {
  console.error(`[mqtt-persistence] failed: ${error.stack || error.message || error}`);
  process.exit(1);
});
