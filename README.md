# SpeakFlow (macOS)

`SpeakFlow` is a local macOS menu bar dictation app:

1. global hotkey dictation from any app
2. native microphone capture
3. floating dictation widget you can click or drag
4. ElevenLabs realtime speech recognition with English + Russian support
5. optional LLM cleanup pass for punctuation and readability
6. Accessibility text insertion first, paste fallback second

## Preview

Idle widget:

![SpeakFlow idle widget](docs/images/widget-idle.png)

Active dictation state:

![SpeakFlow active widget](docs/images/widget-active.png)


## What this build does

Current flow:

1. hold `Right Control`
2. speak
3. release `Right Control`
4. SpeakFlow streams audio to ElevenLabs realtime STT
5. it optionally runs a cleanup LLM pass
6. it inserts the final text into the focused app

The floating widget stays visible across Spaces, updates live between idle / listening / processing states, and can be dragged to a different screen position.

The keyboard trigger is hold-to-talk on `Right Control`. Recording starts when you press it and stops when you release it. If you hold `Right Control` and use it together with another key, SpeakFlow cancels that recording so normal shortcuts are less likely to trigger dictation by accident.

This build now uses ElevenLabs realtime speech-to-text by default and keeps OpenAI-compatible chat cleanup as an optional second step.

## Build

```bash
cd speakflow-macos
chmod +x build-speakflow-app.sh
./build-speakflow-app.sh
open SpeakFlow.app
```

## Architecture

The app is organized as a small native macOS codebase instead of a single monolithic file:

```text
Sources/
  App/          App lifecycle and orchestration
  Audio/        Microphone capture
  Core/         Shared constants, enums, and icon helpers
  Models/       Config and domain models
  Networking/   ElevenLabs + OpenAI clients
  Storage/      History and stats persistence
  UI/           Widget, menu, and control center window
```

`SpeakFlowApp` is the runtime coordinator. UI surfaces, persistence, transcription clients, and helpers live in dedicated source files so the app can keep growing without turning back into a single-file prototype.

## Config

On first launch, SpeakFlow creates and opens:

`~/Library/Application Support/SpeakFlow/config.json`

Default config:

```json
{
  "apiKey": "",
  "elevenLabsAPIKey": "",
  "baseURL": "https://api.openai.com/v1",
  "cleanupEnabled": true,
  "cleanupModel": "gpt-5.1",
  "cleanupPrompt": "You are cleaning dictated text after speech recognition.\nKeep the speaker's meaning and language choice intact.\nNever translate the text into another language.\nFix punctuation, casing, and obvious speech-to-text mistakes.\nRemove filler words only when they add no meaning.\nEnglish must stay English. Russian must stay Russian.\nMixed English and Russian should still read naturally.\nReturn plain text only with no commentary.",
  "customVocabulary": [
    "OpenAI",
    "macOS",
    "Dictation",
    "ChatGPT"
  ],
  "elevenLabsRealtimeModel": "scribe_v2_realtime",
  "preferAccessibilityInsertion": true,
  "providerName": "ElevenLabs realtime + OpenAI cleanup",
  "restoreClipboard": true,
  "transcriptionLanguageHint": "",
  "transcriptionModel": "scribe_v2",
  "transcriptionPrompt": "Transcribe the recording faithfully.\nDo not translate.\nIf the speaker talks in English, output English.\nIf the speaker talks in Russian, output Russian.\nOnly mix English and Russian when the speaker actually mixes them.\nPreserve names, product terms, and intended formatting.\nReturn plain text only."
}
```

Notes:

1. set `elevenLabsAPIKey` or use `ELEVENLABS_API_KEY` for speech recognition
2. leave `apiKey` empty if you prefer using `OPENAI_API_KEY` only for cleanup
3. add names, companies, and product terms to `customVocabulary` for better recognition
4. set `transcriptionLanguageHint` to `en` or `ru` if you want to force one language instead of auto-detection
5. disable `cleanupEnabled` if you want raw transcription only

## macOS permissions

SpeakFlow needs:

1. `Microphone` permission for recording
2. `Accessibility` permission for direct text insertion or `Cmd+V` fallback

The app prompts for both when needed. When Accessibility text insertion works, SpeakFlow edits the focused field directly. Otherwise it falls back to clipboard + paste. If Accessibility is still unavailable, your transcript remains in the clipboard.

