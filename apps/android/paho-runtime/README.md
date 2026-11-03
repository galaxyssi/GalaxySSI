# Paho worker startup correction

This module packages Eclipse Paho MQTT Java **1.2.5**, with three source classes
from the upstream `v1.2.5` tag: `CommsCallback`, `CommsSender`, and `CommsReceiver`.
Original copyright and EPL-2.0 / EDL-1.0 notices are retained. All other classes,
resources and bundled notices come from the unmodified Maven artifact.

Source: https://github.com/eclipse-paho/paho.mqtt.java/tree/v1.2.5/org.eclipse.paho.client.mqttv3/src/main/java/org/eclipse/paho/client/mqttv3/internal

The only source change is the wait at the end of `start()`: stop waiting when
the worker target becomes `STOPPED`, and respect interruption. In 1.2.5 a worker
can enter RUNNING and exit before the polling caller observes it. The caller
then sleeps forever waiting for a state that will never recur. A real S26 Ultra
sample contained roughly 300 MQTT threads, including old `MQTT Con` stacks in
`CommsCallback.start` and `CommsSender.start`.

No MQTT retry, socket timeout, cipher, certificate verification, protocol,
subscription, or delivery settings are changed. The app must depend on this
module, not also on the upstream artifact: the output JAR contains exactly one
copy of every runtime class. The Java tests deterministically exercise the
start/stop race without a public broker.

Android consumes the explicit `packagedRuntime` configuration. Do not use the
default project dependency: Android can select the classes-directory variant,
which omits the unchanged classes merged by the JAR task. The device lifecycle
test constructs the real client from the installed APK and exercises failed
TCP connections. Upstream JAR signatures are excluded because the binary is
modified; license notices remain intact.

When upgrading Paho, compare these classes with upstream and remove this module
once the upstream lifecycle code provides equivalent behavior.
