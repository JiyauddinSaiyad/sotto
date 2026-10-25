import AppKit
import Carbon.HIToolbox
import SwiftUI

extension Notification.Name {
    static let toggleCard = Notification.Name("sotto.toggleCard")
    static let assist = Notification.Name("sotto.assist")
}

/// Global hotkeys. Carbon, yes, in this year of our Lord. It's still the only
/// API that hears a keypress while Zoom owns the keyboard.
enum HotKeys {
    private static var refs: [UInt32: EventHotKeyRef] = [:]

    static func install() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            NotificationCenter.default.post(name: id.id == 1 ? .toggleCard : .assist, object: nil)
            return noErr
        }, 1, &spec, nil, nil)
        register(1, key: kVK_ANSI_Backslash) // ⌘\ peekaboo
    }

    /// ⌘↵ is borrowed, not stolen: claimed when a meeting starts, handed back to
    /// Slack and friends when it ends.
    static func setAssist(_ on: Bool) {
        if on { register(2, key: kVK_Return) } else if let ref = refs.removeValue(forKey: 2) { UnregisterEventHotKey(ref) }
    }

    private static func register(_ id: UInt32, key: Int) {
        guard refs[id] == nil else { return }
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(key), UInt32(cmdKey), EventHotKeyID(signature: OSType(0x534F5454), id: id), GetApplicationEventTarget(), 0, &ref)
        refs[id] = ref
    }
}

/// Floats over everything, follows you across Spaces, and never steals focus.
/// A good houseguest.
final class Panel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        // SwiftUI decides the size. AppKit just holds the frame and nods.
        contentViewController = NSHostingController(rootView: ContentView())
    }

    override var canBecomeKey: Bool { true }

    /// AppKit grows windows from the bottom-left, because 1989. Pin the top so the
    /// pill stays put when the card folds away.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var rect = frameRect
        if frame.height > 0, rect.height != frame.height { rect.origin.y = frame.maxY - rect.height }
        super.setFrame(rect, display: flag)
    }
}

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: Panel?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = Panel()
        panel.setContentSize(panel.contentViewController!.view.fittingSize)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.visibleFrame {
            // NSScreen.main is "the screen with focus", not the one you're looking at.
            // Follow the mouse; it knows.
            panel.setFrameTopLeftPoint(NSPoint(x: screen.midX - panel.frame.width / 2, y: screen.maxY - 8))
        }
        panel.orderFrontRegardless()
        HotKeys.install()
        self.panel = panel
    }
}
