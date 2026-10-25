<p align="center"><img src="Sotto/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" width="128" alt="Sotto icon"></p>

<h1 align="center">Sotto</h1>

<p align="center"><b>A whole meeting copilot in a 0.8 MB download.</b><br>
Live transcript, answers mid-call, and notes afterwards, all running on the AI already built into your Mac.</p>

<p align="center"><a href="https://github.com/JiyauddinSaiyad/sotto/releases/latest/download/Sotto.zip"><b>Download for Mac</b></a> · <a href="https://jiyauddinsaiyad.github.io/sotto/">Website</a></p>

<p align="center"><img src="docs/demo.gif" width="684" alt="Sotto transcribing a meeting live, recapping it, and writing notes with action items and decisions"></p>

---

Your Mac already ships with an on-device language model and speech recognizer (Apple Intelligence). Most people never use them. Sotto puts them to work in your meetings:

- **0.8 MB.** That's the whole download. No Whisper, no Llama, no models. It uses what macOS already has.
- **$0.** No API keys, no subscription, no usage limits.
- **Private.** Audio and transcripts never leave your Mac.
- **Light.** The model only wakes up when you ask it something.

*sotto voce* (Italian): "in a quiet voice". An assistant that whispers to you, not the room.

## What it does

- **Live transcript** of both sides of any call: Zoom, Meet, Teams, Slack, Webex, FaceTime. Your mic is "You", everything else is "Them".
- **Ask mid-meeting.** Type a question, or one tap for **Assist**, **What should I say?**, **Follow-up questions** and **Recap**.
- **Notes when you stop.** Summary, action items and decisions, saved as Markdown in `~/Documents/Sotto/`.
- **History.** Past meetings open right inside the app.
- **Stays out of the way.** A small glass panel that floats over every app and full-screen Space and never steals focus.
- **Hide from screen sharing** with one click (the 👁 button); a dotted border shows it's on. It uses macOS's window-sharing flag, which meeting apps don't all honor the same way, so check your app's share preview before relying on it.
- **No Dock icon.** Quit from the **⋯** menu.

| Shortcut | Action |
|---|---|
| ⌘↵ | Assist (only during a meeting; other apps keep ⌘↵ otherwise) |
| ⌘\ | Hide / show the panel |

## Requirements

- A Mac with Apple silicon (M1 or later)
- macOS 26 or later
- Apple Intelligence turned on (System Settings → Apple Intelligence & Siri)

Sotto checks this at launch and tells you plainly if something's missing.

## Install

1. Download [Sotto.zip](https://github.com/JiyauddinSaiyad/sotto/releases/latest/download/Sotto.zip) and open it.
2. Drag **Sotto** into **Applications**.
3. Open it. macOS will say it can't verify the developer, because Sotto isn't notarized yet. Go to **System Settings → Privacy & Security** and click **Open Anyway**. You only do this once.

## Build and run

Prefer to build it yourself? You'll need Xcode.


```sh
brew install xcodegen
git clone https://github.com/JiyauddinSaiyad/sotto.git && cd sotto
xcodegen generate
open Sotto.xcodeproj   # pick your team under Signing & Capabilities, then Run
```

## Permissions

Sotto asks for two things, and nothing else:

| Permission | Why |
|---|---|
| **Microphone** | To transcribe you |
| **System Audio Recording Only** | To transcribe everyone else on the call. Audio only; Sotto never sees your screen |

If the other side isn't showing up, open **System Settings → Privacy & Security → Screen & System Audio Recording**, and turn Sotto on under **System Audio Recording Only**. macOS doesn't always show the prompt on first run.

## Honest limitations

Sotto runs on Apple's small (~3B parameter) on-device model. That's what makes it free and private, and it also sets the ceiling:

- **Everyone except you is "Them".** Apple's speech APIs don't separate speakers, so Sotto can't tell who said what on the other side.
- **Names and jargon get misheard.** Add them under **Settings → Names & terms** and the notes will use the right spelling. The live transcript can't be corrected; Apple's recognizer ignores custom vocabulary.
- **Language:** uses your Mac's language if Apple's speech recognizer supports it. Only English has been tested.
- **Notes vary** from run to run, and the model can miss an action item. Skim them before you send them on.

For summaries, follow-ups and "what was that number again?", it's genuinely useful. For deep reasoning, it's not a frontier model and doesn't pretend to be.

## How it works

```
mic ───────► SpeechTranscriber ─┐
                                ├─► transcript ─► Foundation Models ─► answers & notes
system audio ► SpeechTranscriber ┘
(Core Audio process tap)
```

Everything is Apple frameworks: `AVAudioEngine` with voice processing for the mic, a Core Audio process tap for system audio, `SpeechAnalyzer` / `SpeechTranscriber` for speech to text, and `FoundationModels` for everything the model writes. Long meetings are condensed in chunks to fit the model's ~4K-token context.

Five Swift files, no dependencies.

## License

MIT. See [LICENSE](LICENSE).
