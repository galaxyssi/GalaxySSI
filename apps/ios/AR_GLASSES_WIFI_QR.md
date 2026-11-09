# Wi-Fi QR for offline AR glasses

The iPhone can display the glasses' `galaxyssi_wifi_v1` code under
My Agent, Connected devices, Glasses Wi-Fi QR. Enter the exact WPA2 network
name and passphrase. The glasses scan the code, display the network name,
and require their own network confirmation. This does not change the
iPhone's Wi-Fi or require the glasses to be online first.

The QR contains the password and can be read by a camera. The phone keeps
it out of persistent storage and clears it on exit, backgrounding, screen
recording or mirroring detection, screenshot notification, or after
one minute. iOS screenshot notifications arrive after capture and cannot
prevent a screenshot; show the code only to the intended device.

SSID entry is manual because iOS has
[no general-purpose Wi-Fi scanning API](https://developer.apple.com/documentation/technotes/tn3111-ios-wifi-api-overview).
No location entitlement or network-scanning permission is requested.
