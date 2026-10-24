# Local-first headline translation

GalaxySSI uses Google Translate through ML Kit's on-device translation API for
missing English news headlines. Existing translations produced while preparing
news, and previously validated cached translations, remain unchanged.

## Execution

- Process at most eight missing public feed headlines per batch, on the worker's
  IO dispatcher. No private inbox content enters this path.
- Use the English-to-Chinese on-device model before discovering agents or
  acquiring cloud/local-LLM inference permits. An installed language model works
  without network access or a configured chat model.
- If the language model is missing, enqueue one Wi-Fi download job with
  exponential retry backoff. Do not wait for the download before model fallback.
- Validate the translated text using the existing title, markup and numeric
  checks. Cache accepted results and their provider in the existing title store,
  preserving its current public-news storage policy.
  Only remaining titles enter the existing configured-model fallback path.
- Bound local attempts to 12 seconds per batch and 3 seconds per headline.
  Cancellation propagates, and the translator closes at the end of each batch.
- Preserve the existing thermal/power deferral and background spacing policy.
  Local-first does not mean running discretionary work while the device is hot.
- Model downloads contain no news text. Fallback may send public headlines to a
  configured cloud model or paired Desktop agent, as before.

## Attribution and quality

ML Kit results display the official Google Translate attribution badge. Its
notice explains that automatic translations have no guarantees of accuracy,
reliability, merchantability, fitness for a particular purpose or non-infringement.
The original English headline remains visible. Numeric validation is not a
semantic accuracy guarantee; proper names, technical terms and ambiguous
headlines still require evaluation.

- [ML Kit translation](https://developers.google.com/ml-kit/language/translation)
- [Google Cloud Translation](https://cloud.google.com/translate)
- [Usage guidelines](https://developers.google.com/ml-kit/language/translation/translation-terms)
- [Attribution requirements](https://cloud.google.com/translate/attribution)

`google_translate_attribution.png` uses the unmodified greyscale and white 3x
regular badges for light and dark themes from Google's official attribution
archive, not a GalaxySSI-created logo:
https://docs.cloud.google.com/static/translate/images/google-translate-attribution.zip
