# WeatherAlarm TestFlight 閰嶇疆姝ラ

鏈」鐩富 App Bundle ID锛?
```text
com.domenx.SmartWake
```

Widget Extension Bundle ID锛?
```text
com.domenx.SmartWake.widget
```

App Group锛?
```text
group.com.domenx.SmartWake
```

## 1. Apple Developer 鍚庡彴

鎵撳紑锛?
```text
https://developer.apple.com/account/resources/identifiers/list
```

### 1.1 鍒涘缓涓?App ID

1. 杩涘叆 `Certificates, Identifiers & Profiles`銆?2. 閫夋嫨 `Identifiers`銆?3. 鐐瑰嚮 `+`銆?4. 閫夋嫨 `App IDs`銆?5. 閫夋嫨 `App`銆?6. Description 濉細

```text
WeatherAlarm
```

7. Bundle ID 閫夋嫨 `Explicit`锛屽～锛?
```text
com.domenx.SmartWake
```

8. 鍕鹃€夎兘鍔涳細
   - App Groups
   - WeatherKit
   - Background Modes
   - In-App Purchase

濡傛灉 Apple Developer 鍚庡彴宸茬粡鏄剧ず AlarmKit锛岃涔熷嬀閫?AlarmKit銆傞儴鍒嗘柊绯荤粺鑳藉姏鍙兘闇€瑕?Xcode / Apple 鍚庡彴閫愭寮€鏀撅紱濡傛灉鍚庡彴鏆傛椂娌℃湁 AlarmKit锛岃鍏堝畬鎴愬叾瀹冭兘鍔涳紝涔嬪悗鍦?Xcode Signing & Capabilities 閲屽悓姝ャ€?
### 1.2 鍒涘缓 App Group

1. 浠嶅湪 `Identifiers`銆?2. 鐐瑰嚮 `+`銆?3. 閫夋嫨 `App Groups`銆?4. Identifier 濉細

```text
group.com.domenx.SmartWake
```

5. 鍒涘缓鍚庡洖鍒颁富 App ID銆?6. 鎵撳紑涓?App ID 鐨?`App Groups` 閰嶇疆銆?7. 鍕鹃€夛細

```text
group.com.domenx.SmartWake
```

### 1.3 鍒涘缓 Widget Extension App ID

鍐嶅垱寤轰竴涓?App ID锛?
Description锛?
```text
WeatherAlarmWidget
```

Bundle ID锛?
```text
com.domenx.SmartWake.widget
```

鍕鹃€夛細

- App Groups

鐒跺悗缁?Widget App ID 涔熼厤缃悓涓€涓?App Group锛?
```text
group.com.domenx.SmartWake
```

## 2. App Store Connect 鍒涘缓 App

鎵撳紑锛?
```text
https://appstoreconnect.apple.com/apps
```

1. 鐐瑰嚮 `+`銆?2. 閫夋嫨 `New App`锛屼笉鏄?`New App Bundle`銆?3. Platform 閫夋嫨 `iOS`銆?4. Name 濉細

```text
WeatherAlarm
```

5. Primary Language 閫変腑鏂囨垨鑻辨枃閮藉彲浠ャ€?6. Bundle ID 閫夋嫨锛?
```text
com.domenx.SmartWake
```

7. SKU 濉細

```text
weatheralarm-ios
```

8. User Access 閫夋嫨 Full Access 鎴栨寜浣犵殑鍥㈤槦璁剧疆銆?9. 鐐瑰嚮 Create銆?
## 3. 鍒涘缓 App Store Connect API Key

鎵撳紑锛?
```text
https://appstoreconnect.apple.com/access/integrations/api
```

1. 杩涘叆 `Users and Access`銆?2. 杩涘叆 `Integrations`銆?3. 閫夋嫨 `App Store Connect API`銆?4. 鐐瑰嚮 `Team Keys`銆?5. 鐐瑰嚮 `Generate API Key`銆?6. Name 濉細

```text
GitHub Actions Upload
```

7. Role 寤鸿閫?`App Manager` 鎴?`Admin`銆?8. 涓嬭浇 `.p8` 鏂囦欢銆傝繖涓枃浠跺彧鑳戒笅杞戒竴娆°€?
璁板綍涓変釜鍊硷細

