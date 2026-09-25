# Plan: the page under the sidebar and top bar (Safari 26 bleed)

**Goal:** the page's colours bleed live into the sidebar and the top bar, as in
Safari 26 (and like YouTube's ambient mode), while the bars keep the native Mac
material. Page content must never be hidden behind a bar.

**How Safari does it:** the page runs *under* the bars. WebKit is told which
strip is covered, keeps the page's layout clear of it, and fills that strip
with colours continued from the page's edge; the bar's material blurs whatever
is beneath it, live.

Tried and dropped (2026-09-26): tinting the whole bar in the page's
theme-color (it flipped light/dark against the setting), and a sampled glow
(snapshots of the page's edge a few times a second, blurred over the bar — read
as a smear, and wasn't live).

## Current state

- `Sources/mnml/App.swift` → `window_`: a `ZStack`. `stage` (the page) is
  drawn first; `SideBar` and `TabBar` are drawn over it. The page is kept out
  from under them with `.padding(.leading/.top, roomed…)` and
  `.offset(chrome…)`; `room` / `make(room:after:)` resize the page once per
  sidebar show/hide, not every animation frame. A comment there notes the page
  was kept beside the chrome on purpose, to save a compositing pass.
- `Sources/mnml/Design.swift` → `Frosted`: `NSVisualEffectView`, `.sidebar`
  material, `.behindWindow` blending (blurs the desktop only). Used by
  `Side.swift` (column background) and `TabBar.swift` (strip background) when
  `prefs.frostedSidebar` is on (Settings › Tabs › Mac window material).
- `Sources/mnml/Stage.swift` → `StageView` hosts the page's web view and sets
  `wanted.frame = bounds`.

## APIs (checked on macOS 26 / 27)

- `WKWebView.obscuredContentInsets` — **public** on macOS 26+: the area of the
  web view covered by other content.
- `-[WKWebView _setUsesAutomaticContentInsetBackgroundFill:]` — SPI, macOS 26+:
  fills the covered strip with the page's edge colours.
- `_setAutomaticallyAdjustsContentInsets:`, `_setTopContentInset:` also exist.

## Steps

1. **Prove the insets alone.** In a scratch app, a bare `WKWebView` on YouTube:
   set `obscuredContentInsets = NSEdgeInsets(top: 0, left: 220, bottom: 0,
   right: 0)` and turn on the automatic fill. Confirm the page lays out right of
   220 pt and the strip is filled with edge colours. Also try `top`. **If WebKit
   ignores the left inset, stop and report** — only the top bar is possible.
2. **Page under the bars.** In `window_`, drop the leading/top padding that
   keeps the stage beside the column / under the strip, so the page is full
   size; pass the chrome size down to the stage.
3. **Tell WebKit.** Where the web view is hosted, set `obscuredContentInsets`
   to the column width or strip height and turn on the fill; update on resize,
   show/hide, fold. In split view (`SplitStage`) only the leftmost pane gets
   the left inset.
4. **Bars blur the page.** Switch the bars' material to `.withinWindow`
   blending (the page beneath instead of the desktop). Compare with
   `.behindWindow` and choose.
5. **Smooth show/hide.** The page used to be resized once per show/hide
   (`room`). With insets: size the page once and animate only the inset, if
   WebKit animates it smoothly; otherwise set it at the end of the slide.
6. **Things that assume the page starts at the column's edge** — check each:
   - picture-in-picture start/end rectangles (`SystemPiP.swift`: the flipped
     start rect; `StageView.park`)
   - mnml's floating window (`Float.swift`)
   - peek (`Peek.swift`)
   - find bar and link bubble positions
   - the folded / hidden column (`Fold.swift`), which already floats over the page
   - tab hover previews (`TabPreview.swift`, placed from the column's edge)
   - full screen and immersed video (`active.immersed`)
   - `renewGState` position updates (`StageView.placed`)
7. **Setting.** Under the existing Mac window material switch or a separate
   one, on by default. Off must give exactly today's layout.

## Risks

- Sites wider than the window may lay out under the column despite the inset —
  test Google Sheets, YouTube, and a page wider than the window.
- The compositing cost the original author avoided — check 4K YouTube
  scrolling and GPU use in Activity Monitor.
- The fill is SPI; without it the strip shows the page's plain background.

## Working

Experiments build into "mnml Test" (`./build.sh release test`); the main app
is for real work. Commit only once the user has tried it by feel.
