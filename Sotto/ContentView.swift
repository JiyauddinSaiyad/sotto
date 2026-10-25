import SwiftUI

struct ContentView: View {
    enum Tab: String, CaseIterable {
        case chat = "Chat", transcript = "Transcript", history = "History", settings = "Settings"
    }

    @State private var meeting = Meeting()
    @State private var question = ""
    @State private var expanded = true
    @State private var tab = Tab.chat
    @AppStorage("width") private var width = 564.0
    @AppStorage("height") private var height = 260.0
    @State private var resizeStart: CGSize?

    var body: some View {
        VStack(spacing: 8) {
            pill
            if expanded {
                card
            }
        }
        .padding(8)
        .overlay {
            // Dotted line = invisible to screen share. A reminder for you, since
            // nobody else can see it anyway.
            if meeting.stealth {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .allowsHitTesting(false)
            }
        }
        .padding(2)
        .frame(width: width)
        .animation(.snappy(duration: 0.2), value: expanded)
        .preferredColorScheme(.dark)
        // Not pure white: full-bright text ends up reflected in your glasses on camera.
        .foregroundStyle(.white.opacity(0.95))
        .onReceive(NotificationCenter.default.publisher(for: .toggleCard)) { _ in expanded.toggle() }
        .onReceive(NotificationCenter.default.publisher(for: .assist)) { _ in
            expanded = true
            tab = .chat
            Task { await meeting.ask(Meeting.Action.assist.prompt, label: Meeting.Action.assist.rawValue) }
        }
        .onChange(of: meeting.isRunning) { HotKeys.setAssist(meeting.isRunning) }
        #if DEBUG
        // Hands-free smoke test: `open Sotto.app --args -testSeconds 90`.
        // Listens, pokes every action mid-meeting, stops. Debug builds only.
        .task {
            let seconds = UserDefaults.standard.double(forKey: "testSeconds")
            guard seconds > 0 else { return }
            tab = .transcript
            await meeting.start()
            print("START:", meeting.status.isEmpty ? "ok" : meeting.status)
            try? await Task.sleep(for: .seconds(seconds))
            tab = .chat
            for action in Meeting.Action.allCases {
                let clock = ContinuousClock.now
                await meeting.ask(action.prompt, label: action.rawValue)
                print("## \(action.rawValue) (\(ContinuousClock.now - clock))\n\(meeting.messages.last!.text)\n")
            }
            let clock = ContinuousClock.now
            await meeting.stop()
            print("## Notes (\(ContinuousClock.now - clock))\n\(meeting.messages.last?.text ?? "")\n\nSTATUS: \(meeting.status)")
            fflush(stdout)
        }
        #endif
    }

    // MARK: Control pill

    private var pill: some View {
        HStack(spacing: 6) {
            Image("Mark")
                .resizable()
                .frame(width: 26, height: 26)
                .clipShape(Circle())
                .padding(.leading, 4)
            PillButton(title: expanded ? "Hide" : "Show", icon: expanded ? "chevron.down" : "chevron.up") {
                expanded.toggle()
            }
            if let start = meeting.startedAt {
                TimelineView(.periodic(from: start, by: 1)) { context in
                    Text(Duration.seconds(context.date.timeIntervalSince(start)).formatted(.time(pattern: .minuteSecond)))
                        .monospacedDigit()
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
            Button {
                Task { meeting.isRunning ? await meeting.stop() : await meeting.start() }
            } label: {
                Image(systemName: meeting.isRunning ? "stop.fill" : "record.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(meeting.isRunning ? .red : .primary)
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .disabled(meeting.isStarting || meeting.unavailable != nil)
            .help(meeting.isRunning ? "Stop and write notes" : "Start listening")
            Button {
                meeting.stealth.toggle()
            } label: {
                Image(systemName: meeting.stealth ? "eye.slash.fill" : "eye")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(meeting.stealth ? Color.accentColor : .primary)
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(meeting.stealth ? 0.2 : 0.1), in: Circle())
            }
            .help(meeting.stealth ? "Invisible to screen sharing. Click to show." : "Visible to screen sharing. Click to hide.")
            Menu {
                Button("Open notes folder") { NSWorkspace.shared.open(Meeting.folder) }
                Divider()
                Button("Quit Sotto") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .frame(width: 30)
        }
        .buttonStyle(.plain)
        .padding(5)
        .shadow(color: .black.opacity(0.8), radius: 1.5)
        .glassEffect(.clear.tint(.black.opacity(0.55)), in: Capsule())
        .help("Drag to move · ⌘\\ to hide or show")
        .gesture(WindowDragGesture())
    }

    // MARK: Card

    private var card: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Button(t.rawValue) { tab = t }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(tab == t ? .white.opacity(0.12) : .clear, in: Capsule())
                        .foregroundStyle(tab == t ? .primary : .secondary)
                }
                Spacer()
                if meeting.isRunning {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text("Listening").font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(10)
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())

            Group {
                switch tab {
                case .chat: chat
                case .transcript: TranscriptView(lines: meeting.lines)
                case .history: HistoryView()
                case .settings: SettingsView(stealth: $meeting.stealth)
                }
            }
            .frame(height: height)

            if !meeting.status.isEmpty {
                Text(meeting.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }

            if tab == .chat {
                actions
                input
            }
        }
        // Clear glass looks great right up until there's text behind it. The tint and
        // the shadow are the reading glasses.
        .shadow(color: .black.opacity(0.8), radius: 1.5)
        .glassEffect(.clear.tint(.black.opacity(0.55)), in: RoundedRectangle(cornerRadius: 22))
        .overlay(alignment: .bottomTrailing) { resizeGrip }
    }

    /// Resize by dragging the corner. Borderless windows have no edges to grab, so we
    /// change the SwiftUI size and the window tags along.
    private var resizeGrip: some View {
        Image(systemName: "arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.tertiary)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .gesture(DragGesture(coordinateSpace: .global)
                .onChanged { drag in
                    let start = resizeStart ?? CGSize(width: width, height: height)
                    resizeStart = start
                    width = min(max(start.width + drag.translation.width, 420), 1000)
                    height = min(max(start.height + drag.translation.height, 140), 800)
                }
                .onEnded { _ in resizeStart = nil })
            .pointerStyle(.frameResize(position: .bottomTrailing))
            .padding(4)
    }

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(meeting.messages) { message in
                        MessageView(message: message).id(message.id)
                    }
                }
                .padding(.horizontal, 14)
            }
            .overlay {
                if let problem = meeting.unavailable {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").font(.title2)
                        Text(problem).multilineTextAlignment(.center)
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(URL(filePath: "/System/Applications/System Settings.app"))
                        }
                    }
                    .padding()
                } else if meeting.messages.isEmpty {
                    VStack(spacing: 6) {
                        Text(meeting.isRunning ? "Listening… ask anything about the conversation." : "Press ● to start listening to your meeting.")
                        if let last = meeting.lines.last {
                            Text("\(last.speaker): \(last.text)").lineLimit(2).font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                }
            }
            .onChange(of: meeting.messages.last?.text) {
                if let id = meeting.messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 14) {
            ForEach(Meeting.Action.allCases, id: \.self) { action in
                Button {
                    Task { await meeting.ask(action.prompt, label: action.rawValue) }
                } label: {
                    Label(action.rawValue, systemImage: action.icon)
                }
            }
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
    }

    private var input: some View {
        HStack(spacing: 8) {
            TextField("Ask about the conversation, or ⌘↵ for Assist", text: $question)
                .textFieldStyle(.plain)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(question.isEmpty ? Color.white.opacity(0.15) : Color.accentColor, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(question.isEmpty)
        }
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.1)))
        .padding([.horizontal, .bottom], 12)
    }

    private func send() {
        guard !question.isEmpty else { return }
        let q = question
        question = ""
        Task { await meeting.ask(q) }
    }
}

