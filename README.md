# GalaxySSI

GalaxySSI is a private superintelligence interface that turns phones, computers, agents, models, and devices into a trusted AI mesh.

Current release: **v1.0.0**

The project combines a mobile-first command surface, Signal-style trusted pairing, encrypted agent messaging, voice interaction, and a desktop connector that makes local tools, cloud models, and autonomous agents reachable as secure contacts.

On-device agents can develop and verify projects within isolated local Linux workspaces.

## Repository Layout

```text
apps/android      Native Android app
apps/ios          Native iOS app
apps/desktop      Electron desktop app for Windows, macOS, and Linux
apps/watch        Native Wear OS companion app
apps/ar-glasses   Native Android app for AR glasses
docs              Product, protocol, architecture, security, setup, and design docs
assets            Logos, icons, screenshots, and marketing media
tools             Development, diagnostics, release, and migration tools
tests             Cross-platform fixtures and end-to-end tests
```

## Current Apps

- Android app: `apps/android`
- iOS app: `apps/ios` (native app for iOS 15+)
- Desktop connector: `apps/desktop`
- Wear OS watch app: `apps/watch`
- AR glasses app: `apps/ar-glasses`
- GalaxySSI Link core: `apps/desktop/core/galaxyssi-link`

## Watch and AR Glasses

- **Watch:** The native [GalaxySSI Watch](apps/watch/README.md) app runs on Wear OS with Android 13+ (API 33+). It supports conversations with paired Desktop assistants or configured cloud models, speech input, spoken replies, task status, and encrypted messaging. Watch-specific setup and current limitations are documented in its README.
- **AR glasses:** The native [GalaxySSI AR glasses](apps/ar-glasses/README.md) app supports on-glasses wake-word input, spoken and on-screen replies, and cloud-model configuration from the phone.

## Development

Repository checks:

```bash
npm run check
```

Android:

```bash
npm run check:android
npm run smoke:android:ui
npm run smoke:android:friends
npm run smoke:android:contact-rename
npm run smoke:android:contact-tags
npm run smoke:android:language
npm run smoke:android:cloud-models
npm run smoke:android:background
npm run smoke:android:agent-replies
npm run smoke:android:backup
npm run smoke:android:voice-reply
npm run smoke:android:voice-settings
npm run smoke:android:reset
```

Desktop:

```bash
cd apps/desktop
npm install
npm run check
npm run smoke
```

Desktop smoke gates from the repository root:

```bash
npm run smoke:desktop
npm run smoke:desktop:voice-stt
npm run smoke:desktop:e2e
```

Run smoke commands sequentially; they share the local backend port and test lock.

Full test coverage is documented in `docs/testing/README.md`.

Product requirements are documented in `docs/product/PRODUCT_REQUIREMENTS.md`.

The phone-owned Super Agent architecture is specified in
`docs/product/MOBILE_NATIVE_SUPER_AGENT_IMPLEMENTATION.md`, with its bounded tool-session contract in
`docs/protocol/Phone-Native-Tool-Session-v1.md`.

Local release gates:

```bash
npm run test:release:local
npm run test:release:device
```

Windows desktop package:

```bash
npm run package:desktop:win
npm run smoke:desktop:packaged
```

The Windows package workflow runs the same package and packaged-smoke gates on Desktop packaging changes.

Release audit:

```bash
npm run audit:release
npm run audit:release:strict
```
