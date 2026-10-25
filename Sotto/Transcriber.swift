import AVFoundation
import Speech

/// One ear. Sotto runs two: mic and system audio. Built-in speech-to-text; the
/// only download is a missing language pack, once, fetched by macOS itself.
final class Transcriber {
    private let transcriber = SpeechTranscriber(locale: Locale.current, preset: .progressiveTranscription)
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var format: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var results: Task<Void, Never>?
    private var heardAnything = false

    func start(onText: @escaping @MainActor (String, Bool) -> Void) async throws {
        let modules: [any SpeechModule] = [transcriber]
        if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            try await request.downloadAndInstall()
        }
        format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules)

        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        input = continuation
        let analyzer = SpeechAnalyzer(modules: modules)
        self.analyzer = analyzer

        let transcriber = transcriber
        results = Task {
            do {
                for try await result in transcriber.results {
                    await onText(String(result.text.characters), result.isFinal)
                }
            } catch {}
        }
        try await analyzer.start(inputSequence: stream)
    }

    /// Audio-thread hot path. Takes whatever format the hardware felt like today
    /// and converts it to what the analyzer insists on.
    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let format, let input else { return }
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else { return }

        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        var consumed = false
        converter.convert(to: out, error: nil) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if out.frameLength > 0 {
            heardAnything = true
            input.yield(AnalyzerInput(buffer: out))
        }
    }

    func stop() async {
        input?.finish()
        input = nil
        // Finalizing an analyzer that never got a single buffer waits forever, and
        // there's nothing to finalize anyway. Cancel and move on.
        guard heardAnything else {
            results?.cancel()
            await analyzer?.cancelAndFinishNow()
            return
        }
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await results?.value
    }
}
