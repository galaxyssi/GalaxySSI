# AR speech proxy

This optional Cloudflare Worker transcribes audio from the glasses with the multilingual `@cf/openai/whisper-large-v3-turbo` Workers AI model. The Worker uses an AI binding; no Cloudflare account credential is sent to the glasses. A separate random device token authorizes uploads. Audio is processed in memory and this Worker does not store it.

Cloudflare currently includes a daily free Workers AI allocation; usage above the allocation requires a paid plan. Check [Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/) before deployment. The model and its input format are documented in [Cloudflare's Whisper large v3 turbo guide](https://developers.cloudflare.com/workers-ai/guides/tutorials/build-a-workers-ai-whisper-with-chunking/).

To deploy in your own Cloudflare account, install Node.js, authenticate Wrangler, generate a random device token of at least 32 characters, then run from this directory:

```sh
npx wrangler secret put DEVICE_TOKEN
npx wrangler deploy
```

Enter the same token and the deployed HTTPS URL in the GalaxySSI phone app's AR speech configuration, then sync it to the glasses through the existing verified pairing flow. Treat the device token as a credential and rotate it if a glasses device is lost. The endpoint accepts only `POST /transcribe`, with a canonical 16 kHz mono PCM16 WAV body up to 700 kB, and responds with `{"text":"..."}`. `GET /health` reports whether the Worker is reachable.

Run `npm test` for the proxy contract tests. No Cloudflare account or live AI binding is needed for those tests.
