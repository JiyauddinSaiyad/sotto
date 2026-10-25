import AppKit
import FoundationModels
import Observation

@Generable
struct MeetingNotes {
    @Guide(description: "A 3 to 5 sentence summary of the meeting")
    var summary: String
    @Guide(description: "Concrete tasks someone agreed to do, as 'Name: task by deadline'. Use a name only if it was said in the meeting; otherwise just the task")
    var actionItems: [String]
    @Guide(description: "Decisions the group agreed on, not tasks")
    var decisions: [String]
}

@MainActor @Observable
final class Meeting {
    struct Line: Identifiable {
        let id = UUID()
        let speaker: String
        var text: String
    }

    struct Message: Identifiable {
        let id = UUID()
        let fromUser: Bool
        var text: String
    }

    /// The buttons under the chat. Each is just a prompt in a trench coat.
    enum Action: String, CaseIterable {
        case assist = "Assist"
        case reply = "What should I say?"
        case followUps = "Follow-up questions"
        case recap = "Recap"

        var icon: String {
            switch self {
            case .assist: "sparkles"
            case .reply: "wand.and.stars"
            case .followUps: "bubble.left.and.text.bubble.right"
            case .recap: "arrow.triangle.2.circlepath"
            }
        }

        var prompt: String {
            switch self {
            case .assist: "Look at the last few lines. If someone just asked a question, give me a short answer I can use. Otherwise explain the main point being discussed right now. At most 3 short sentences."
            case .reply: "Write what I could say next, replying directly to the most recent lines and mentioning their specifics. Reply with only the words to say, in one or two natural sentences."
            case .followUps: "Suggest 3 specific follow-up questions I could ask about what was discussed, one per line, starting each with \"• \"."
            case .recap: "Recap the conversation so far in 3 to 5 short lines, each starting with \"• \". Name who owns each task when a name was said."
            }
        }
    }

