# Releasing GPX Organizer

`./build_app.sh` makes an app that is only signed ad hoc. Other people can run it after *right-click → Open*, but macOS warns
about an unidentified developer. For a smooth download you need a **signed and notarized** app.

## One-time setup (paid Apple Developer Program, about 99 USD per year)

1. Join the [Apple Developer Program](https://developer.apple.com/programs/).
2. Create a **Developer ID Application** certificate (Xcode → Settings → Accounts → Manage Certificates, or developer.apple.com → Certificates).
   Check that it is installed: `security find-identity -v -p codesigning`. The name looks like
   `Developer ID Application: Your Name (TEAMID)`.
3. Create an **app-specific password** at appleid.apple.com (Sign-In and Security → App-Specific Passwords).
4. Store the notarization credentials in your keychain (once):
   ```sh
   xcrun notarytool store-credentials "gpx-organizer" --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
   ```

## Making a release

1. Change the version number in `VERSION`.
2. Run:
   ```sh
   SIGN_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="gpx-organizer" ./release.sh
   ```
   The script builds the app, signs it with the hardened runtime, sends it to Apple for notarization, staples the ticket and
   creates `dist/GPX-Organizer-<version>.zip`.
3. Publish the ZIP: on GitHub → *Releases → Draft a new release* (tag `v<version>`), attach the ZIP. Or with the GitHub CLI:
   ```sh
   gh release create v0.1.0 dist/GPX-Organizer-0.1.0.zip --title "GPX Organizer 0.1.0" --notes "First release"
   ```

## Without a developer account

Attach the ad-hoc built ZIP (`ditto -c -k --keepParent "dist/GPX Organizer.app" GPX-Organizer.zip`) and tell users to open the app with
*right-click → Open* once, or to run `xattr -dr com.apple.quarantine "GPX Organizer.app"` after unpacking.
