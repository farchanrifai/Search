import OSLog
import WebKit

// A video into macOS's own picture-in-picture, the way Safari puts one there
// when you leave its tab: the video slides out of the page into the system's
// window and back again, and the page itself is never touched. Asked of
// WebKit from the app's side — the page's own requestPictureInPicture needs a
// click on it, this doesn't. Where WebKit can't (no video it is tracking, or
// a macOS without the call), mnml's own floating window (Float.swift) is used.

enum SystemPiP {
    private static let can = NSSelectorFromString("_canTogglePictureInPicture")
    private static let toggle = NSSelectorFromString("_togglePictureInPicture")
    private static let active = NSSelectorFromString("_isPictureInPictureActive")
    private static let playing = NSSelectorFromString("_hasActiveVideoForControlsManager")

    private static func ask(_ web: WKWebView, _ selector: Selector) -> Bool {
        guard web.responds(to: selector) else { return false }
        return (web.value(forKey: NSStringFromSelector(selector)) as? Bool) == true
    }

    static func isActive(_ web: WKWebView) -> Bool { ask(web, active) }

    /// WebKit only works out which video it could hand to picture-in-picture
    /// when asked to look — until then it says it can't, and leaving the tab
    /// fell back to mnml's own window. Asked as a video starts playing, and
    /// again a moment later, once the player has settled on its element.
    static func prepare(_ web: WKWebView) {
        watch()
        let refresh = NSSelectorFromString("_updateMediaPlaybackControlsManager")
        guard web.responds(to: refresh) else { return }
        web.perform(refresh)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak web] in web?.perform(refresh) }
    }

    /// Which path each video took, for when one misbehaves.
    static let log = Logger(subsystem: "com.farchan.mnml", category: "PiP")

    /// Out into the system's window, if a video is playing and WebKit can.
    /// Already out — started from the video's own menu — counts as done: a
    /// second, mnml's own, window beside it showed only "playing in
    /// picture in picture".
    static func enter(_ web: WKWebView) -> Bool {
        watch()
        if isActive(web) { return true }
        // Where the video is, looked at again first: picture-in-picture
        // starts its flight from WebKit's note of it (see StageView.layout).
        web.renewGState()
        guard web.responds(to: toggle), ask(web, can), ask(web, playing) else {
            log.notice("float: mnml's window (can=\(ask(web, can)), playing=\(ask(web, playing)))")
            // Next time, it will know.
            prepare(web)
            return false
        }
        web.perform(toggle)
        return true
    }

    /// Back into the page, if it is still out.
    static func exit(_ web: WKWebView) {
        guard web.responds(to: toggle), isActive(web) else { return }
        web.perform(toggle)
    }
}

// MARK: - two corrections to WebKit's side of it

extension SystemPiP {
    /// Where the video flies out from, measured the way mnml's window
    /// counts, and the return button bringing its tab forward. Installed
    /// once, on WebKit's own picture-in-picture class.
    static func watch() {
        guard !watching, let cls = NSClassFromString("WebVideoPresentationInterfaceMacObjC") else { return }
        watching = true

        let setUp = NSSelectorFromString("setUpPIPForVideoView:withFrame:inWindow:")
        if let method = class_getInstanceMethod(cls, setUp) {
            typealias Fn = @convention(c) (AnyObject, Selector, NSView, NSRect, NSWindow?) -> Void
            let original = unsafeBitCast(method_getImplementation(method), to: Fn.self)
            let block: @convention(block) (AnyObject, NSView, NSRect, NSWindow?) -> Void = { this, view, frame, window in
                // WebKit measures from the window's bottom, as AppKit does,
                // and puts the video's container in the window's content view
                // at that rectangle to fly it from. mnml's content view is
                // SwiftUI's, which counts from the top: the flight started as
                // far up from the bottom as the video is down from the top.
                var start = frame
                if let content = window?.contentView, content.isFlipped {
                    start.origin.y = content.bounds.height - frame.maxY
                }
                original(this, setUp, view, start, window)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }

        // The window's return button: WebKit puts the video back in its page,
        // and that is all — from another app, nothing came forward to show
        // it. Browser answers by bringing its window and the tab forward.
        let back = NSSelectorFromString("pipShouldClose:")
        if let method = class_getInstanceMethod(cls, back) {
            typealias Fn = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
            let original = unsafeBitCast(method_getImplementation(method), to: Fn.self)
            let block: @convention(block) (AnyObject, AnyObject) -> Bool = { this, pip in
                let answer = original(this, back, pip)
                DispatchQueue.main.async { NotificationCenter.default.post(name: SystemPiP.returned, object: nil) }
                return answer
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
    }

    private static var watching = false

    /// The return button was pressed on the system's window.
    static let returned = Notification.Name("mnml.pip.returned")
}
