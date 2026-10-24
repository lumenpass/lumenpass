# LumenPass Mobile — Testing Protocol

**Platform:** Android 8 or newer
**Scope:** Local and cloud-backed vault workflows
**Updated:** 2026-08-26

---

## 1. Test Preparation

### Required

- An Android phone or emulator running Android 8 or newer
- The current LumenPass build installed
- A stable internet connection for cloud-provider and support-link tests
- A second browser or device when verifying remote sync
- A test `.kdbx` file that contains no real personal data

### Provider-specific test access

Use only provider accounts or servers you control. Prepare access for every provider you intend to test:

| Provider | Required access |
|---|---|
| Google Drive | A Google account able to authorize Drive access |
| Dropbox | A Dropbox account able to authorize file access |
| OneDrive | A Microsoft account able to authorize OneDrive access |
| WebDAV | Server URL, port, username, password, and root path |
| SFTP | Host, port, username, password or supported SSH credentials, and root path |
| S3 | Access key, secret key, region, bucket, and optional root path |

Do not place production secrets or real personal records in test vaults.

### Record each result

- ✅ **Pass** — behavior matches the protocol
- ❌ **Fail** — record the actual behavior, steps, and a screenshot or recording
- ⏭️ **Skipped** — record why the test could not be performed

For cloud tests, note the provider, connection type, and whether the vault was newly created or opened from an existing file.

---

## 2. First Launch and Onboarding

### 2.1 Splash screen

1. Clear the app's local data or install it on a clean device.
2. Open LumenPass.

**Verify:**

- The splash screen appears without visual glitches.
- Startup completes without a crash or indefinite loading state.
- The onboarding walkthrough appears on a first launch.

### 2.2 Onboarding walkthrough

1. Swipe through all three pages.
2. Verify the pages describe encrypted vault storage, AutoFill, and private encrypted sync.
3. Test **Continue**, **Skip**, and **Get Started** where shown.

**Verify:**

- Swiping and page indicators stay synchronized.
- Text and artwork remain readable without clipping.
- The final action opens the vault picker.
- The walkthrough does not imply that a LumenPass service identity is required.

### 2.3 Relaunch behavior

1. Complete onboarding.
2. Force-close and reopen the app.

**Verify:**

- Completed onboarding is not shown again automatically.
- The app opens to the vault picker or the configured default-vault flow.

---

## 3. Local Vault Creation and Master Password

### 3.1 Create a local vault

1. In **Your vaults**, select **Local**.
2. Choose the action to create a new encrypted vault.
3. Enter a unique vault name such as `Local QA Vault`.
4. Set a test master password.
5. Finish creation.

**Verify:**

- Creation succeeds without requiring network access.
- The vault appears in **Your vaults** with a Local provider indicator.
- The vault can be opened with its master password.
- Closing and reopening LumenPass does not remove the vault reference.

### 3.2 Master-password validation

1. Lock the local vault.
2. Enter an incorrect master password.
3. Retry with the correct master password.

**Verify:**

- The incorrect password does not open the vault.
- The error is clear and does not expose sensitive details.
- A retry is possible without restarting the app.
- The correct master password opens the vault.

### 3.3 Offline local-vault operation

1. Disable Wi-Fi and mobile data.
2. Open the local vault.
3. Add or edit an entry, save it, lock the vault, and reopen it.

**Verify:**

- Local vault operations remain available offline.
- The saved change survives lock, reopen, and app restart.
- No cloud-connection error blocks local work.

### 3.4 Lock behavior

1. Open the vault.
2. Use the lock control.
3. Attempt to return to vault content without unlocking.

**Verify:**

- Sensitive content is no longer readable after locking.
- The vault requires its configured unlock method before showing content again.

---

## 4. Multiple Vaults and Vault Picker

### 4.1 Add multiple local vaults

1. Create at least three local vaults with distinct names.
2. Return to **Your vaults** after each creation.

**Verify:**

- Every vault remains listed and independently usable.
- Creating another vault is not blocked by an artificial vault-count limit.
- Each vault keeps its own master password and quick-unlock configuration.

### 4.2 Search vaults

1. Search by full vault name.
2. Search by a partial name.
3. Search by provider or file-name text when available.
4. Clear the search.

**Verify:**

