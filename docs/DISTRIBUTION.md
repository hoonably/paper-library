# Distributing Paper Library for macOS

The app is a native SwiftUI macOS application. It creates and manages its own data under `~/Library/Application Support/Paper Library`; users do not choose or download a library folder.

The app also advertises a PDF-only macOS Service named **Move to Paper Library**. Finder shows it under **Services** after the app has been launched once. If macOS hides it, enable it in **System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders**. Invoking the service silently moves selected PDFs into the app-managed `Waiting` directory; it does not copy or overwrite them.

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

This build can be attached to a GitHub Release, but it is not checked or notarized by Apple. State that limitation clearly in the release notes. After the first blocked launch, users must open **System Settings → Privacy & Security** and choose **Open Anyway**. Upload the ZIP, not the loose `.app` directory.

## Version policy

- Do not change the app version for ordinary feature or bug-fix commits.
- Change it only when the user explicitly decides to create a new release.
- Keep early testing releases below `1.0.0`; use `1.0.0` only after the app has been sufficiently tested.
- Keep `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, and the defaults in `scripts/build-local-app.sh` synchronized.

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

Do not enable App Sandbox for this architecture. The background organizer and the app intentionally share the Application Support library.

## Release checks

- Run `swift build`.
- Run `scripts/run-core-checks.sh`.
- Test a fresh first launch, relaunching, search/filter/sort, editing a row, opening a PDF, and moving a disposable test PDF to the Trash.
- Confirm **Set Up Automation** installs the watcher and the header updates, then change model/reasoning/language and verify `Catalog/organizer-settings.json` updates without losing `automationDevice`.
- From Finder, invoke **Move to Paper Library** on a disposable PDF and confirm the source disappears, the app window stays closed, and the PDF appears in `Waiting`.
- Verify the exported app with `codesign --verify --deep --strict --verbose=2`.
- Verify the executable contains both `arm64` and `x86_64` architectures.
- Run `scripts/verify-release-app.sh` and upload only the ZIP made from that verified app.
- Test the notarized artifact on a Mac that does not have a development certificate installed.
