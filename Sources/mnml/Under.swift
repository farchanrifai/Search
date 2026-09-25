import AppKit
import WebKit

// The page under the column and the strip, as Safari 26 has it: the page is
// laid out the full size of the window, WebKit is told which strip of it the
// chrome covers, keeps the page's content clear of that strip and fills it
// with colours carried on from the page's edge, and the chrome's material
// blurs whatever is beneath it — the page, live, as it scrolls and plays.
// See docs/mnml/page-under-chrome.md.
//
// Off unless asked for (Settings › Tabs). Off, or on a Mac whose WebKit
// can't be told, the page sits beside the chrome as it always has.

enum Under {
    private static let insetsSetter = NSSelectorFromString("setObscuredContentInsets:")
    private static let insetsGetter = NSSelectorFromString("obscuredContentInsets")
    private static let fill = NSSelectorFromString("_setUsesAutomaticContentInsetBackgroundFill:")

    /// This WebKit can keep a page clear of a covered strip: macOS 26 and
    /// on. Asked by name, so mnml builds with an SDK that doesn't know it.
    static let possible = WKWebView.instancesRespond(to: insetsSetter)
        && WKWebView.instancesRespond(to: insetsGetter)

    /// Tells a page how much of it is covered, and to fill that much with
    /// its own edge colours. Only when it changes: every new value lays the
    /// page out again.
    static func cover(_ web: WKWebView, _ insets: NSEdgeInsets) {
        guard possible, !same(covered(web), insets) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, NSEdgeInsets) -> Void
        unsafeBitCast(web.method(for: insetsSetter), to: Setter.self)(web, insetsSetter, insets)
        // Without the fill the covered strip is the page's plain background
        // — still right, only flatter.
        if web.responds(to: fill) {
            typealias Fill = @convention(c) (AnyObject, Selector, Bool) -> Void
            unsafeBitCast(web.method(for: fill), to: Fill.self)(web, fill, insets.left > 0 || insets.top > 0)
        }
    }

    /// How much of a page is covered: none, unless it has been told.
    static func covered(_ page: NSView) -> NSEdgeInsets {
        guard possible, let web = page as? WKWebView else { return NSEdgeInsets() }
        typealias Getter = @convention(c) (AnyObject, Selector) -> NSEdgeInsets
        return unsafeBitCast(web.method(for: insetsGetter), to: Getter.self)(web, insetsGetter)
    }

    /// A page leaving for somewhere nothing covers it — the floating window.
    /// Says how much was covered, so the page can keep the width it had.
    @discardableResult
    static func clear(_ page: NSView) -> NSEdgeInsets {
        let was = covered(page)
        if let web = page as? WKWebView { cover(web, NSEdgeInsets()) }
        return was
    }

    /// Over the page, the chrome's material blurs the page; the desktop
    /// behind the window is what it blurs otherwise. For trying the two side
    /// by side, a test build can be told to keep the desktop:
    ///   defaults write com.farchan.mnml.test under.behindWindow -bool YES
    static var blending: NSVisualEffectView.BlendingMode {
        Store.settings.bool(forKey: "under.behindWindow") ? .behindWindow : .withinWindow
    }

    private static func same(_ a: NSEdgeInsets, _ b: NSEdgeInsets) -> Bool {
        a.top == b.top && a.left == b.left && a.bottom == b.bottom && a.right == b.right
    }
}

extension Browser {
    /// The page runs under the column and the strip right now. Only with
    /// the see-through material — under a flat colour there'd be nothing to
    /// see — and not for a split, whose pages sit on cards with a margin of
    /// their own and never meet the chrome's edge.
    var pageUnder: Bool {
        prefs.pageUnder && prefs.frostedSidebar && Under.possible
            && shownSplit == nil && splitPicking == nil
    }
}
