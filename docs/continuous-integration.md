# Continuous integration

Ordinary CI runs for pull requests and pushes to `main` when the changed paths affect the workflow. Markdown-only changes, including README updates, do not start the native builds or extension packaging.

| Workflow | Relevant inputs | Job limit | Artifact retention |
| --- | --- | --- | --- |
| iOS | `ios/`, shared `browser-extension/`, iOS helper scripts, App Store Connect key helper, iOS workflow files | 45 minutes | 7 days |
| Android | `android/`, Android workflow files | 30 minutes | 7 days |
| Browser extension | `browser-extension/`, browser-extension workflow files | 10 minutes | 7 days |
| Safari extension | `browser-extension/`, macOS Safari generator, Safari workflow | 30 minutes | 7 days |

The path filters include source, fixtures, manifests, lockfiles, build configuration, generated Xcode files, and executable packaging scripts. Shared extension changes still run iOS, Safari, and Chromium validation because iOS and Safari embed that runtime. App Store listing text under `ios/AppStore/` also triggers iOS metadata validation. Markdown exclusions apply after those input patterns.

Each ordinary workflow cancels older runs of that same workflow on the same Git ref. Separate PRs and workflows do not cancel each other. Timeouts bound stuck jobs without changing runner types or removing test/archive checks.

The manually dispatched iOS signed release and Android beta workflows, and the tag-triggered browser release workflow, retain their existing triggers, environments, signing behavior, and artifact retention. Ordinary CI never changes account billing limits.

## Updating the filters

When adding a shared input or moving a build script, update both `push.paths` and `pull_request.paths` in every workflow that consumes it. Keep the negative Markdown pattern last. Check representative cases before committing:

- Root or platform README changes: no ordinary build workflows.
- iOS Swift/plist/project or iOS helper changes: iOS.
- Android source/Gradle changes: Android.
- Shared extension source, manifest, lockfile, or tests: iOS, Safari, and Browser extension.
- macOS Safari generator changes: Safari.
- A workflow's own YAML change: that workflow.

[GitHub documents](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onpushpull_requestpull_request_targetpathspaths-ignore) that path-skipped workflows do not report a successful required check. Before adding branch protection that requires these jobs for every PR, use an always-running lightweight gate with conditional build jobs instead of requiring a path-filtered workflow. GitHub also limits changed-file evaluation for large diffs; keep changes focused and inspect workflow runs on large refactors.
