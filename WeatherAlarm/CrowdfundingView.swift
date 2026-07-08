import StoreKit
import SwiftUI

@available(iOS 26.0, *)
struct CrowdfundingView: View {
    @ObservedObject var store: StoreKitSubscriptionStore
    @State private var selectedFeature: CrowdfundingFeature?

    private let features = CrowdfundingFeature.all

    var body: some View {
        List {
            Section {
                CrowdfundingHeroView()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(features) { feature in
                    Button {
                        selectedFeature = feature
                    } label: {
                        CrowdfundingFeatureRow(
                            feature: feature,
                            isSupported: store.supportedCrowdfundingProductIDs.contains(feature.productID)
                        )
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("AI 催眠支持 98 元，其他服务支持 20 元。功能开发完成并正式定价时，已支持金额会抵扣该服务价格。众筹购买以 StoreKit verified transaction 为准，不会模拟支付成功。")
            }

            if case .failed(let message) = store.state {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("功能众筹")
        .sheet(item: $selectedFeature) { feature in
            CrowdfundingCheckoutView(
                store: store,
                feature: feature,
                isSupported: store.supportedCrowdfundingProductIDs.contains(feature.productID)
            )
        }
        .task {
            await store.loadProductsAndEntitlements()
        }
    }
}

struct CrowdfundingFeature: Identifiable {
    let id: String
    let productID: String
    let title: String
    let subtitle: String
    let emotionalPromise: String
    let detail: String
    let symbolName: String
    let supportAmount: Int
    let accent: Color

    static let all = [
        CrowdfundingFeature(
            id: "sleep-ai",
            productID: WeatherAlarmProductID.crowdfundSleepAI,
            title: "AI 催眠引导睡眠",
            subtitle: "众筹中 · 98 元支持",
            emotionalPromise: "把脑子里停不下来的事，慢慢放到明天再说。",
            detail: "未来会根据你的起床时间、明天天气和睡眠目标，生成温柔的睡前引导：呼吸、放松、白噪音脚本和轻提示，让你更容易进入睡眠。",
            symbolName: "moon.stars.fill",
            supportAmount: 98,
            accent: Color(red: 0.39, green: 0.32, blue: 0.84)
        ),
        CrowdfundingFeature(
            id: "weather-takeout",
            productID: WeatherAlarmProductID.crowdfundWeatherTakeout,
            title: "天气外卖提醒",
            subtitle: "众筹中 · 20 元支持",
            emotionalPromise: "雨下大之前，先把晚饭安排好。",
            detail: "未来会根据明天和当下天气提醒你是否适合点外卖：暴雨、降温、风大、通勤变慢时，提前给出更省心的生活建议。",
            symbolName: "bag.fill",
            supportAmount: 20,
            accent: Color(red: 0.91, green: 0.42, blue: 0.18)
        ),
        CrowdfundingFeature(
            id: "early-sleep-alarm",
            productID: WeatherAlarmProductID.crowdfundEarlySleepAlarm,
            title: "提前睡觉闹钟",
            subtitle: "众筹中 · 20 元支持",
            emotionalPromise: "明天会更难起，就今晚早点被温柔提醒。",
            detail: "未来会根据明天雨雪、通勤压力和建议起床时间，提前提醒你该准备睡觉，把明早的压力挪到今晚轻轻解决。",
            symbolName: "alarm.fill",
            supportAmount: 20,
            accent: Color(red: 0.09, green: 0.52, blue: 0.48)
        )
    ]
}

@available(iOS 26.0, *)
private struct CrowdfundingHeroView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("一起把智能闹钟做成更懂你的早晨管家")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color(red: 0.07, green: 0.13, blue: 0.22))

            Text("AI 催眠 98 元众筹，其他服务 20 元众筹。你不是在买一个还没做完的按钮，而是在提前锁定一个会让生活更轻一点的能力；正式上线定价时，已支持金额可抵扣。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                CrowdfundingPill(text: "众筹中")
                CrowdfundingPill(text: "可抵扣")
                CrowdfundingPill(text: "StoreKit 支付")
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.99, green: 0.95, blue: 0.88),
                    Color(red: 0.89, green: 0.98, blue: 0.97),
                    Color(red: 0.93, green: 0.95, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black.opacity(0.06))
        }
        .padding(.vertical, 4)
    }
}

private struct CrowdfundingPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color(red: 0.07, green: 0.37, blue: 0.35))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CrowdfundingFeatureRow: View {
    let feature: CrowdfundingFeature
    let isSupported: Bool

    var body: some View {
        HStack(spacing: 12) {
            CrowdfundingFeatureIcon(feature: feature, size: 50)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(feature.title)
                        .font(.headline)

                    Text(isSupported ? "已支持" : "众筹中")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isSupported ? .green : .orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            (isSupported ? Color.green : Color.orange).opacity(0.12),
                            in: Capsule()
                        )
                }

                Text(isSupported ? "已锁定 \(feature.supportAmount) 元抵扣权益" : feature.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(feature.emotionalPromise)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}

private struct CrowdfundingFeatureIcon: View {
    let feature: CrowdfundingFeature
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            feature.accent.opacity(0.95),
                            Color(red: 0.06, green: 0.08, blue: 0.13)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(feature.accent.opacity(0.36))
                .frame(width: size * 0.78, height: size * 0.78)
                .blur(radius: 10)

            Image(systemName: feature.symbolName)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: feature.accent.opacity(0.24), radius: 12, y: 6)
    }
}

@available(iOS 26.0, *)
private struct CrowdfundingCheckoutView: View {
    @ObservedObject var store: StoreKitSubscriptionStore
    let feature: CrowdfundingFeature
    let isSupported: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        CrowdfundingFeatureIcon(feature: feature, size: 68)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(feature.title)
                                .font(.system(size: 27, weight: .bold))

                            Text(feature.emotionalPromise)
                                .font(.headline)
                                .foregroundStyle(feature.accent)

                            Text(feature.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Text("现在支持 \(feature.supportAmount) 元，正式上线后可抵扣这个服务的定价。你会成为这项功能的早期支持者，也会帮它更快从愿望清单变成真实能力。")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color(red: 0.42, green: 0.25, blue: 0.04))
                            .padding(12)
                            .background(Color(red: 1.0, green: 0.93, blue: 0.74), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    if isSupported {
                        Label("你已支持，\(feature.supportAmount) 元抵扣权益已记录", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else if let product = store.product(for: feature.productID) {
                        Button {
                            Task {
                                let didPurchase = await store.purchase(product)
                                if didPurchase {
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("支持 \(feature.supportAmount) 元，锁定抵扣权益")
                                        .font(.headline)

                                    Text("将打开 Apple StoreKit 系统支付")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(product.displayPrice)
                                    .font(.headline)
                            }
                        }
                        .disabled(store.state == .purchasing)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("等待 App Store Connect 商品配置")
                                .font(.headline)

                            Text("请先创建产品 ID：\(feature.productID)。配置完成后，这里会显示 \(feature.supportAmount) 元 StoreKit 支付按钮。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("众筹权益仅用于该服务正式上线后的价格抵扣，不可转让或跨服务使用。")
                }

                if case .failed(let message) = store.state {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("支持众筹")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}
