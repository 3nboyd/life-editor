import SwiftUI
import AppKit

@MainActor final class EditorAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: EditorStore?
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        store?.confirmDiscard() == false ? .terminateCancel : .terminateNow
    }
}

struct WindowGuard: NSViewRepresentable {
    let store: EditorStore
    func makeNSView(context:Context)->GuardView { GuardView(store:store) }
    func updateNSView(_ view:GuardView,context:Context) {}
    @MainActor final class GuardView:NSView,NSWindowDelegate {
        let store:EditorStore
        // AppKit invokes delegate forwarding on the main thread; NSObject declarations are nonisolated.
        nonisolated(unsafe) weak var previousDelegate: (any NSWindowDelegate)?
        init(store:EditorStore){self.store=store;super.init(frame:.zero)}
        required init?(coder:NSCoder){fatalError("init(coder:) unavailable")}
        override func viewDidMoveToWindow(){
            super.viewDidMoveToWindow()
            if let window,window.delegate !== self {previousDelegate=window.delegate;window.delegate=self}
        }
        func windowShouldClose(_ sender:NSWindow)->Bool {store.confirmDiscard()}
        override func responds(to selector:Selector!) -> Bool {
            if super.responds(to:selector) {return true}
            return previousDelegate?.responds(to:selector) ?? false
        }
        override func forwardingTarget(for selector:Selector!) -> Any? {
            previousDelegate?.responds(to:selector) == true ? previousDelegate : super.forwardingTarget(for:selector)
        }
    }
}
