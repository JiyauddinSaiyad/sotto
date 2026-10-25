// LLM speed on Apple's on-device model, measured the boring way: stream, time, count tokens.
// Build: swiftc -O bench/llm.swift -o build/llm-bench && build/llm-bench
import Foundation
import FoundationModels

let model = SystemLanguageModel.default
guard case .available = model.availability else { print("Model unavailable: \(model.availability)"); exit(1) }

// tokenCount wraps text in a prompt template; subtract the empty-prompt cost so we count only the text.
let overhead = try await model.tokenCount(for: "")
func tokens(_ s: String) async throws -> Int { try await model.tokenCount(for: s) - overhead }

struct Run { var promptTokens = 0, outputTokens = 0, ttft = 0.0, total = 0.0 }

func run(_ prompt: String) async throws -> Run {
    let session = LanguageModelSession(model: model) // fresh per request, same as the app
    var r = Run()
    r.promptTokens = try await tokens(prompt)
    let start = Date()
    var text = ""
    for try await snap in session.streamResponse(to: prompt) {
        if r.ttft == 0, !snap.content.isEmpty { r.ttft = Date().timeIntervalSince(start) }
        text = snap.content
    }
    r.total = Date().timeIntervalSince(start)
    r.outputTokens = try await tokens(text)
    return r
}

func median(_ xs: [Double]) -> Double { let s = xs.sorted(); return s[s.count / 2] }

// The transcript texts are the first lines of LibriSpeech test-clean, so nothing here is made up or tuned.
let corpus = (try? String(contentsOfFile: CommandLine.arguments.dropFirst().first ?? "", encoding: .utf8)) ?? ""
let words = corpus.split(separator: " ")
func transcript(_ n: Int) -> String { words.prefix(n).joined(separator: " ").lowercased() }

let workloads: [(String, String)] = [
    ("Short answer", "In two sentences, what is a meeting agenda for?"),
    ("Long answer (decode)", "Write about 400 words on how to run a good weekly team meeting."),
    ("Recap of ~1K-token transcript", "Transcript:\n\(transcript(700))\n\nRecap this in 4 short bullets."),
    ("Recap of ~3K-token transcript (prefill)", "Transcript:\n\(transcript(2200))\n\nRecap this in 4 short bullets."),
]

// First call pays for loading the model. Measure it once, then keep it out of the medians.
let cold = try await run("Say hi.")
print(String(format: "Cold start (first request in a new process): %.2f s", cold.total))

let reps = 5
print("\n| Workload | Prompt tok | Output tok | Time to first token | Prefill tok/s | Decode tok/s | Total |")
print("|---|---|---|---|---|---|---|")
for (name, prompt) in workloads {
    var runs: [Run] = []
    for _ in 0..<reps { runs.append(try await run(prompt)) }
    let ttft = median(runs.map(\.ttft))
    let prefill = median(runs.map { Double($0.promptTokens) / $0.ttft })
    let decode = median(runs.map { Double(max($0.outputTokens - 1, 1)) / max($0.total - $0.ttft, 0.001) })
    print(String(format: "| %@ | %d | %d | %.2f s | %.0f | %.1f | %.2f s |",
                 name, runs[0].promptTokens, Int(median(runs.map { Double($0.outputTokens) })), ttft, prefill, decode, median(runs.map(\.total))))
}
print("\nContext window: \(model.contextSize) tokens. Medians of \(reps) runs.")