- Matching vaults appear as the query changes.
- Nonmatching vaults are hidden.
- Clearing the query restores the full list.

### 4.3 Vault actions

For a disposable test vault, exercise the actions exposed by its menu, including duplicate, export, default selection, or remove when present.

**Verify:**

- Duplicate creates a distinct usable vault reference or file.
- Export produces an accessible file without changing the source vault.
- A selected default vault follows the configured startup behavior.
- Remove deletes only the local app reference unless the UI explicitly states otherwise.
- Removing one vault does not affect other vaults.

### 4.4 Vault isolation

1. Add different entries to two vaults.
2. Switch between them several times.

**Verify:**

- Entries never appear in the wrong vault.
- Search, TOTP, tags, and recent-item data reflect only the active vault.
- Lock and quick-unlock settings remain scoped to the correct vault.

---

## 5. Cloud Providers and Provider Credentials

All supported providers must remain selectable and usable. Test each provider independently; failure in one provider must not disable another.

### 5.1 Google Drive OAuth

1. Select **Google Drive** in the vault picker.
2. Start the connection flow and authorize Drive access with a Google account.
3. Return to LumenPass.
4. Browse folders, create a test vault, and open an existing `.kdbx` file.

**Verify:**

- The system or browser OAuth flow identifies Google Drive clearly.
- Cancellation returns safely to LumenPass and allows another attempt.
- Successful authorization returns to the app and shows the connected account.
- Folder browsing, create, and open operations work.
- The connection is restored after an app restart when the provider token remains valid.

### 5.2 Dropbox OAuth

Repeat test 5.1 with **Dropbox**.

**Verify:**

- Dropbox authorization opens and returns to LumenPass correctly.
- Cancellation is harmless and retryable.
- Folder browsing, create, open, and connection restoration work.

### 5.3 OneDrive OAuth

Repeat test 5.1 with **OneDrive** and a Microsoft account.

**Verify:**

- OneDrive authorization requests the expected file-access scope.
- Cancellation is harmless and retryable.
- Folder browsing, create, open, and connection restoration work.

### 5.4 WebDAV credentials

1. Select **WebDAV**.
2. Enter server URL, port, username, password, and root path.
3. Test the connection.
4. Browse the configured root, create a test vault, and open an existing `.kdbx` file.
5. Repeat once with an invalid password or unreachable host.

**Verify:**

- Valid credentials connect and persist securely for later use.
- Paths are normalized and browsing stays within the configured location.
- Invalid credentials produce an actionable error without a crash.
- Correcting the credentials allows a successful retry.

### 5.5 SFTP credentials

1. Select **SFTP**.
2. Enter host, port, username, supported authentication details, and root path.
3. Connect, browse, create a test vault, and open an existing `.kdbx` file.
4. Repeat once with invalid connection details.

**Verify:**

- Valid credentials establish an SFTP connection.
- Invalid credentials or host-key/connection failures are reported clearly.
- Create, open, and folder navigation work after connection.
- Corrected credentials can be saved and reused.

### 5.6 S3 credentials

1. Select **S3**.
2. Enter access key, secret key, region, bucket, and optional root path.
3. Connect, browse, create a test vault, and open an existing `.kdbx` file.
4. Repeat once with an invalid secret, region, or bucket.

**Verify:**

- Valid credentials can access the configured bucket and path.
- Invalid configuration produces an actionable error.
- Object listing, create, and open operations work.
- Credentials are not displayed in plain text after saving.

### 5.7 Disconnect each provider

For each connected provider:

1. Start the disconnect action.
2. Read and confirm the warning.
3. Disconnect.

**Verify:**

- Only local provider credentials/tokens and local vault references are removed.
- Remote vault files are not deleted.
- Other providers and local vaults remain available.
- Reconnecting restores access to remote files.

---

## 6. Cloud Sync and Conflict Safety

Run these tests for every configured provider: Google Drive, Dropbox, OneDrive, WebDAV, SFTP, and S3.

### 6.1 Upload after edit

1. Open a cloud-backed vault.
2. Add an entry with a unique timestamp in its title.
3. Save and observe the sync status.
4. Verify the remote file from the provider or a second device.

**Verify:**

- The app reports pending/in-progress/completed states accurately.
- The remote vault receives the saved change.
- Repeated saves do not create unintended duplicate vault files.

