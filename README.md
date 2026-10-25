<p align="center"><img src="Sotto/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" width="128" alt="Sotto icon"></p>

<h1 align="center">Sotto</h1>

<p align="center"><b>A free meeting copilot in a 0.8 MB download.</b><br>
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

Rather skip that warning? Paste this in Terminal. Files fetched with `curl` aren't quarantined, so macOS opens Sotto straight away:

```sh
curl -sL https://github.com/JiyauddinSaiyad/sotto/releases/latest/download/Sotto.zip -o /tmp/Sotto.zip && ditto -xk /tmp/Sotto.zip /Applications && open /Applications/Sotto.app
```

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

## Benchmarks

M4 MacBook Air (16 GB, fanless), macOS 27.0.1, medians of 5 runs. Run them yourself with the tools in [`bench/`](bench).

**Language model** (Apple Foundation Models, on-device ~3B, tokens counted with Apple's tokenizer)

| Workload | In | Out | First token | Prefill | Decode |
|---|---|---|---|---|---|
| Short answer | 11 | 33 | 0.42 s | – | 55 tok/s |
| Long answer | 17 | 434 | 0.37 s | – | 42 tok/s |
| Recap, 1K-token transcript | 818 | 136 | 0.79 s | 1,032 tok/s | 35 tok/s |
| Recap, 3K-token transcript | 2,578 | 133 | 2.29 s | 1,127 tok/s | 26 tok/s |

Cold start (first request after launch): 3.75 s. A hot, fanless Air ran up to ~40% slower.

**Speech to text** (Apple SpeechTranscriber, LibriSpeech test-clean)

| | WER | Speed | Ships with app |
|---|---|---|---|
| **Sotto** | **2.06%** | **49× real time** | **0 MB** |
| Whisper Small* | 3.74% | | 466 MB |
| Whisper Base* | 5.42% | | 142 MB |
| Whisper Tiny* | 7.88% | | 75 MB |

Ours: all 2,620 utterances, 52,576 words, 5.4 hours of audio in 6.6 minutes. *Whisper rows are a [published third-party run](https://www.developersdigest.tech/blog/apple-speechanalyzer-vs-whisper-benchmark) on an M2 Pro, not ours; it measured Apple's recognizer at 2.12%.

**Footprint:** 0.8 MB download, 1.6 MB installed, ~85 MB RAM mid-meeting (the model lives in macOS, not in Sotto), 0 dependencies.

## How it compares

There are great open-source meeting tools. Every one we checked asks you to download a model or paste an API key first.

| Open-source app | Mac download | What you set up before it works |
|---|---|---|
| **Sotto** | **0.8 MB** | **Nothing. It uses the AI built into macOS.** |
| [Meetily](https://github.com/Zackriya-Solutions/meetily) | 45 MB | A Whisper or Parakeet model, plus Ollama or an API key for summaries |
| [Anarlog](https://github.com/fastrepl/anarlog) | 201 MB | A local model server, your own API key, or their hosted plan |
| [cheating-daddy](https://github.com/sohzm/cheating-daddy) | 92 MB | A Gemini API key |
| [Pluely](https://github.com/iamsrikanthnani/pluely) | 13 MB | Your API key, an AI CLI, or a paid plan |
| [free-cluely](https://github.com/Prat011/free-cluely) | Build from source | A Gemini API key or Ollama |
| [OpenCluely](https://github.com/TechyCSR/OpenCluely) | Setup script | A Gemini API key, plus a local Whisper install |

The six most-starred open-source alternatives on GitHub, checked on Oct 26, 2026 against each project's README and latest release.

And the paid ones:

| App | Paid plan | Hide from screen share | Free tier |
|---|---|---|---|
| **Sotto** | **Free** | **Free, opt-in** | **Everything, unlimited** |
| Cluely | $19.99/mo (Pro) | $149.99/mo plan | Starter, limited |
| Final Round AI | $25/mo (Pro) | In Pro | No live copilot |
| Parakeet AI | ₹9,470/mo unlimited† | – | One 10-minute session |
| Granola | $14/user/mo (Business) | – | 30 days of meeting history |
| Otter.ai | $16.99/user/mo (Pro) | – | 300 min/month, 30 min per meeting |

Prices from each company's own pricing page on Oct 26, 2026, monthly billing; "–" means not offered on that page. †Parakeet AI prices by region; this is what its page showed us. If anything here is out of date, open an issue and we'll fix it.

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

Everything is Apple frameworks: `AVAudioEngine` with voice processing for the mic, a Core Audio process tap for system audio, `SpeechAnalyzer` / `SpeechTranscriber` for speech to text, and `FoundationModels` for everything the model writes. Long meetings are condensed in chunks to fit the model's context window (8,192 tokens on macOS 27).

Five Swift files, no dependencies.

## Support

Sotto is free and always will be. If it saves you a subscription, [buy me a coffee](https://buymeacoffee.com/jsaiyad).

## License

MIT. See [LICENSE](LICENSE).
