# Distributing Paper Library for macOS

The app is a native SwiftUI macOS application. It creates and manages its own data under `~/Library/Application Support/Paper Library`; users do not choose or download a library folder.

The app also advertises a PDF-only macOS Service named **Move to Paper Library**. Finder shows it under **Services** after the app has been launched once. If macOS hides it, enable it in **System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders**. Invoking the service silently moves selected PDFs into the app-managed `Waiting` directory; it does not copy or overwrite them. The same action starts one detached organizer run, which drains the queue and exits. No persistent folder watcher or LaunchAgent is installed.

Sparkle provides in-app updates through the HTTPS appcast at `appcast.xml`. The app checks on Sparkle's normal schedule and exposes **Paper Library → Check for Updates…**. **Version History** opens the repository's GitHub Releases page. Finder Service launches do not start the updater.

## Requirements

- Free build: macOS 14 or later and the Xcode Command Line Tools
- Notarized build: full Xcode, an Apple Developer Program membership, a unique bundle identifier, and a Developer ID Application certificate

## Free, unnotarized build

Open `PaperLibrary.xcodeproj`, select the `PaperLibrary` scheme, choose **My Mac**, and run. On first launch, confirm the app creates `Waiting`, `Papers`, `Catalog`, and `Automation` in its Application Support directory.

Without full Xcode or a paid Apple Developer membership, build and package an ad-hoc signed Apple Silicon app with:

```sh
scripts/build-local-app.sh
```

This normally creates `dist/Paper Library.app` and `dist/Paper-Library.zip`. The app is signed and verified in a temporary staging directory before both outputs are copied into the repository. If the destination attaches metadata that invalidates the loose signed bundle, the script removes that copy and keeps only the verified ZIP.

This build can be attached to a GitHub Release, but it is not checked or notarized by Apple. State that limitation clearly in the GitHub Release description. After the first blocked launch, users must open **System Settings → Privacy & Security** and choose **Open Anyway**. Upload the ZIP, not the loose `.app` directory.

The first release that includes Sparkle must still be downloaded manually by existing users. Later releases can be installed inside the app.

## Free release updates

Update archives and the appcast are authenticated with a Sparkle EdDSA key, independently of Apple's paid Developer ID program. The public key is embedded in `PaperLibrary/Info.plist`. The matching private key must never be committed or attached to a release.

On the release Mac, the key is stored in the login Keychain under the Sparkle account `hoonably.paper-library`. The local release script reads its exported copy from:

```text
~/Library/Application Support/Paper Library Development/sparkle-private-key
```

Keep an additional secure backup. Without this key, free builds already installed by users cannot trust a replacement key automatically.

After setting the release version and build number, run the release checks, build the ZIP, and prepare the update feed with one command:

```sh
scripts/prepare-release.sh
```

Write release notes directly in the GitHub Release description. Start with the changes themselves; do not repeat the release name or version as a heading inside the description. Do not create or upload a separate Markdown asset. The appcast points **Version History** to `https://github.com/hoonably/paper-library/releases`.

The release preparation verifies that the local signing key matches the public key embedded in the app, signs `dist/Paper-Library.zip`, and updates the repository's `appcast.xml`. Commit the version changes and generated appcast together, push the commit and tag, then upload that exact ZIP as the only asset named `Paper-Library.zip` to the matching `v<version>` GitHub Release. Do not edit the generated appcast or replace the ZIP afterward.

To sign on another Mac, transfer the private-key backup securely and either place it at the path above or provide its path only for the release command:

```sh
SPARKLE_PRIVATE_KEY_FILE='/secure/path/sparkle-private-key' scripts/generate-appcast.sh
```

## Version policy

- Do not change the app version for ordinary feature or bug-fix commits.
- Change it only when the user explicitly decides to create a new release.
- Keep early testing releases below `1.0.0`; use `1.0.0` only after the app has been sufficiently tested.
- Keep `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, and the defaults in `scripts/build-local-app.sh` synchronized.
- Generate and commit `appcast.xml` only as part of a release.

## Release archive

1. In the target's **Signing & Capabilities**, select the Apple Developer team and replace `com.hoonably.PaperLibrary` if necessary.
2. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the target settings.
3. Select **Any Mac (Apple Silicon, Intel)** and choose **Product → Archive** in Xcode.
4. In Organizer, choose **Distribute App → Developer ID → Upload** to sign and submit the app for notarization.
5. After notarization succeeds, export the app and staple the ticket:

   ```sh
   xcrun stapler staple '/path/to/Paper Library.app'
   ```

6. Run the repository's release verifier. It rejects ad-hoc or Apple Development signatures, missing bundled automation resources, unstapled apps, non-universal executables, unresolved version fields, and accidentally packaged private catalog data:

   ```sh
   scripts/verify-release-app.sh '/path/to/Paper Library.app'
   ```

7. Only after that succeeds, create the GitHub Release ZIP:

   ```sh
   ditto -c -k --sequesterRsrc --keepParent \
     '/path/to/Paper Library.app' Paper-Library.zip
   ```

The Developer ID workflow below avoids the security override and remains the preferred option for wider distribution.

Do not enable App Sandbox for this architecture. The on-demand organizer and the app intentionally share the Application Support library.

## Release checks

- Run `swift build`.
- Run `scripts/run-core-checks.sh`.
- Confirm **Paper Library → Check for Updates…** is enabled in a packaged app.
- Confirm **Version History** opens `https://github.com/hoonably/paper-library/releases` in the default browser.
- Test a fresh first launch, relaunching, search/filter/sort, editing a row, opening a PDF, and moving a disposable test PDF to the Trash.
- Confirm **Set Up Automation** configures on-demand execution without installing a LaunchAgent, and that the header remains **Ready for Finder** while idle. Then change model/reasoning/language and verify `Catalog/organizer-settings.json` updates without losing `automationDevice`.
- From Finder, invoke **Move to Paper Library** on a disposable PDF and confirm the source disappears, the app window stays closed, an organizer process starts, and the process exits after the PDF leaves `Waiting`.
- Verify the exported app with `codesign --verify --deep --strict --verbose=2`.
- Confirm the app contains `Contents/Frameworks/Sparkle.framework`, and that `SUFeedURL` and `SUPublicEDKey` are present in its Info.plist.
- Verify the executable contains both `arm64` and `x86_64` architectures.
- Run `scripts/verify-release-app.sh` and upload only the ZIP made from that verified app.
- Test the notarized artifact on a Mac that does not have a development certificate installed.