### 6.2 Refresh remote changes

1. Modify the same test vault from another compatible client or device.
2. Return to LumenPass and trigger refresh if needed.

**Verify:**

- The remote update is downloaded and visible.
- The vault remains readable with the same master password.
- Sync status returns to a healthy state.

### 6.3 Offline edit and recovery

1. Open a cloud-backed vault while online.
2. Disable network access.
3. Edit and save an entry.
4. Restore network access.

**Verify:**

- The cached vault remains usable offline.
- The local change is retained while sync is unavailable.
- Sync resumes when connectivity returns.
- No data is silently lost.

### 6.4 Connection health and expired credentials

1. Revoke or invalidate a disposable provider credential where practical.
2. Refresh vault connection status or attempt sync.
3. Reconnect the provider.

**Verify:**

- The affected vault shows a useful health or credential error.
- Unaffected providers continue working.
- Reconnection restores sync without creating a duplicate vault reference.

### 6.5 Concurrent-change handling

1. Make different edits to the same cloud vault from two clients before both have synchronized.
2. Allow both clients to reconnect.

**Verify:**

- The app does not silently overwrite newer remote data without warning or recovery behavior.
- Any conflict message explains the available action.
- The resulting vault remains valid and unlockable.

---

## 7. Vault Items

Use synthetic values only.

### 7.1 Create common entry types

Create and save representative entries for:

- Website credentials
- Secure note
- Credit card
- Bank account
- Identity
- SSH key

**Verify:**

- Each type presents appropriate fields.
- Saved entries appear in **Items**.
- Sensitive fields are concealed by default where expected.
- Reveal and copy controls work.

### 7.2 Edit, search, sort, and delete

1. Edit an existing entry and save it.
2. Search by full and partial title.
3. Exercise available sort and filter controls.
4. Delete a disposable entry and confirm.

**Verify:**

- Edits persist after lock and reopen.
- Search, sort, and filters return the expected entries.
- Delete affects only the selected entry.
- The app remains responsive with at least 50 entries.

### 7.3 Unicode and long values

1. Create an entry titled `🔐 Café Résumé 日本語`.
2. Add long text and punctuation to several fields.
3. Save, reopen, edit, and copy the values.

**Verify:**

- Unicode and long values remain intact.
- Layout does not overlap or clip controls.
- Clipboard output matches the stored value.

---

## 8. TOTP and Password Generator

### 8.1 Add TOTP manually

1. Open the **TOTP** tab.
2. Add a disposable TOTP secret from a service you control.
3. Compare the generated code with another standards-compatible authenticator.

**Verify:**

- The current code and countdown render correctly.
- Codes rotate at the expected interval.
- Generated values match the reference authenticator.

### 8.2 Scan a TOTP QR code

1. Add a TOTP record using the camera scanner.
2. Grant camera permission when requested.
3. Scan a valid test QR code.

**Verify:**

- Permission denial is handled without a crash and can be retried.
- A valid QR code populates the correct TOTP data.
- Copying the current code provides clear feedback.

### 8.3 Password generator

1. Open the password generator.
2. Change length and character options.
3. Regenerate several times and copy a result.

**Verify:**

- Generated values follow the selected rules.
- Regeneration produces new values.
- Copy works and gives confirmation.

---

## 9. PIN and Biometric Vault Unlock

Configure and test quick unlock separately for at least two vaults.

### 9.1 Enable PIN unlock

1. Open a vault with its master password.
2. Go to **Profile → Settings → Security**.
3. Enable **PIN unlock**.
4. Confirm the master password if requested.
5. Enter and confirm a six-digit PIN.
6. Lock the vault and unlock it with the PIN.

**Verify:**

- PIN setup requires matching six-digit values.
- An incorrect PIN is rejected and retry remains available.
- The correct PIN opens only the vault for which it was configured.
- The master password remains available as the primary recovery method.

### 9.2 Disable PIN unlock

1. Return to **Security**.
2. Disable **PIN unlock** and confirm.
3. Lock the vault.

**Verify:**

- PIN data for that vault is removed.
- The PIN option no longer opens that vault.
- Other vaults keep their own PIN configuration.

### 9.3 Enable biometric unlock

