# Accessibility audit

## iOS

Audited September 22, 2026 against the iOS 17 deployment target.

## Product surface

- **Dynamic Type:** Dashboard and Progress metric grids collapse to one column at accessibility sizes. Pumbility summary metrics stack vertically, catalog copy can grow without one-line clipping, chart grids widen their cells, and judgment grids reduce their column count.
- **VoiceOver:** Icon-only commands have explicit labels. Metric tiles are single semantic elements. Performance rows expose the song as the label and chart, grade, result, score, and date as an ordered value. Chart tokens expand to Single, Double, or Co-op level descriptions. Decorative song artwork is hidden.
- **Touch targets:** Favorite controls and tappable chart badges are at least 44 points tall. Navigation and toolbar controls use system components.
- **Color and contrast:** Failure, recommendation, premium, and score-change states include text or symbols in addition to color. Primary content uses system foreground and background styles so light mode, dark mode, increased contrast, and grayscale do not depend on custom fills.
- **Motion:** The app has no custom motion, parallax, autoplay, or timing-dependent interactions. System navigation and progress indicators inherit Reduce Motion behavior.
- **Loading and errors:** Progress indicators have spoken labels. Empty, signed-out, offline, and error states use `ContentUnavailableView` with a textual action where recovery is possible.
- **Account isolation:** Account-scoped detail and session screens clear stale content before fetching a different account, preventing assistive technology from encountering another account's cached data.

### Release smoke test

Run this matrix on an iPhone and iPad before each TestFlight release:

1. Traverse every tab and detail screen with VoiceOver using swipe navigation and the rotor.
2. Repeat catalog, chart-history, and session flows at Accessibility Extra Extra Extra Large.
3. Verify light, dark, Increase Contrast, Differentiate Without Color, and grayscale appearances.
4. Verify every actionable control with Switch Control and an external keyboard.
5. Enable Reduce Motion and confirm navigation remains understandable with no timing dependency.

## Android

Audited September 22, 2026 against the Android 26 minimum and Android 37 target.

- **Scalable text:** Home summary metrics stack at accessibility font scales. Progress grids already collapse to one column, song titles can wrap, and chart/judgment collections use flow layouts instead of fixed columns.
- **TalkBack:** Icon-only commands have explicit labels. Decorative icons and artwork are hidden. Performance, session, Pumbility, and attempt rows expose one ordered announcement instead of a cluster of child nodes. Chart tokens expand to Single, Double, or Co-op level descriptions, recommended charts expose a spoken state, and favorite controls retain their action label while an update is running.
- **Touch targets:** Navigation, toolbar, favorite, segmented, and command controls use Material components. Custom chart buttons have an explicit 48 dp height and display-only chart tokens do not expose a disabled button action.
- **Color and contrast:** Failed plays include `FAILED`, score improvements include a plus value, premium songs use a trophy, favorites change shape, and recommended charts use a star in addition to color. Theme foreground/background pairs come from Material light and dark color schemes.
- **Motion:** The Android app has no custom motion, parallax, autoplay, or timing-dependent gesture. Material navigation and loading indicators inherit platform animation-scale behavior.
- **Loading and errors:** Loading states include adjacent spoken text. Empty, signed-out, offline, and error states provide text and a labeled recovery action where possible.
- **Account isolation:** Account changes clear private catalog, performance, chart-history, and session state before replacement requests can publish results.

The checked-in gate runs Android lint and unit coverage for spoken chart labels and failed-play classification. Android's automated accessibility checks and Accessibility Scanner require a running emulator or device, so they remain part of release smoke testing rather than being represented as completed in this environment.

### Release smoke test

Run this matrix on a phone, tablet, and resizable emulator before each Android beta:

1. Traverse every navigation destination and detail screen with TalkBack using swipe navigation and Explore by Touch.
2. Run Compose UI Check and Accessibility Scanner on Home, Progress, Activity, Songs, song detail, chart history, and recent session.
3. Repeat catalog, chart-history, favorite, and session flows at the largest system font and display sizes.
4. Verify light, dark, high-contrast text, color correction, and grayscale appearances.
5. Verify every actionable control with Switch Access, a keyboard, and a D-pad.
6. Disable animations and confirm loading, navigation, and state changes remain understandable.