- `APPLE_API_KEY_ID`锛欿ey ID
- `APPLE_API_ISSUER_ID`锛欼ssuer ID
- `.p8` 鏂囦欢鍐呭锛氬悗闈㈣杞?Base64

## 4. Windows 涓婃妸 .p8 杞?Base64

PowerShell 閲屾墽琛岋細

```powershell
[Convert]::ToBase64String([System.IO.File]::ReadAllBytes("C:\浣犵殑璺緞\AuthKey_XXXXXX.p8"))
```

澶嶅埗杈撳嚭锛屼綔涓?GitHub Secret锛?
```text
APPLE_API_KEY_BASE64
```

## 5. GitHub Secrets

鎵撳紑浠撳簱锛?
```text
https://github.com/DomenWang/codex/settings/secrets/actions
```

娣诲姞浠ヤ笅 Secrets锛?
```text
APPLE_API_KEY_ID
APPLE_API_ISSUER_ID
APPLE_API_KEY_BASE64
EXPORT_OPTIONS
```

`EXPORT_OPTIONS` 濉畬鏁?XML锛屾敞鎰忔妸 `YOUR_TEAM_ID` 鎹㈡垚浣犵殑 Apple Developer Team ID锛?
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
  <key>manageAppVersionAndBuildNumber</key>
  <true/>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
```

Team ID 鏌ョ湅浣嶇疆锛?
```text
https://developer.apple.com/account
```

Membership Details 閲屾湁 Team ID銆?
## 6. 杩愯 GitHub Actions 涓婁紶 TestFlight

鎵撳紑锛?
```text
https://github.com/DomenWang/codex/actions/workflows/app-store-upload.yml
```

鐐瑰嚮锛?
```text
Run workflow
```

鎴栬€呮帹涓€涓?tag锛?
```powershell
git tag v0.1.0
git push origin v0.1.0
```

鎴愬姛鍚?Actions 浼氾細

1. 鐢熸垚 Xcode project銆?2. Archive銆?3. Export IPA銆?4. 涓婁紶 IPA 鍒?App Store Connect銆?
## 7. TestFlight 瀹夎

涓婁紶鎴愬姛鍚庯紝鎵撳紑锛?
```text
https://appstoreconnect.apple.com/apps
```

1. 杩涘叆 WeatherAlarm銆?2. 鎵撳紑 `TestFlight`銆?3. 绛夊緟 Apple 澶勭悊 Build銆?4. 澶勭悊瀹屾垚鍚庯紝娣诲姞 Internal Testing 娴嬭瘯鍛樸€?5. 浣犵殑 iPhone 瀹夎 TestFlight App銆?6. 鐢ㄥ悓涓€涓?Apple ID 鎺ユ敹娴嬭瘯閭€璇枫€?7. 鍦?TestFlight 閲屽畨瑁?WeatherAlarm銆?
## 甯歌闂

### 鎵句笉鍒?Bundle ID

鍏堝幓 Apple Developer 鐨?Identifiers 鍒涘缓 `com.domenx.SmartWake`銆?
### 鑷姩绛惧悕澶辫触

妫€鏌ワ細

- API Key 鏉冮檺鏄惁鏄?App Manager 鎴?Admin銆?- App ID 鑳藉姏鏄惁宸茬粡寮€鍚€?- App Group 鏄惁鍒嗛厤缁欎富 App 鍜?Widget Extension銆?- `EXPORT_OPTIONS` 閲岀殑 Team ID 鏄惁姝ｇ‘銆?
### App Store Connect 娌℃湁鏄剧ず Build

涓婁紶鍚?Apple 澶勭悊 build 闇€瑕佸嚑鍒嗛挓鍒板嚑鍗佸垎閽熴€傛墦寮€ App Store Connect 鐨?TestFlight 椤电瓑寰呭鐞嗗畬鎴愩€?
### 涓嶈兘鍦?iPhone 瀹夎

纭 iPhone 绯荤粺鏄?iOS 26+锛屽洜涓烘湰椤圭洰浣跨敤 AlarmKit iOS 26+銆?

