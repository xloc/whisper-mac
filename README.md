# Whisper PTT

Native macOS push-to-talk transcription. Hold the configured shortcut, speak, release, and the local transcript is pasted into the active input. Each recording's language is detected automatically and transcribed in its original language, without translation.

WhisperKit runs the Whisper model through Core ML. The mel stage is configured for the GPU and the encoder and decoder for CPU plus Neural Engine, so Apple Silicon acceleration is selected explicitly in the source.

## Build and run

The first build downloads the Swift dependencies. The first launch downloads the selected model from WhisperKit's model repository. App data lives under `~/.whisper-ptt`:

- `huggingface/`: models, shared tokenizers, partial downloads, and model size manifests.
- `history.json`: transcripts across launches.
- `settings.json`: shortcut and last successfully loaded model.

On upgrade, the app moves the existing cache from `~/Library/Application Support/Whisper PTT/huggingface` and imports the previous model and shortcut preferences. History stays in place. The old preference keys are removed after the move succeeds. Quit the old app before launching this build. The much earlier `~/Documents/huggingface` location is not accessed by the app.

To reset app data and preferences, quit the app and delete `~/.whisper-ptt`. The next launch starts with the default shortcut and model, an empty history, and a new model download. Microphone and Accessibility permissions are managed by macOS separately. **Open App Folder…** in History opens the folder in Finder.

```sh
./scripts/build-app.sh
open "Whisper PTT.app"
```

For Accessibility permission to survive rebuilds, sign with a stable Apple Development identity. The script detects the first one automatically, or you can select one explicitly:

```sh
security find-identity -v -p codesigning
export WHISPER_PTT_SIGNING_IDENTITY='Apple Development: Your Name (TEAMID)'
./scripts/build-app.sh
```

Without a development identity, the script falls back to ad-hoc signing. macOS may then treat each changed build as a new code identity and ask for Accessibility again.

For a smaller first download, use `--model tiny` or `--model base`:

```sh
open "Whisper PTT.app" --args --model tiny
```

Grant the app **Microphone** access. Grant **Accessibility** access to the app in System Settings → Privacy & Security → Accessibility so it can monitor the shortcut and post ⌘V into the active input. Documents folder permission can be disabled in Privacy & Security → Files & Folders.

The app opens a resizable native **Whisper PTT** window with **Dictation**, **Models**, and **History** tabs. An SF Symbol, short status heading, and contextual instructions show the current state. Dictation groups the shortcut, model, permissions, and selectable latest transcript. Permission request buttons appear only when needed; **Open Settings…** uses a standard bordered button in each permission row. Clicking the menu-bar icon opens the window directly. Its SF Symbol reflects loading, missing permissions, ready, recording, transcribing, text sent, no speech, or error; hover to read the status. Text sent means the paste command was dispatched. Success and no-speech feedback last two seconds before returning to the idle status.

The menu-bar symbol uses Apple's native Symbols animations. Model loading (`progress.indicator`) and recording (`waveform`) use iterative variable color that dims inactive layers and runs without reversing, repeating continuously on macOS 15 and later. Recording uses periodic repetition on macOS 14. Transcription (`text.viewfinder`) pulses as a whole symbol, repeating with a one-second delay on macOS 15 and later (regular repetition on macOS 14). This keeps the glyph intact at menu-bar size instead of repeatedly drawing its individual layers. Errors use `xmark.circle` with a one-time Draw On animation on macOS 26 and later; on earlier systems the error icon remains still. The static states use `waveform.badge.minus` for missing permissions, a plain `mic` for ready, `checkmark.circle` for text sent, and `waveform.badge.exclamationmark` for no speech detected. Animations stop when the status changes and are disabled by the system's Reduce Motion setting. Updating download percentages does not restart an existing animation. These effects run through AppKit, with no additional icon library or SwiftUI dependency. The selected symbols are all available on macOS 15 and later; Draw On requires macOS 26.

