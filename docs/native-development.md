# Native development loop

MyPIU uses SwiftUI and Jetpack Compose. Vite does not rebuild these native apps. Reuse one checkout, one existing Simulator/emulator, and incremental Debug build outputs for ordinary edits. Release archives and the full CI suite remain release checks.

## iOS after a pull or Swift edit

With Xcode and Node.js available, run from the repository root:

```sh
# First review local changes; pull only a clean development checkout.
git status --short
git pull --ff-only
./scripts/dev-ios.sh check
./scripts/dev-ios.sh build
```

The helper uses the checked-in `ios/MyPIU.xcodeproj`, shared `MyPIU` scheme, Debug configuration, two build jobs, and `.build/ios-dev` for DerivedData. It selects an existing, available iPhone Simulator, preferring a booted iPhone; an existing iPad is a fallback. Pin a destination when several are installed:

```sh
xcrun simctl list devices available
./scripts/dev-ios.sh check YOUR_EXISTING_SIMULATOR_UDID
./scripts/dev-ios.sh build YOUR_EXISTING_SIMULATOR_UDID
```

`check` inspects the destination and storage without building. `build` compiles only; it does not boot a Simulator, install or launch the app, download a runtime, alter signing settings, or change API endpoints. It disables signing for this command, so its output is a compile check, not a device distribution artifact. The first build can fetch the project's pinned Swift package dependency. Later builds reuse package and compiler outputs in the same directory.

For interactive testing, open `ios/MyPIU.xcodeproj`, choose `MyPIU` and an existing Simulator, then use **Run (⌘R)** yourself. Xcode's normal incremental Run keeps its own DerivedData unless configured otherwise. Do not run two builds against the same DerivedData directory simultaneously. A Git pull still requires a build/Run to update an installed app; there is no automatic app replacement.

Do not regenerate the project or clean the build on every edit. Run `./scripts/generate-ios-project.sh` when changing `ios/project.yml` or shared Safari extension sources/dependencies, and inspect the generated diff. It rewrites the Xcode project, so preserve any local signing edits first. Ordinary Swift changes to files already in the project need only an incremental build. New files must be included in the generated project.

For isolated SwiftUI components, use Xcode's Canvas/Live mode. Open `ios/MyPIU/Features/Songs/SongsView.swift` to select **Songs - Light** or **Songs - Dark, large text**. These Debug-only `#Preview` variants render the real catalog header and rows with synthetic songs and placeholder artwork; they do not instantiate account models or request images. Edit those components to inspect layout changes without signing in or loading the catalog. The dark variant includes the saved-data indicator and accessibility text size.

Keep real account restoration, sync, and network calls out of additional preview fixtures. Full-screen navigation and loading behavior still require app testing. See [Apple's preview workflow](https://developer.apple.com/documentation/xcode/interacting-with-previews-in-the-canvas).

## Explicit iOS cache cleanup

The helper retains one ignored cache directory. It refuses to start when that directory is at least **2 GiB**, or when the volume has less than **5 GiB** free. The size check runs between builds: a build can temporarily exceed the budget, and these checks are not a disk quota or a guarantee against other processes using storage. An over-budget completed build prints a warning; the next build requires cleanup.

After stopping all builds using this directory, inspect and remove only this helper's generated files from the repository root:

```sh
du -sh .build/ios-dev
rm -rf -- .build/ios-dev
```

This discards incremental outputs; the next build is cold. It leaves source files, Xcode's other DerivedData, installed runtimes, and Simulator/app data intact. The helper never deletes caches automatically. Remove this directory when retiring a development worktree rather than retaining a copy per branch.

## Android incremental iteration

With the [Android prerequisites](../android/README.md) installed, reuse the same checkout and Gradle daemon:

```sh
cd android
./gradlew :app:assembleDebug --build-cache
# Run focused validation when relevant code changes:
./gradlew :app:testDebugUnitTest :app:lintDebug
```

The project already enables Gradle's configuration cache and parallel execution. Avoid `clean` between ordinary edits. In Android Studio, use an existing device/emulator and Debug build. Compose **Live Edit** supports eligible function-body changes after an initial Run; structural/signature changes still need Run. Live Edit requires an API 30+ device and compatible Studio/Compose/AGP versions. It can reset UI state, so do not treat it as a performance measurement. See [Compose iterative development](https://developer.android.com/develop/ui/compose/tooling/iterative-development).

For changes outside Live Edit, Android Studio offers **Apply Changes** for supported Debug changes on API 26+; some changes require restarting the activity or app. Live Edit and Apply Changes are separate workflows; follow Studio's restart prompt when switching. See [Run and Apply Changes](https://developer.android.com/studio/run/).

For deliberate local cleanup, stop Studio builds, run `./gradlew --stop`, then `./gradlew clean` to remove project build outputs. This loses incremental benefit. Do not remove the shared `~/.gradle` cache or emulator data as part of routine iteration. No Android tools or runtimes are installed by the iOS helper.

## API environments

These commands keep the existing production API configuration. There is no supported staging selector yet. A staging app needs coordinated URL resolution, separate credentials/cache namespaces, and an OAuth callback/client arrangement; changing only one base URL can mix production tokens, images, or cached data with staging. Set up isolated staging API/data before adding that option.
