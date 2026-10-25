# Releasing Daymark

Daymark is published from GitHub Actions. Every tagged release builds and
uploads real artifacts for Linux, Windows, Android, iOS, and macOS. There is no
manual "build on my laptop and hope" step.

## Trigger a release

1. Update `version:` in `pubspec.yaml` (for example `1.2.0+3`).
2. Move the relevant entries in `CHANGELOG.md` from `[Unreleased]` to the new
   version.
3. Commit and push to `main`.
4. Create and push an annotated tag:

   ```bash
   git tag -a v1.2.0 -m "Daymark 1.2.0"
   git push origin main --follow-tags
   ```

The **Build & Release** workflow in `.github/workflows/ci.yml` then runs:

| Job | Runner | Output |
| --- | --- | --- |
| `quality` | Ubuntu | Format check, analyzer, all tests |
| `linux` | Ubuntu | `Daymark-<version>-linux-x64.tar.gz`, `Daymark-<version>-linux-amd64.deb` |
| `windows` | Windows | `Daymark-<version>-windows-x64.zip` |
| `android` | Ubuntu | `Daymark-<version>-android.apk`, `Daymark-<version>-android.aab` |
| `ios` | macOS | `Daymark-<version>-ios-unsigned.ipa` |
| `macos` | macOS | `Daymark-<version>-macos-<arch>.dmg` and `.zip` |
| `release` | Ubuntu | All of the above plus `SHA256SUMS.txt` on the GitHub Release |

Pushes to `main` run the same build jobs and keep the artifacts on the workflow
run for 14 days. Pull requests run only `quality`, so a pull request cannot
publish a release.

You can also start a build manually from **Actions → Build & Release → Run
workflow**. Manual runs produce artifacts but do not create a GitHub Release.

## Google sign-in for official builds

Official Daymark builds can show **Continue with Google** instead of guided
OAuth setup. Add these repository secrets before building:

| Secret | Value |
| --- | --- |
| `GOOGLE_OAUTH_CLIENT_ID` | Google Cloud **Desktop app** OAuth client ID |
| `GOOGLE_OAUTH_CLIENT_SECRET` | Matching desktop client secret |

Every quality and build job runs `tool/configure_google_oauth.dart`, which writes
those values into `assets/config/google_oauth.json` before the Flutter build.
The asset is bundled into the application. When the secrets are absent, the
script writes an empty client and the app falls back to guided setup.

Create the OAuth client in the [Google Cloud Console](https://console.cloud.google.com/apis/credentials):

1. Enable the **Google Drive API**.
2. Configure the OAuth consent screen. Add test users while the app is in
   testing, or complete Google's verification for public distribution.
3. Create an OAuth client of type **Desktop app**.
4. Copy its client ID and secret into the GitHub secrets above.

Desktop client secrets are not confidential in the same way as server secrets;
Google expects them to ship with installed apps. They are still supplied through
CI rather than hard-coded in the repository. Google's consent-screen and
verification requirements are outside the workflow's control.

## Android release signing

The repository does not contain a keystore. Add these repository secrets to
produce a production-signed APK and AAB:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 daymark-release.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias, for example `daymark` |
| `ANDROID_KEY_PASSWORD` | Key password |

The workflow writes the keystore to `android/app/daymark-release.jks` and a
temporary `android/key.properties`, both ignored by git. It then verifies the
APK and prints its certificate.

Without those secrets the build still succeeds, but Gradle falls back to the
debug signing key. Those artifacts are for testing and sideloading, not for
Google Play.

To publish to Google Play, upload the generated `.aab` to the Play Console or
add a Play Developer API service-account step to the workflow. Daymark does not
ship Play credentials and will not publish to a store without them.

## Apple signing

The iOS IPA is built with `--no-codesign` because Apple requires a paid
developer account, a distribution certificate, and a provisioning profile.
The unsigned IPA can be signed by services such as Xcode, Transporter, or a
sideloading tool. To sign it manually:

```bash
unzip Daymark-1.2.0-ios-unsigned.ipa
codesign --force --sign "Apple Distribution: Your Team" \
  --entitlements Runner/Runner.entitlements \
  Payload/Runner.app
zip -qry Daymark-signed.ipa Payload
```

For a fully automated signed build, add these secrets and extend the `ios`
job:

- `APPLE_CERTIFICATE_BASE64` — `.p12` distribution certificate
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_PROVISIONING_PROFILE_BASE64`
- `APPLE_TEAM_ID`
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_API_PRIVATE_KEY`

Then import the certificate into a temporary keychain, install the provisioning
profile, and run `flutter build ipa --release` instead of the unsigned build.
Uploading to App Store Connect still requires an App Store Connect app record.

The macOS DMG is **ad-hoc signed**, not notarized. It runs on the machine that
built it and on other Macs after the user allows it in **System Settings →
Privacy & Security**, or after right-clicking **Open**. For a smoother
distribution:

1. Join the Apple Developer Program.
2. Export a **Developer ID Application** certificate.
3. Import it into a temporary keychain in CI.
4. Sign with `codesign --deep --force --options runtime`.
5. Notarize with `xcrun notarytool submit` and staple the ticket with
   `xcrun stapler staple`.

Until then, the release notes call the Apple artifacts unsigned and explain the
Gatekeeper prompt. This is honest and avoids pretending an ad-hoc build is a
notarized production build.

## Linux package details

The portable tarball contains the Flutter bundle and can be launched with:

```bash
tar -xzf Daymark-1.2.0-linux-x64.tar.gz
./Daymark-1.2.0-linux-x64/daymark
```

The Debian package installs to `/usr/lib/daymark`, adds `/usr/bin/daymark`, and
installs a desktop entry and icon under `/usr/share`. Install it with:

```bash
sudo apt install ./Daymark-1.2.0-linux-amd64.deb
```

The package declares dependencies on GTK 3, blkid, and SQLite. It targets x64
and does not bundle a private GTK stack.

## Windows build

The ZIP is a portable folder. Extract it and run `daymark.exe`. It uses the
system Visual C++ runtime and the Windows notification service. The workflow
builds x64 only.

## macOS architecture

The workflow uses `macos-14` and names the artifact with the runner's
architecture (`uname -m`). Apple Silicon users should use the `arm64` artifact;
Intel users should use `x64`. Building a universal binary would require
producing and combining both architectures in a follow-up job.

## Reproducing packaging locally

The CI workflow is the source of truth, but these commands reproduce most of
it on a matching host:

```bash
flutter pub get
flutter build linux --release
flutter build windows --release
flutter build apk --release
flutter build appbundle --release
flutter build ios --release --no-codesign
flutter build macos --release
```

The Linux `.deb` and macOS `.dmg` packaging steps are in
`.github/workflows/ci.yml`. See the `Makefile` for shorter local targets.

## Checklist before a release

- [ ] `flutter pub get`
- [ ] `dart format --output=none --set-exit-if-changed lib test`
- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] `flutter build linux --release`
- [ ] Version and changelog agree
- [ ] Tag is `v<major>.<minor>.<patch>`
- [ ] CI release job is green
- [ ] Download one artifact per platform and launch it
- [ ] Verify `SHA256SUMS.txt` matches the uploaded files

## Rolling back a bad release

Delete the GitHub Release and the tag, then publish a new patch version. Do
not move an existing tag: users and package mirrors may already have cached
its artifacts.

```bash
git tag -d v1.2.0
git push origin :refs/tags/v1.2.0
gh release delete v1.2.0 --yes
```