    static let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "Sotto")

    var lines: [Line] = []
    var messages: [Message] = []
    var startedAt: Date?
    var notes: MeetingNotes?
    var status = ""
    var stealth = false {
        didSet { NSApp.windows.forEach { $0.sharingType = stealth ? .none : .readOnly } }
    }

    var isStarting = false
    // New every meeting. A transcriber's results stream reads exactly once; a
    // second read is a crash, ask me how I know.
    private var mic = MicCapture()
    private var system = SystemAudioCapture()
    private var micText = Transcriber()
    private var systemText = Transcriber()
    private var pending: [String: UUID] = [:]
    // Summarizing talk is "content transformation" to Apple; the default guardrails
    // flinch at ordinary meeting chatter.
    private let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    private var instructions: String {
        var text = """
            You are a private meeting assistant helping the user. In the transcript, "You:" lines are the user and \
            "Them:" lines are the other participants, who may be several different people. Never call anyone "Them" \
            and never copy transcript lines; use the names people say, or "they". Use only what the transcript says, \
            and never invent people or facts. When a "Them" speaker volunteers for a task without saying their \
            own name, leave the task without an owner rather than guessing.
            """
        // SpeechTranscriber ignores contextual strings (tested: identical output).
        // So the recognizer mishears, and the model fixes the spelling after.
        if let vocabulary = UserDefaults.standard.string(forKey: "vocabulary"), !vocabulary.isEmpty {
            text += " Speech recognition may mishear these names and terms; always spell them like this: \(vocabulary)."
        }
        return text
    }

    var isRunning: Bool { startedAt != nil }

    /// No Apple Intelligence, no Sotto. Say why in plain words, not an enum case.
    var unavailable: String? {
        switch model.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "This Mac can't run Apple Intelligence. Sotto needs a Mac with Apple silicon (M1 or later)."
        case .unavailable(.appleIntelligenceNotEnabled): "Apple Intelligence is turned off. Turn it on in System Settings → Apple Intelligence & Siri, then reopen Sotto."
        case .unavailable(.modelNotReady): "Apple Intelligence is still downloading its model. Keep your Mac online and try again in a few minutes."
        case .unavailable: "Apple Intelligence isn't available on this Mac right now."
        }
    }

    func start() async {
        guard !isStarting, !isRunning, unavailable == nil else { return }
        isStarting = true
        defer { isStarting = false }
        mic = MicCapture()
        system = SystemAudioCapture()
        micText = Transcriber()
        systemText = Transcriber()
        lines = []
        notes = nil
        messages = []
        pending = [:]
        status = "Starting…"
        do {
            try await micText.start { [weak self] in self?.update("You", $0, $1) }
            try await systemText.start { [weak self] in self?.update("Them", $0, $1) }
            try mic.start { [micText] in micText.feed($0) }
            try await system.start(onBuffer: { [systemText] in systemText.feed($0) }, onStop: { [weak self] error in
                Task { @MainActor in self?.status = "Stopped hearing system audio: \(error.localizedDescription)" }
            })
            startedAt = .now
            status = ""
            Task {
                try? await Task.sleep(for: .seconds(3))
                if isRunning, !system.isFlowing {
                    status = "Can't hear the other side. Allow Sotto in System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only."
                }
            }
        } catch {
            status = "Couldn't start: \(error.localizedDescription)"
            await stopCapture()
        }
    }

    func stop() async {
        await stopCapture()
        startedAt = nil
        guard !lines.isEmpty else { return }
        status = "Writing notes…"
        var problem = ""
        do {
            let notes = try await summarize()
            self.notes = notes
            var text = notes.summary
            if !notes.actionItems.isEmpty { text += "\n\nAction items\n" + notes.actionItems.map { "• \($0)" }.joined(separator: "\n") }
            if !notes.decisions.isEmpty { text += "\n\nDecisions\n" + notes.decisions.map { "• \($0)" }.joined(separator: "\n") }
            messages.append(Message(fromUser: false, text: text))
        } catch {
            problem = "Couldn't write notes (\(error.localizedDescription)); transcript kept. "
        }
        // Notes are nice to have; the transcript is the meeting. It always gets saved.
        do {
            status = problem + "Saved to \(try save().lastPathComponent)"
        } catch {
            status = problem + "Couldn't save: \(error.localizedDescription)"
        }
    }

    func ask(_ question: String, label: String? = nil) async {
        messages.append(Message(fromUser: true, text: label ?? question))
        guard !lines.isEmpty else {
            messages.append(Message(fromUser: false, text: "Nothing transcribed yet. Press Start when your meeting begins."))
            return
        }
        messages.append(Message(fromUser: false, text: "Thinking…"))
        let reply = messages.count - 1
        let prompt = "Transcript:\n\(String(transcript.suffix(6000)))\n\nRequest: \(question)"
        do {
            messages[reply].text = try await retrying {
                try await LanguageModelSession(model: model, instructions: instructions).respond(to: prompt).content
            }
            // 3B params occasionally answers with "• • • • •". Lines with nothing to
            // say get dropped.
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.isEmpty || $0.contains(where: { $0.isLetter || $0.isNumber }) }
            .map { $0.replacing(/^(\s*•\s*)+/, with: "• ") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            messages[reply].text = "Couldn't answer that: \(error.localizedDescription)"
        }
    }

    private var transcript: String {
        lines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
    }

    private func stopCapture() async {
        mic.stop()
        await system.stop()
        await micText.stop()
        await systemText.stop()
    }

    /// The recognizer drafts a phrase, revises it, then commits. Edit the draft in
    /// place so the transcript doesn't stutter.
    private func update(_ speaker: String, _ text: String, _ isFinal: Bool) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = pending[speaker], let i = lines.firstIndex(where: { $0.id == id }) {
            if text.isEmpty { lines.remove(at: i) } else { lines[i].text = text }
            if isFinal { pending[speaker] = nil }
        } else if !text.isEmpty {
            let line = Line(speaker: speaker, text: text)
            lines.append(line)
            if !isFinal { pending[speaker] = line.id }
        }
    }

    /// ~4K tokens of context. A 40-minute meeting won't fit, so condense it in chunks,
    /// and keep condensing until it does. Map-reduce for one.
    private func summarize() async throws -> MeetingNotes {
        var source = transcript
        while source.count > 6000 {
            var chunks = [""]
            for line in source.split(separator: "\n") {
                if chunks[chunks.count - 1].count + line.count > 6000 { chunks.append("") }
                chunks[chunks.count - 1] += line + "\n"
            }
            var parts: [String] = []
            for chunk in chunks {
                parts.append(try await retrying {
                    try await LanguageModelSession(model: model, instructions: instructions)
                        .respond(to: "Condense this part of a meeting. Keep every task with its owner and deadline, every decision, and every number:\n\(chunk)").content
                })
            }
            source = parts.joined(separator: "\n")
        }
        return try await retrying {
            try await LanguageModelSession(model: model, instructions: instructions)
                .respond(to: "Write meeting notes from this meeting:\n\(source)", generating: MeetingNotes.self).content
        }
    }

    /// Ask once, forgive once, then give up. The on-device model has off moments
    /// (busy, or a jumpy safety filter), not a grudge.
    private func retrying<T>(_ request: () async throws -> T) async throws -> T {
        do {
            return try await request()
        } catch {
            try await Task.sleep(for: .seconds(1))
            return try await request()
        }
    }

    private func save() throws -> URL {
        let folder = Self.folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = Date.now.formatted(.verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits)", timeZone: .current, calendar: .current))
        let file = folder.appending(path: "\(name).md")
        var md = "# Meeting \(Date.now.formatted(date: .long, time: .shortened))\n\n"
        if let notes {
            md += "## Summary\n\n\(notes.summary)\n\n## Action items\n\n"
            md += notes.actionItems.map { "- [ ] \($0)" }.joined(separator: "\n") + "\n\n## Decisions\n\n"
            md += notes.decisions.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        md += "## Transcript\n\n" + lines.map { "**\($0.speaker):** \($0.text)" }.joined(separator: "\n\n") + "\n"
        try md.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}