// MARK: Pieces

struct PillButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(.white.opacity(0.12), in: Capsule())
        }
    }
}

struct MessageView: View {
    let message: Meeting.Message

    var body: some View {
        if message.fromUser {
            Text(message.text)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.accentColor.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            Text(message.text)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TranscriptView: View {
    let lines: [Meeting.Line]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(lines) { line in
                        (Text("\(line.speaker): ").bold().foregroundColor(line.speaker == "You" ? .accentColor : .primary)
                            + Text(line.text))
                            .font(.callout)
                            .textSelection(.enabled)
                            .id(line.id)
                    }
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay {
                if lines.isEmpty { Text("No transcript yet.").foregroundStyle(.secondary) }
            }
            .onChange(of: lines.last?.text) {
                if let id = lines.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }
}

/// History is just the markdown files on disk. No database, no sync, no regrets.
struct HistoryView: View {
    @State private var files: [URL] = []
    @State private var open: URL?

    var body: some View {
        if let open {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button {
                        self.open = nil
                    } label: {
                        Label("History", systemImage: "chevron.left")
                    }
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([open]) }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
                MarkdownView(file: open)
            }
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(files, id: \.self) { file in
                    Button {
                        open = file
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                            Text(file.deletingPathExtension().lastPathComponent)
                            Spacer()
                            Text(Self.preview(file)).lineLimit(1).foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        .padding(8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
        }
        .overlay {
            if files.isEmpty { Text("Meetings you record show up here.").foregroundStyle(.secondary) }
        }
        .onAppear {
            let urls = (try? FileManager.default.contentsOfDirectory(at: Meeting.folder, includingPropertiesForKeys: nil)) ?? []
            files = urls.filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
    }

    /// First line of the summary, because "2026-10-25 17.21" tells you nothing.
    private static func preview(_ file: URL) -> String {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return "" }
        let lines = text.components(separatedBy: "\n")
        guard let i = lines.firstIndex(of: "## Summary") else { return "" }
        return lines.dropFirst(i + 1).first { !$0.isEmpty } ?? ""
    }
}

/// Just enough markdown for the files we write ourselves. Not a markdown engine;
/// please don't feed it your README.
struct MarkdownView: View {
    let file: URL

    var body: some View {
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                    if line.hasPrefix("# ") {
                        Text(line.dropFirst(2)).font(.title3.bold())
                    } else if line.hasPrefix("## ") {
                        Text(line.dropFirst(3)).font(.headline).padding(.top, 8)
                    } else if line.hasPrefix("- [ ] ") {
                        Text(Image(systemName: "square")) + Text(" ") + Text(Self.inline(line.dropFirst(6)))
                    } else if line.hasPrefix("- ") {
                        Text("• ") + Text(Self.inline(line.dropFirst(2)))
                    } else if !line.isEmpty {
                        Text(Self.inline(line))
                    }
                }
            }
            .font(.callout)
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static func inline(_ s: some StringProtocol) -> AttributedString {
        (try? AttributedString(markdown: String(s))) ?? AttributedString(String(s))
    }
}

struct SettingsView: View {
    @Binding var stealth: Bool
    @AppStorage("vocabulary") private var vocabulary = ""

    var body: some View {
        Form {
            Section {
                TextField("Names & terms", text: $vocabulary, prompt: Text("Teammates, products, acronyms"), axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("Names & terms")
            } footer: {
                Text("Comma-separated names and jargon, like colleagues or products. Notes and answers will use these spellings even if the live transcript mishears them.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Hide Sotto from screen sharing", isOn: $stealth)
                Button("Open notes folder") { NSWorkspace.shared.open(Meeting.folder) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
