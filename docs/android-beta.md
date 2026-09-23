# Android beta release checklist

MyPIU publishes `com.austinkimchi.mypiu` as an Android App Bundle. Google Play App Signing should own the app signing key, while this repository's protected `android-beta` environment holds a separate upload key used only to authenticate bundles sent to Play.

## One-time Play Console setup

1. Create the Play Console app with package name `com.austinkimchi.mypiu`. The package name becomes fixed after the first artifact upload.
2. Enroll in Play App Signing and use a dedicated upload key rather than the Play-managed app signing key.
3. Create an internal testing track and tester list. Internal testing supports up to 100 invited testers and keeps the app undiscoverable outside its opt-in URL.
4. Add the privacy policy at `https://mypiu.austin.kim/privacy`, support contact, store listing, content rating, target audience, ads declaration, and account-deletion URL.
5. Complete the Data safety inventory from the actual mobile/backend data flow before moving beyond internal testing. Do not infer Play's answers directly from Apple's privacy-manifest categories.

## Protected GitHub environment

Create an `android-beta` environment with deployment reviewers, then add these environment secrets:

| Secret | Value |
| --- | --- |
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | Base64-encoded upload keystore bytes |
| `ANDROID_UPLOAD_STORE_PASSWORD` | Upload keystore password |
| `ANDROID_UPLOAD_KEY_ALIAS` | Upload key alias |
| `ANDROID_UPLOAD_KEY_PASSWORD` | Upload private-key password |
| `ANDROID_UPLOAD_CERT_SHA256` | SHA-256 fingerprint of the upload certificate |

Encode the keystore without line wrapping and read the fingerprint locally:

```bash
base64 -w 0 mypiu-upload.jks
keytool -list -v -keystore mypiu-upload.jks -alias mypiu-upload
```

For a PKCS12 keystore, use the same value for the store and key password secrets; PKCS12 does not support a distinct key password. A JKS keystore may use separate values.

Keep the original keystore and passwords in an independent secure backup. Never commit a keystore or put the Play-managed app signing key in GitHub.

## Build and upload

1. Run the **Android beta bundle** workflow from the Actions page.
2. Enter a semantic `version_name` and a `version_code` greater than every code previously uploaded to Play but no greater than Play's `2100000000` limit.
3. Approve the protected environment deployment.
4. Download and extract the `mypiu-android-beta-<version>-<code>` artifact, then run `sha256sum -c app-release.aab.sha256` in the extracted directory.
5. Upload `app-release.aab` to the Play internal testing track, add release notes, review the generated device support, and roll out to internal testers.

The workflow validates the pinned upload certificate, runs unit tests and release lint, builds an upload-key-signed AAB, verifies its JAR signature, and retains only the signed bundle plus checksum. It does not automate a Play rollout, so the first release and each tester expansion remain visible operator decisions.

## Beta qualification

Before widening the tester group:

- Install from Google Play on a physical phone and tablet rather than sideloading the CI debug APK.
- Complete the Android matrix in `accessibility-audit.md`, including font scaling and TalkBack.
- Exercise Google and Discord sign-in, PIUGAME connection, foreground sync, background refresh, offline catalog recovery, sign-out, token revocation, and account deletion.
- Confirm the installed package receives an update from the next internal-track bundle without losing encrypted local state.
- Review Play pre-launch reports and resolve crashes, ANRs, accessibility warnings, and policy blockers.
