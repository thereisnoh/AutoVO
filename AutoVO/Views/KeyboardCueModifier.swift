import SwiftUI
import AppKit

/// Installs a local key monitor for live cue control while it is in the view tree
/// (Show Mode only). It is removed automatically when the view disappears, so
/// Space/arrows behave normally back in Edit Mode.
///
/// Space / Return / keypad-Enter = GO, Esc = STOP, ↑ = arm previous, ↓ = arm next.
struct CueKeyboardCatcher: NSViewRepresentable {
    var onGo: () -> Void
    var onStop: () -> Void
    var onArmNext: () -> Void
    var onArmPrevious: () -> Void

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.callbacks = (onGo, onStop, onArmNext, onArmPrevious)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(callbacks: (onGo, onStop, onArmNext, onArmPrevious))
    }

    final class Coordinator {
        typealias Callbacks = (go: () -> Void, stop: () -> Void, next: () -> Void, prev: () -> Void)
        var callbacks: Callbacks
        private var monitor: Any?

        init(callbacks: Callbacks) {
            self.callbacks = callbacks
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                // Never hijack keys while an editable text view has focus.
                if event.window?.firstResponder is NSTextView { return event }
                switch event.keyCode {
                case 49, 36, 76: self.callbacks.go(); return nil      // space, return, keypad enter
                case 53:         self.callbacks.stop(); return nil     // escape
                case 126:        self.callbacks.prev(); return nil     // up arrow
                case 125:        self.callbacks.next(); return nil     // down arrow
                default:         return event
                }
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
