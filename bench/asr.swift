// Speech-to-text on LibriSpeech, the dataset every ASR paper reports on.
// Build: swiftc -O bench/asr.swift -o build/asr-bench
// Run:   build/asr-bench path/to/LibriSpeech/test-clean > build/asr.tsv && python3 bench/wer.py build/asr.tsv path/to/LibriSpeech/test-clean
import AVFoundation
import Foundation
import Speech

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let limit = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : .max
let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!.compactMap { $0 as? URL })
    .filter { $0.pathExtension == "flac" }.sorted { $0.path < $1.path }.prefix(limit)

let locale = Locale(identifier: "en_US")
let probe = SpeechTranscriber(locale: locale, preset: .transcription)
if let req = try await AssetInventory.assetInstallationRequest(supporting: [probe]) { try await req.downloadAndInstall() }

var audio = 0.0, busy = 0.0, done = 0
for url in files {
    // A truncated download shouldn't take the whole run down with it.
    guard let file = try? AVAudioFile(forReading: url), file.length > 0 else {
        FileHandle.standardError.write("skip \(url.lastPathComponent)\n".data(using: .utf8)!); continue
    }
    let t = SpeechTranscriber(locale: locale, preset: .transcription)
    let analyzer = SpeechAnalyzer(modules: [t])
    let start = Date()
    // Results is a one-shot stream: start reading before feeding, or you'll miss the party.
    let text = Task { try await t.results.reduce("") { $0 + String($1.text.characters) } }
    let hyp: String
    do {
        if let end = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        hyp = try await text.value
    } catch {
        // Header said the file was whole; the bytes disagreed.
        await analyzer.cancelAndFinishNow()
        FileHandle.standardError.write("skip \(url.lastPathComponent): \(error.localizedDescription)\n".data(using: .utf8)!)
        continue
    }
    busy += Date().timeIntervalSince(start)
    audio += Double(file.length) / file.fileFormat.sampleRate
    done += 1
    print("\(url.deletingPathExtension().lastPathComponent)\t\(hyp.replacingOccurrences(of: "\n", with: " "))")
}
FileHandle.standardError.write(String(format: "files %d  audio %.0f s  processing %.0f s  RTF %.3f  (%.0fx real time)\n",
                                      done, audio, busy, busy / audio, audio / busy).data(using: .utf8)!)