The **Model** selector offers `tiny`, `base`, `small`, `medium`, `large-v3`, and `large-v3_turbo`. Switching unloads the previous model and downloads the new one if needed. The last successfully loaded selection is saved for the next launch. Model and shortcut changes are disabled during loading, recording, and transcription. Choose Right Option, Right Command, F13, or Fn / Globe; the shortcut is also saved. Each permission row has **Allow…** and **Open Settings…** buttons; the latter opens the matching Privacy & Security page in System Settings. Permission status refreshes when you return to the app. **Test Paste** hides the window briefly and sends a known string into the previous app, which isolates Accessibility/paste problems from Whisper transcription problems. Use **Quit** or **⌘Q** while the window is active to exit; closing the window keeps push-to-talk running in the menu bar.

The **Models** tab uses a native table with Model, Size, and Status columns. Select a row to see its details and available actions below. **Download** caches that model without changing the current dictation model, so the loaded model can keep transcribing. **Use Model** loads a downloaded model. **Remove Download** deletes inactive model files and partial downloads, leaving shared tokenizers intact. The model in use cannot be removed. The footer summarizes downloaded models and cached bytes; **More** offers **Show Selected Model in Finder**, **Refresh Model Sizes**, and **Open Model Folder…**. Switching models and removing files are disabled during downloads.

Download progress appears as a percentage in the model's Status column, or above the other tabs. There are no progress bars. Preparing Core ML and the tokenizer is shown as a text status. For the listed models, progress uses completed files plus partial download bytes divided by the repository's total file size. A model is marked downloaded only when every listed file exists at its expected size. Sizes come from Hugging Face file manifests; a bundled snapshot and saved refreshes keep this information available offline. Sizes exclude shared tokenizer files and extra filesystem overhead. The bundled snapshots were read from `argmaxinc/whisperkit-coreml` on 2026-10-01.

The **History** tab uses a native table with Time and Transcript columns, newest first. Each transcript occupies one line, with an ellipsis for overflow. Hover for the original text, or select a row to read its full text in the scrollable preview below. The preview preserves line breaks and supports selecting and copying part of the text. Search filters the original text, and **⌘F** focuses the search field. Select one or more rows and use **Copy Text** or **⌘C** to copy the original text without timestamps. With the table focused, **⌘A** selects all visible rows. **Open App Folder…** opens `~/.whisper-ptt`, where `history.json` stores the original text, timestamp, and model as readable JSON. Each successful, nonempty transcription is saved atomically before pasting, so a paste failure does not lose the transcript. Closing and reopening the app restores history and the latest transcript. Test Paste samples are not recorded. Text from versions that did not save history cannot be recovered. Read or write failures are reported in the window, and an unreadable existing history file is not overwritten.

The executable accepts `--model MODEL` to override the saved selection at startup. Use a multilingual model such as `base` (the first-launch default); English-only `.en` models are rejected. Language detection is always enabled, with no language override.

Whisper is called locally after release: `AVAudioEngine` produces mono audio, the recorder converts it to 16 kHz `Float32`, and `WhisperKit.transcribe(audioArray:decodeOptions:)` returns the segment text. The app joins the segments, shows the result in the window, and pastes it only after checking Accessibility permission.

## Tests

```sh
swift test
```

The tests cover shortcut press/release state, microphone sample-rate conversion, transcript assembly, permission status precedence, offline model sizes, partial downloads, truncated files, and model removal without deleting shared tokenizers. History tests save and reload across multiple sessions, preserve multilingual and repeated text, protect malformed files on read, and report write failures. Storage tests move models, tokenizers, and partial downloads, preserve existing history and settings, verify folder deletion resets the app, and protect malformed settings and conflicting model folders. The window reports runtime microphone, model, Accessibility, transcription, paste, and storage failures because device and permission checks require the user's environment.

To run the optional on-device model switching and language regression test, which downloads the base and tiny models if needed:

```sh
WHISPER_PTT_RUN_MODEL_TESTS=1 swift test --filter WhisperIntegrationTests
```

The download test uses an isolated temporary copy of `tiny`, removes one file, and verifies that the real downloader restores it and reports intermediate progress through completion. The language regression test switches `base → tiny → base`, checks model unloading, and sends Chinese and English speech through the same loader and transcription code as the app. It checks that each output preserves its language. The audio fixtures are generated with macOS speech synthesis; they do not test microphone capture or pasting into another app.
