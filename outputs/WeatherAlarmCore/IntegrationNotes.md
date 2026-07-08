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
4. In-App Purchase
5. App Groups
   - `group.com.domenx.SmartWake`

## Info.plist

Add:

```xml
<key>NSAlarmKitUsageDescription</key>
<string>根据早晨天气情况提前您的起床闹钟。</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>用于获取您所在位置的真实天气预报。</string>

<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.domenx.SmartWake.daily-weather-refresh</string>
</array>
```

## Important Constraints

- BGAppRefreshTask cannot guarantee an exact 05:00 launch. The code requests 05:00 through `earliestBeginDate`; iOS decides the actual execution time.
- The wake-up alarm time is not hard-coded. `AlarmManager` reads it from `AlarmSettingsStore`.
- WeatherKit failures are not masked with fake data. If WeatherKit, location, or permissions fail, the task fails and keeps the existing alarm unchanged.
- TransitService failures are caught inside `AlarmManager`; the app falls back to weather-only alarm adjustment and publishes the Toast message `路况检测失败`.
- SwiftUI screens should listen to `ToastMessageCenter` and use `toast(message:)`. Do not call `TransitService` directly from a View.
- Keep `com.domenx.SmartWake.daily-weather-refresh` identical in code, Info.plist, and `project.yml`.
- StoreKit 2 product IDs must be created in App Store Connect before purchases can succeed:
  - `com.weatherwake.sub.weather_monthly` (¥19/month, no coupons)
  - `com.weatherwake.sub.weather_yearly` (¥98/year, no coupons)
  - `com.weatherwake.iap.forever_commute` (¥298 non-consumable, supports REF100_OFF / REF50_UNIVERSAL eligibility)
  - `com.weatherwake.sub.gaode_enhance` (¥5/month, supports REF50_UNIVERSAL eligibility)
- Referral coupon client validation is handled by `CouponEligibilityValidator`, but the actual discounted price must still be enforced by App Store Connect offers or backend receipt validation. Never show cash, withdrawal, or transfer wording.
- The Widget reads the latest real weather-alarm status from the App Group. It does not call WeatherKit, TransitService, or AlarmKit by itself.
- The rain advance minutes are user-configurable in the main UI, but the decision still depends on real WeatherKit precipitation probability.
- Commute route setup calls AMap geocoding plus the selected route API through `TransitService.syncCommuteRoute(...)`: driving, public transit, bicycling, or walking. If the AMap API key is not configured, the app shows a failure message and does not save fake route data.
- Rain/snow commute impact is mode-aware: walking and bicycling use route distance, public transit adds transfer/waiting buffer, and driving adds only severe-weather buffer because real-time traffic duration already captures most driving delay.