1. Confirm the device has a fingerprint, face, or supported device credential configured.
2. Open a vault with its master password.
3. Go to **Profile → Settings → Security** and enable **Biometric unlock**.
4. Complete the system biometric prompt.
5. Lock and unlock the vault biometrically.

**Verify:**

- Unsupported devices show an understandable unavailable state.
- Failed or cancelled biometric prompts do not open the vault.
- Successful authentication opens only the configured vault.
- The master password remains usable.

### 9.4 Biometric changes and disable

1. Disable biometric unlock in LumenPass and confirm it no longer appears for that vault.
2. If practical on a test device, change the device biometric enrollment and retry.

**Verify:**

- Disabling removes the stored quick-unlock material for that vault.
- Invalidated device biometrics fail safely and fall back to the master password.
- Other vaults are unaffected.

---

## 10. AutoFill

### 10.1 Enable the Android AutoFill service

1. Open a vault and go to **Profile → Settings → AutoFill**.
2. Open Android's AutoFill settings.
3. Select LumenPass as the AutoFill service.
4. Return to LumenPass.

**Verify:**

- The correct system settings page opens.
- LumenPass reports the enabled state after returning.
- Cancelling system setup leaves the app usable.

### 10.2 Fill a website credential

1. Save a website credential with a test URL, username, and password.
2. Open the matching site in Chrome.
3. Focus the username and password fields.
4. Select the LumenPass suggestion.

**Verify:**

- Suggestions are associated with the correct site.
- Selecting a suggestion fills the expected fields.
- A locked vault requires vault authentication before revealing data.
- Credentials from another vault are not exposed unexpectedly.

### 10.3 Other apps and browsers

Repeat AutoFill in another supported browser and a test app with credential fields.

**Verify:**

- Inline or picker suggestions render correctly.
- Search in the picker can find the intended entry.
- Cancelling the picker inserts no data.

### 10.4 AutoFill reminder

1. Disable LumenPass as the system AutoFill service.
2. Unlock a vault and observe the setup reminder.
3. Test **AutoFill Settings**, **Setup Later**, and **Don't Use AutoFill** across separate runs.

**Verify:**

- Each action matches its label.
- **Setup Later** allows the reminder to return later.
- **Don't Use AutoFill** suppresses future reminders until the preference is changed.

---

## 11. Profile, Settings, and Support

### 11.1 Current navigation

1. Open an unlocked vault.
2. Move through **Home**, **Items**, **TOTP**, and **Profile** using the bottom navigation.

**Verify:**

- Every destination opens and the active destination is clear.
- The fourth destination and screen title both use **Profile**.
- Returning to a destination preserves reasonable screen state.

### 11.2 Profile screen

1. Open **Profile**.
2. Pull to refresh.
3. Review the vault sync-status row, app version/build, support email, website, and copyright.

**Verify:**

- The screen contains vault preferences, security, support, and app information.
- Sync status reflects the active vault.
- Version and build values are present in an installed release build.

### 11.3 Settings sections

Open **Profile → Settings** and inspect:

- **General** — language, default tab, and quick-vault selection
- **Security** — biometric/PIN unlock, auto-lock, clipboard, and privacy controls
- **AutoFill** — system service and suggestion options
- **Backup** — schedule, retention, location, and restore controls
- **About** — version, licenses, privacy policy, and terms
- **Rate LumenPass** — external store action

**Verify:**

- Every row opens the expected screen or external destination.
- Settings persist after closing and reopening the app.
- Choosing **Profile** as the default tab opens that destination after vault unlock.
- Back navigation returns to the previous settings level without losing changes.

### 11.4 Support email and website

1. Tap the support email on **Profile**.
2. Return to LumenPass and tap the website.

**Verify:**

- The email action opens a compatible mail app or displays an actionable system message.
- The website opens in a browser.
- Returning to LumenPass preserves the active vault state according to security settings.

### 11.5 Security preferences

Exercise **Auto-lock**, **Clear clipboard**, screenshot blocking, and password concealment controls where available.

**Verify:**

- Auto-lock activates after the selected idle period.
- Copied sensitive text is cleared after the selected timeout where supported by Android.
- Screenshot blocking prevents sensitive capture when enabled.
- Password concealment changes display behavior without changing stored values.

---

## 12. Resilience, Accessibility, and Performance

### 12.1 Interrupted operations

Cancel or interrupt each of the following once:

