# SpeakFlow (macOS)

`SpeakFlow` is a local macOS menu bar dictation app:

1. global hotkey dictation from any app
2. native microphone capture
3. floating dictation widget you can click or drag
4. ElevenLabs realtime speech recognition with English + Russian support
5. optional LLM cleanup pass for punctuation and readability
6. Accessibility text insertion first, paste fallback second

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

## Current limits

This first build does not yet include:

1. live partial transcript display in the widget
2. local on-device speech-to-text fallback
3. per-app formatting profiles or tone presets
4. widget context menus or compact/expanded modes