For the most stable Accessibility trust, keep the app in a stable install location such as `/Applications/SpeakFlow.app` instead of launching a freshly rebuilt copy from a different path each time.

## Practical tuning

For the best English + Russian results:

1. keep the realtime model on `scribe_v2_realtime`
2. add your names, company terms, and slang to `customVocabulary`
3. set `transcriptionLanguageHint` to `en` when you only want English dictation
4. keep the cleanup prompt conservative so it fixes text without changing meaning
5. speak naturally; the prompt tells the models not to translate between English and Russian

## Rough pricing

These are rough estimates, not quotes. API and subscription prices change, and this app combines two different billing models:

1. ElevenLabs charges from a monthly credit pool on paid plans, but their API pricing page also publishes business-tier starting rates for STT, which are useful as a rough benchmark.
2. OpenAI cleanup is plain token billing, so that part is easier to estimate.

### Baseline comparison

1. `SpeakFlow` with ElevenLabs + OpenAI cleanup
   If you stay inside ElevenLabs `Starter`, the practical floor is about `$5/month` plus a very small OpenAI cleanup bill.
2. `SpeakFlow` with OpenAI transcription only
   `gpt-4o-transcribe` is listed at about `$0.006 / minute`, so `600 minutes / month` is about `$3.60` before any cleanup.
3. `Wispr Flow Pro`
   Public pricing is ` $15/user/month ` on the monthly plan, or ` $12/user/month ` billed annually.

### STT benchmark rates

Using official published API pricing as a benchmark:

1. ElevenLabs `Scribe v2` batch STT: about `$0.22 / hour`
2. ElevenLabs `Scribe v2 Realtime`: about `$0.39 / hour`
3. OpenAI `gpt-4o-transcribe`: about `$0.006 / minute` or about `$0.36 / hour`

### Cleanup estimate

For cleanup, the cost is usually small compared with speech recognition. As a rough rule of thumb:

1. `gpt-5.4-mini` is `$0.75 / 1M input tokens` and `$4.50 / 1M output tokens`
2. short dictation cleanup prompts usually land in the `pennies to low single-digit dollars per month` range unless usage is very heavy

### Example monthly scenarios

These are practical estimates, not exact bills:

1. Light use: `300 minutes/month`
   `OpenAI-only transcription` is about `$1.80`.
   `ElevenLabs Scribe v2 batch` is about `$1.10`.
   `ElevenLabs Scribe v2 Realtime` is about `$1.95`.
2. Medium use: `600 minutes/month`
   `OpenAI-only transcription` is about `$3.60`.
   `ElevenLabs Scribe v2 batch` is about `$2.20`.
   `ElevenLabs Scribe v2 Realtime` is about `$3.90`.
3. Heavy use: `1,500 minutes/month`
   `OpenAI-only transcription` is about `$9.00`.
   `ElevenLabs Scribe v2 batch` is about `$5.50`.
   `ElevenLabs Scribe v2 Realtime` is about `$9.75`.

Add OpenAI cleanup on top of those numbers. In most dictation-heavy setups, cleanup is still likely to stay much smaller than the transcription cost unless prompts or outputs become unusually large.

### What this means in practice

1. If you already want ElevenLabs for quality and low latency, `SpeakFlow` can be cheaper than a polished subscription app, but your true cost depends on which ElevenLabs tier you need.
2. If your main goal is the lowest raw operating cost, an OpenAI transcription-first setup can be very inexpensive.
3. Paid SaaS products like Wispr Flow include the finished app, support, hosted infrastructure, and ongoing product work, so the comparison is not fully apples-to-apples.

### Sources

1. [OpenAI API pricing](https://developers.openai.com/api/docs/pricing)
2. [OpenAI gpt-4o-transcribe model page](https://developers.openai.com/api/docs/models/gpt-4o-transcribe)
3. [ElevenLabs pricing](https://elevenlabs.io/pricing)
4. [ElevenLabs docs overview](https://elevenlabs.io/docs/product/introduction)
5. [ElevenLabs speech-to-text overview](https://elevenlabs.io/docs/capabilities/speech-to-text)
6. [Wispr Flow pricing](https://wisprflow.ai/pricing)
7. [Wispr Flow plan details](https://docs.wisprflow.ai/articles/9559327591-flow-plans-and-what-s-included)

## Current limits

This first build does not yet include:

1. live partial transcript display in the widget
2. local on-device speech-to-text fallback
3. per-app formatting profiles or tone presets
4. widget context menus or compact/expanded modes