- Cloud OAuth authorization
- WebDAV, SFTP, or S3 credential entry
- Cloud folder selection
- Vault creation
- Vault unlock
- AutoFill selection

**Verify:**

- Cancellation returns to a stable screen.
- No incomplete vault reference or duplicate file is created.
- The action can be retried.

### 12.2 Rapid input and back navigation

1. Rapidly tap a create, save, sync, or unlock action.
2. Navigate several levels deep and press Android Back repeatedly.

**Verify:**

- Only one operation runs when duplicate submission would be unsafe.
- Progress states prevent accidental repeated writes.
- Back navigation does not crash or expose locked content.

### 12.3 Rotation, large text, and display modes

1. Rotate between portrait and landscape on key screens.
2. Set Android font size and display size to their largest practical values.
3. Test light and dark system appearance if supported by the build.

**Verify:**

- Important controls remain reachable.
- Text does not overlap or become unreadable.
- Partially entered non-secret form data behaves predictably across rotation.
- Sensitive values are not exposed by layout changes.

### 12.4 Startup, unlock, and large-vault performance

1. Measure cold startup to the vault picker.
2. Measure master-password unlock for a representative vault.
3. Scroll and search a vault with at least 50 entries.
4. Observe sync while continuing to navigate.

**Verify:**

- Startup and unlock complete without prolonged frozen frames.
- Scrolling and search remain responsive.
- Background sync does not block normal vault use.
- Errors offer a retry path rather than an indefinite spinner.

### 12.5 Device coverage

Repeat the core local-vault, cloud, PIN/biometric, and AutoFill tests on available device classes:

| Device class | Suggested coverage |
|---|---|
| Older Android | Android 8–10 |
| Budget phone | Lower-memory physical device |
| Current phone | Recent Android release |
| Tablet | Large-screen Android device |

Record device model, Android version, app version/build, provider tested, and any vendor-specific behavior.

---

## 13. Bug Report Template

```text
TITLE:
[Short description]

ACTUAL RESULT:
[What happened]

EXPECTED RESULT:
[What should have happened]

STEPS:
1. [Step]
2. [Step]
3. [Step]

TEST CONTEXT:
- Device:
- Android version:
- LumenPass version/build:
- Vault storage: Local / Google Drive / Dropbox / OneDrive / WebDAV / SFTP / S3
- Vault state: Locked / Unlocked
- Unlock method: Master password / PIN / Biometric
- Network: Wi-Fi / Mobile / Offline
- AutoFill enabled: Yes / No

DATA SAFETY:
- Was any test data lost or overwritten?
- Was a remote file changed?
- Can the issue be reproduced with a disposable vault?

ATTACHMENTS:
[Screenshot, recording, and sanitized logs if available]
```

Never include a master password, PIN, biometric data, provider token, access key, secret key, server password, or real vault content in a bug report.

---

## 14. Results Summary

```text
TESTER:           ___________________________
DATE:             ___________________________
DEVICE:           ___________________________
ANDROID VERSION:  ___________________________
APP VERSION:      ___________________________
BUILD:            ___________________________

RESULTS:
1. Preparation                         Pass / Fail / Skipped
2. First Launch and Onboarding         Pass / Fail / Skipped
3. Local Vault and Master Password     Pass / Fail / Skipped
4. Multiple Vaults and Vault Picker    Pass / Fail / Skipped
5. Cloud Providers and Credentials     Pass / Fail / Skipped
6. Cloud Sync and Conflict Safety      Pass / Fail / Skipped
7. Vault Items                         Pass / Fail / Skipped
8. TOTP and Password Generator         Pass / Fail / Skipped
9. PIN and Biometric Unlock            Pass / Fail / Skipped
10. AutoFill                           Pass / Fail / Skipped
11. Profile, Settings, and Support     Pass / Fail / Skipped
12. Resilience and Performance         Pass / Fail / Skipped

PROVIDERS TESTED:
[ ] Google Drive
[ ] Dropbox
[ ] OneDrive
[ ] WebDAV
[ ] SFTP
[ ] S3

DATA-LOSS OR SECURITY ISSUES:
[List issue references or write "None"]

OTHER BUGS:
[List issue references or write "None"]

OVERALL NOTES:
[Usability, clarity, reliability, and provider-specific observations]
```
