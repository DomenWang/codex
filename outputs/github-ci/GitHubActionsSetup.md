# GitHub Actions iOS Build Setup

I added:

```text
.github/workflows/ios-build.yml
.github/workflows/app-store-upload.yml
```

The workflow builds on a GitHub macOS runner with Xcode and runs:

```bash
xcodebuild clean build
```

Simulator builds use:

```text
-sdk iphonesimulator
```

This avoids failures caused by GitHub runner images not having a specific simulator device name installed.

`app-store-upload.yml` is a separate manual/tag workflow for:

1. `xcodebuild archive`
2. `xcodebuild -exportArchive`
3. uploading the exported `.ipa` to App Store Connect

## Required before it can pass

This repository can generate the Xcode project in GitHub Actions through XcodeGen:

```text
project.yml
```

The workflow runs:

```bash
brew install xcodegen
xcodegen generate --spec project.yml
```

If you later create a real `WeatherAlarm.xcodeproj` in Xcode and commit it, the workflow will use that project instead.

## Capabilities

Enable in Xcode:

- AlarmKit
- WeatherKit
- Background Modes
  - Background fetch

Also add the Info.plist keys described in:

```text
outputs/WeatherAlarmCore/IntegrationNotes.md
```

## If your project name differs

Edit `.github/workflows/ios-build.yml`:

```yaml
env:
  XCODE_PROJECT: YourProject.xcodeproj
  XCODE_WORKSPACE: ""
  SCHEME: YourScheme
```

If you use CocoaPods or a workspace:

```yaml
env:
  XCODE_PROJECT: ""
  XCODE_WORKSPACE: YourProject.xcworkspace
  SCHEME: YourScheme
```

## About signing

The simulator build workflow uses:

```bash
CODE_SIGNING_ALLOWED=NO
```

That is enough for simulator builds.

For App Store Connect upload, configure GitHub repository secrets:

- `EXPORT_OPTIONS`
- `APPLE_API_KEY_BASE64`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`

Recommended `EXPORT_OPTIONS` value:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
```

PowerShell Base64 command:

```powershell
[Convert]::ToBase64String([System.IO.File]::ReadAllBytes("AuthKey_YOUR_KEY_ID.p8"))
```

Important: the private key file name uses `APPLE_API_KEY_ID`, so the workflow creates:

```text
private_keys/AuthKey_${APPLE_API_KEY_ID}.p8
```
