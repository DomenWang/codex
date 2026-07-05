# WeatherAlarmCore Integration Notes

## Target

- iOS 26+
- Swift + SwiftUI
- Frameworks:
  - AlarmKit
  - WeatherKit
  - BackgroundTasks
  - CoreLocation

## Signing & Capabilities

Enable these capabilities on the app target:

1. AlarmKit
2. WeatherKit
3. Background Modes
   - Background fetch

## Info.plist

Add:

```xml
<key>NSAlarmKitUsageDescription</key>
<string>根据早晨天气情况提前您的起床闹钟。</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>用于获取您所在位置的真实天气预报。</string>

<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.yourcompany.weatheralarm.daily-weather-refresh</string>
</array>
```

## Important Constraints

- BGAppRefreshTask cannot guarantee an exact 03:00 launch. The code requests 03:00 through `earliestBeginDate`; iOS decides the actual execution time.
- The wake-up alarm time is not hard-coded. `AlarmManager` reads it from `AlarmSettingsStore`.
- WeatherKit failures are not masked with fake data. If WeatherKit, location, or permissions fail, the task fails and keeps the existing alarm unchanged.
- TransitService failures are caught inside `AlarmManager`; the app falls back to weather-only alarm adjustment and publishes the Toast message `路况检测失败`.
- SwiftUI screens should listen to `ToastMessageCenter` and use `toast(message:)`. Do not call `TransitService` directly from a View.
- Replace `com.yourcompany.weatheralarm.daily-weather-refresh` with your real bundle-style identifier in both code and Info.plist.
