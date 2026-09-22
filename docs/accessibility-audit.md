# iOS accessibility audit

Audited September 22, 2026 against the iOS 17 deployment target.

## Product surface

- **Dynamic Type:** Dashboard and Progress metric grids collapse to one column at accessibility sizes. Pumbility summary metrics stack vertically, catalog copy can grow without one-line clipping, chart grids widen their cells, and judgment grids reduce their column count.
- **VoiceOver:** Icon-only commands have explicit labels. Metric tiles are single semantic elements. Performance rows expose the song as the label and chart, grade, result, score, and date as an ordered value. Chart tokens expand to Single, Double, or Co-op level descriptions. Decorative song artwork is hidden.
- **Touch targets:** Favorite controls and tappable chart badges are at least 44 points tall. Navigation and toolbar controls use system components.
- **Color and contrast:** Failure, recommendation, premium, and score-change states include text or symbols in addition to color. Primary content uses system foreground and background styles so light mode, dark mode, increased contrast, and grayscale do not depend on custom fills.
- **Motion:** The app has no custom motion, parallax, autoplay, or timing-dependent interactions. System navigation and progress indicators inherit Reduce Motion behavior.
- **Loading and errors:** Progress indicators have spoken labels. Empty, signed-out, offline, and error states use `ContentUnavailableView` with a textual action where recovery is possible.
- **Account isolation:** Account-scoped detail and session screens clear stale content before fetching a different account, preventing assistive technology from encountering another account's cached data.

## Release smoke test

Run this matrix on an iPhone and iPad before each TestFlight release:

1. Traverse every tab and detail screen with VoiceOver using swipe navigation and the rotor.
2. Repeat catalog, chart-history, and session flows at Accessibility Extra Extra Extra Large.
3. Verify light, dark, Increase Contrast, Differentiate Without Color, and grayscale appearances.
4. Verify every actionable control with Switch Control and an external keyboard.
5. Enable Reduce Motion and confirm navigation remains understandable with no timing dependency.
