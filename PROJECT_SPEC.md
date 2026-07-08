# WeatherWake Project Spec

## 3.1 产品矩阵 (Product IDs)

* `com.weatherwake.sub.weather_monthly` (自动续订, ¥19/月) — 天气闹钟入门（不支持任何代金券/立减券）
* `com.weatherwake.sub.weather_yearly` (自动续订, ¥98/年) — 天气闹钟主推订阅（不支持任何代金券/立减券）
* `com.weatherwake.iap.forever_commute` (非消耗型, 原价 ¥598；新用户 51% 优惠券后 ¥298) — 智能闹钟永久买断（支持 100 元永久立减券 / 50 元代金券）
* `com.weatherwake.sub.gaode_enhance` (自动续订, ¥5/月) — 高德路况增强（支持 50 代金券）
* `com.weatherwake.iap.crowdfund.sleep_ai` (非消耗型, ¥98) — AI 催眠引导睡眠众筹（正式上线后抵扣该服务价格）
* `com.weatherwake.iap.crowdfund.weather_takeout` (非消耗型, ¥20) — 天气外卖提醒众筹（正式上线后抵扣该服务价格）
* `com.weatherwake.iap.crowdfund.early_sleep_alarm` (非消耗型, ¥20) — 提前睡觉闹钟众筹（正式上线后抵扣该服务价格）

众筹产品合规边界：

* UI 统一标注为“众筹中 / 上线后抵扣”，AI 催眠支持 98 元，天气外卖提醒和提前睡觉闹钟支持 20 元；不得写“投资、分红、提现、返现、收益”。
* 每项众筹购买只锁定对应服务的抵扣权益，不可跨服务叠加，不可提现。
* 客户端只能在 StoreKit verified transaction 后显示“已支持”，不得模拟支付成功。

推介优惠配置需在 App Store Connect 手动创建，客户端只实现 eligibility 校验和 UI 防误操作：

* `REF100_OFF`：金额立减 100 元，仅适用于 `forever_commute` 产品，每用户限领 1 张，不可转赠
* `REF50_UNIVERSAL`：金额立减 50 元，仅适用于 `forever_commute` 和 `gaode_enhance` 产品，每用户限领 1 张，不可叠加使用；不可用于天气月订阅或天气年订阅

## 3.2 权限判断

```swift
let canUseWeather = UserDefaults.standard.bool(forKey: "hasPurchasedForever") || SubscriptionManager.shared.isWeatherSubscribed
let canUseGaode = SubscriptionManager.shared.hasGaodeEnhance
```

当前实现对应字段：

* `StoreKitSubscriptionStore.hasPurchasedForever`
* `StoreKitSubscriptionStore.isWeatherSubscribed`
* `StoreKitSubscriptionStore.hasGaodeEnhance`
* `StoreKitSubscriptionStore.hasPremiumAccess` 等价于 `hasPurchasedForever || isWeatherSubscribed`

## 3.3 裂变规则（单层双券，合规无风险）

* 绑定逻辑：推荐人生成专属链接 `weatherwake://invite?ref={uuid}`，好友点击后首次启动 App 通过 `onOpenURL` 解析 `ref` 并存储为 `referrer_id`；好友购买时将 `referrer_id` 通过 `appAccountToken` 传入 StoreKit 交易，用于奖励结算。
* 单层奖励（A→B，无多级分销）：
  - 好友 B 得：`universal_50` 代金券 1 张（存储为 `ww_my_coupons`，类型为 `REF50_UNIVERSAL`，`used=false`，仅可用于新人 298 元永久购买权/高德增强）
  - 推荐人 A 得：`forever_100_discount` 立减券 1 张（存储为 `ww_referral_coupons`，类型为 `REF100_OFF`，`claimed=false`，仅可用于新人 298 元永久购买权，抵后实付 198 元）
* 链式限制：B→C 时，B 作为推荐人得 `forever_100_discount` 券，C 得 `universal_50` 券；A 不再从 B→C 的交易中获得奖励，层级上限为 3（A→B→C 即止，D 不计），符合苹果审核对“非多级分销”的要求。
* 客户端校验逻辑：
  - 用户尝试用 50 代金券购买天气月/年订阅时，弹窗提示：`该代金券仅可用于智能永久买断或高德增强服务哦~`
  - 用户尝试同时用 50 代金券抵扣天气永久和高德增强时，弹窗提示：`代金券不可叠加使用，请选择一项服务抵扣~`
* 防刷规则：
  - 同设备 IDFV/IP 仅算 1 次有效邀请
  - 监听 StoreKit `Transaction.revoked` 退款通知，自动回滚双方奖励
  - 每人每月最多 20 次有效邀请，`forever_100_discount` 券每人最多累计 1 张，`universal_50` 券每人最多累计 1 张
* 合规要求：所有奖励仅标注为“立减券/代金券”，严禁出现“现金/提现/微信打款”等违规词汇；客服仅留 `support@weatherwake.app`，不得在 App 内展示联系方式。

## UI 文案

### 推荐人页面（InviteView）

* 顶部进度条：已邀 X 人，再邀 Y 人得 100 元永久立减券（原价 598，新人 298 购买权再抵后 198）
* 奖励说明：每邀 1 位好友完成购买，你得 100 元永久立减券，TA 得 50 元代金券（仅可用于天气永久/高德增强）~
* 底部小字：代金券不可用于天气月/年订阅，不可叠加使用

### 好友首次启动弹窗

* 标题：好友送你 50 元代金券
* 正文：该券仅可用于智能永久买断（原价 598，新人 298 购买权）或高德增强（5 元/月），不可用于月/年订阅哦~
* 按钮：立即领取（自动关联 REF50_UNIVERSAL 优惠）

### Paywall 页面

* 永久档：
  - 原价：¥598 → 新用户 51% 优惠券后：¥298
  - 推荐人福利：新人 298 购买权再用 100 元永久立减券后：¥198
  - 好友福利：新人 298 购买权再用 50 代金券后：¥248
* 98 年档：
  - 标注：该档位不支持代金券，直接购买更划算~
* 高德增强档：
  - 新用户：用 50 代金券后：首月 0 元，次月起 5 元/月（好友福利）

## 必测 Case

1. 好友尝试用 50 代金券购买 19 元月订阅 → 是否弹窗提示“不支持该服务”
2. 好友尝试用 50 代金券购买 98 元年订阅 → 是否弹窗提示“不支持该服务”
3. 好友用 50 代金券购买新人 298 永久购买权 → 实付是否为 248 元，券是否标记为 `used=true`
4. 好友用 50 代金券购买高德增强 → 首月是否 0 元，次月是否自动续费 5 元，券是否标记为 `used=true`
5. 推荐人用 100 元永久立减券购买新人 298 永久购买权 → 实付是否为 198 元，券是否标记为 `claimed=true`
6. 用户同时勾选“用 50 代金券抵天气永久”和“用 50 代金券抵高德增强” → 是否弹窗提示“不可叠加使用”

## App Store Connect 关键操作

去 App Store Connect 给 `REF50_UNIVERSAL` 优惠配置适用产品范围：仅勾选 `forever_commute` 和 `gaode_enhance`，不要勾选月/年订阅 ID。这样即使客户端有漏洞，苹果服务器端也会拦截。

TestFlight 测试时，特意找几个用户尝试用 50 券买年订阅，验证拦截逻辑是否生效。

正式上架后，在 App Store 描述里明确写：50 元代金券仅适用于智能永久买断及高德增强服务，详情见 App 内说明。
