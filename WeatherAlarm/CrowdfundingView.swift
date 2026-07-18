import StoreKit
import SwiftUI

@available(iOS 26.0, *)
struct CrowdfundingView: View {
    @ObservedObject var store: StoreKitSubscriptionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedFeature: CrowdfundingFeature?
    @State private var hasEntered = false

    private let features = CrowdfundingFeature.all

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                CrowdfundingHeroView(
                    isVisible: hasEntered,
                    reduceMotion: reduceMotion
                )

                ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                    Button {
                        selectedFeature = feature
                    } label: {
                        CrowdfundingFeatureRow(
                            feature: feature,
                            isSupported: store.supportedCrowdfundingProductIDs.contains(feature.productID)
                        )
                    }
                    .buttonStyle(CrowdfundingPressButtonStyle(reduceMotion: reduceMotion))
                    .crowdfundingEntrance(
                        isVisible: hasEntered,
                        delay: 0.22 + (Double(index) * 0.08),
                        reduceMotion: reduceMotion
                    )
                }

                Text("支持金额会记录为对应功能抵扣权益，正式上线后自动抵扣。支付成功后会立即记录到本机权益。")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.56))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 18)
                    .crowdfundingEntrance(
                        isVisible: hasEntered,
                        delay: 0.48,
                        reduceMotion: reduceMotion
                    )

                if case .failed(let message) = store.state {
                    Text(message)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(red: 1.00, green: 0.48, blue: 0.56))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
        }
        .navigationTitle("功能众筹")
        .navigationBarTitleDisplayMode(.inline)
        .background(
            CrowdfundingBackground(
                isVisible: hasEntered,
                reduceMotion: reduceMotion
            )
        )
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $selectedFeature) { feature in
            CrowdfundingCheckoutView(
                store: store,
                feature: feature,
                isSupported: store.supportedCrowdfundingProductIDs.contains(feature.productID)
            )
        }
        .task {
            store.startLoadingProductsAndEntitlements()
            guard !hasEntered else { return }

            if !reduceMotion {
                do {
                    try await Task.sleep(nanoseconds: 70_000_000)
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            hasEntered = true
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
            accent: Color(red: 0.72, green: 0.34, blue: 0.78)
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
            accent: Color(red: 0.96, green: 0.54, blue: 0.12)
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
            accent: Color(red: 0.12, green: 0.68, blue: 0.46)
        )
    ]
}

@available(iOS 26.0, *)
private struct CrowdfundingHeroView: View {
    let isVisible: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("早期支持者专属")
                .font(.caption.weight(.black))
                .tracking(1)
                .foregroundStyle(Color(red: 0.55, green: 1.00, blue: 0.78))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.10), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
                .crowdfundingEntrance(
                    isVisible: isVisible,
                    delay: 0,
                    reduceMotion: reduceMotion
                )

            Text("把下一个功能\n提前做出来")
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
                .crowdfundingEntrance(
                    isVisible: isVisible,
                    delay: 0.06,
                    reduceMotion: reduceMotion
                )

            CrowdfundingSaleBadge(
                isVisible: isVisible,
                reduceMotion: reduceMotion
            )
                .padding(.vertical, 2)

            Text("现在支持，未来上线后自动抵扣对应功能。你不是在等功能做好，而是在把它更快推到自己手里。")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.74))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .crowdfundingEntrance(
                    isVisible: isVisible,
                    delay: 0.15,
                    reduceMotion: reduceMotion
                )

            HStack(spacing: 9) {
                CrowdfundingPill(text: "可抵扣")
                CrowdfundingPill(text: "早期权益")
                CrowdfundingPill(text: "系统支付")
            }
            .crowdfundingEntrance(
                isVisible: isVisible,
                delay: 0.20,
                reduceMotion: reduceMotion
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .padding(.bottom, 24)
    }
}

private struct CrowdfundingPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.86))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.white.opacity(0.10), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
    }
}

private struct CrowdfundingFeatureRow: View {
    let feature: CrowdfundingFeature
    let isSupported: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 13) {
                CrowdfundingFeatureIcon(feature: feature, size: 52)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(feature.title)
                            .font(.headline.weight(.black))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(isSupported ? "已支持" : "众筹中")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(isSupported ? Color(red: 0.52, green: 1.00, blue: 0.72) : Color(red: 1.00, green: 0.84, blue: 0.42))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.10), in: Capsule())

                        Spacer(minLength: 0)
                    }

                    Text(isSupported ? "已锁定 \(feature.supportAmount) 元抵扣权益" : "支持 \(feature.supportAmount) 元，未来上线自动抵扣")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(feature.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.34))
                    .padding(.top, 8)
            }

            Text(feature.emotionalPromise)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.76))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    feature.accent.opacity(0.26),
                    Color(red: 0.09, green: 0.09, blue: 0.13).opacity(0.96),
                    Color(red: 0.03, green: 0.03, blue: 0.06).opacity(0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: feature.accent.opacity(0.22), radius: 18, y: 10)
    }
}

private struct CrowdfundingFeatureIcon: View {
    let feature: CrowdfundingFeature
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            feature.accent.opacity(0.95),
                            Color(red: 1.00, green: 0.27, blue: 0.40).opacity(0.90)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            Image(systemName: feature.symbolName)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: feature.accent.opacity(0.42), radius: 14, y: 8)
    }
}

@available(iOS 26.0, *)
private struct CrowdfundingCheckoutView: View {
    @ObservedObject var store: StoreKitSubscriptionStore
    let feature: CrowdfundingFeature
    let isSupported: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasEntered = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 18) {
                        CrowdfundingFeatureIcon(feature: feature, size: 74)

                        Text(feature.title)
                            .font(.system(size: 32, weight: .black))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.82)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(feature.emotionalPromise)
                            .font(.headline.weight(.black))
                            .foregroundStyle(feature.accent)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(feature.detail)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.74))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("现在支持 \(feature.supportAmount) 元，正式上线后可抵扣这个服务的定价。你会成为这项功能的早期支持者，也会帮它更快从愿望清单变成真实能力。")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white.opacity(0.82))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(14)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: [
                                feature.accent.opacity(0.28),
                                Color(red: 0.11, green: 0.09, blue: 0.18).opacity(0.96),
                                Color(red: 0.03, green: 0.03, blue: 0.06).opacity(0.98)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(.white.opacity(0.13), lineWidth: 1)
                    }
                    .shadow(color: feature.accent.opacity(0.24), radius: 24, y: 12)
                    .crowdfundingEntrance(
                        isVisible: hasEntered,
                        delay: 0.02,
                        reduceMotion: reduceMotion
                    )

                    if isSupported {
                        Label("你已支持，\(feature.supportAmount) 元抵扣权益已记录", systemImage: "checkmark.seal.fill")
                            .font(.headline.weight(.black))
                            .foregroundStyle(Color(red: 0.52, green: 1.00, blue: 0.72))
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .crowdfundingEntrance(
                                isVisible: hasEntered,
                                delay: 0.12,
                                reduceMotion: reduceMotion
                            )
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
                                        .font(.headline.weight(.black))
                                        .foregroundStyle(.white)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text("将打开系统支付")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.70))
                                }

                                Spacer()

                                Text(product.displayPrice)
                                    .font(.headline.weight(.black))
                                    .foregroundStyle(.white)
                            }
                            .padding(17)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.00, green: 0.18, blue: 0.30),
                                        Color(red: 1.00, green: 0.36, blue: 0.48)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                            )
                        }
                        .buttonStyle(CrowdfundingPressButtonStyle(reduceMotion: reduceMotion))
                        .disabled(store.state == .purchasing)
                        .crowdfundingEntrance(
                            isVisible: hasEntered,
                            delay: 0.12,
                            reduceMotion: reduceMotion
                        )
                    } else {
                        Button {
                            store.startLoadingProductsAndEntitlements()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("为我保留这个早期支持名额")
                                        .font(.headline.weight(.black))
                                        .foregroundStyle(.white)

                                    Text("轻点刷新 \(feature.supportAmount) 元支持方案，准备好后即可通过系统安全支付。")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.70))
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 4)

                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(feature.accent)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(CrowdfundingPressButtonStyle(reduceMotion: reduceMotion))
                        .crowdfundingEntrance(
                            isVisible: hasEntered,
                            delay: 0.12,
                            reduceMotion: reduceMotion
                        )
                    }

                    Text("众筹权益仅用于该服务正式上线后的价格抵扣，不可转让或跨服务使用。")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.56))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .crowdfundingEntrance(
                            isVisible: hasEntered,
                            delay: 0.18,
                            reduceMotion: reduceMotion
                        )

                if case .failed(let message) = store.state {
                        Text(message)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color(red: 1.00, green: 0.48, blue: 0.56))
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
                .padding(18)
                .padding(.top, 14)
            }
            .navigationTitle("支持众筹")
            .navigationBarTitleDisplayMode(.inline)
            .background(
                CrowdfundingBackground(
                    isVisible: hasEntered,
                    reduceMotion: reduceMotion
                )
            )
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundStyle(.white.opacity(0.86))
                }
            }
            .task {
                guard !hasEntered else { return }

                if !reduceMotion {
                    do {
                        try await Task.sleep(nanoseconds: 55_000_000)
                    } catch {
                        return
                    }
                }

                guard !Task.isCancelled else { return }
                hasEntered = true
            }
        }
    }
}

private struct CrowdfundingBackground: View {
    let isVisible: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Color(red: 0.01, green: 0.01, blue: 0.02)
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color(red: 0.24, green: 0.10, blue: 0.75).opacity(0.42),
                    Color.clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 360
            )
            .scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : 0.92), anchor: .top)
            .opacity(isVisible ? 1 : 0.58)
            .ignoresSafeArea()
            .animation(
                reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.85),
                value: isVisible
            )

            RadialGradient(
                colors: [
                    Color(red: 1.00, green: 0.17, blue: 0.32).opacity(0.18),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 40,
                endRadius: 320
            )
            .scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : 0.94), anchor: .bottomTrailing)
            .opacity(isVisible ? 1 : 0.48)
            .ignoresSafeArea()
            .animation(
                reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.95).delay(0.06),
                value: isVisible
            )
        }
    }
}

private struct CrowdfundingSaleBadge: View {
    let isVisible: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(red: 0.84, green: 0.62, blue: 1.00).opacity(0.44), lineWidth: 2)
                .frame(width: 138, height: 138)
                .scaleEffect(reduceMotion ? 1 : (isVisible ? 1.26 : 0.78))
                .opacity(isVisible ? 0 : 0.42)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.82).delay(0.08),
                    value: isVisible
                )

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.74, green: 0.55, blue: 1.00),
                            Color(red: 0.97, green: 0.42, blue: 0.93)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 128, height: 128)
                .shadow(color: Color(red: 0.63, green: 0.25, blue: 1.00).opacity(0.48), radius: 34)
                .scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : 0.76))
                .rotationEffect(.degrees(reduceMotion ? 0 : (isVisible ? 0 : -7)))
                .opacity(isVisible ? 1 : 0)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.16)
                        : .spring(response: 0.58, dampingFraction: 0.70).delay(0.08),
                    value: isVisible
                )

            VStack(spacing: 2) {
                Text("Support")
                    .font(.headline.weight(.black))
                Text("抵扣")
                    .font(.system(size: 34, weight: .black))
            }
            .foregroundStyle(.white)
            .scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : 0.82))
            .opacity(isVisible ? 1 : 0)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.16)
                    : .spring(response: 0.56, dampingFraction: 0.74).delay(0.12),
                value: isVisible
            )

            ForEach(0..<8, id: \.self) { index in
                let finalOffset = confettiOffset(index)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(confettiColor(index))
                    .frame(width: index.isMultiple(of: 2) ? 5 : 4, height: index.isMultiple(of: 2) ? 18 : 13)
                    .rotationEffect(.degrees(
                        (Double(index) * 31) + (reduceMotion || isVisible ? 0 : -18)
                    ))
                    .offset(
                        x: reduceMotion || isVisible ? finalOffset.width : finalOffset.width * 0.24,
                        y: reduceMotion || isVisible ? finalOffset.height : finalOffset.height * 0.24
                    )
                    .scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : 0.36))
                    .opacity(isVisible ? 1 : 0)
                    .animation(
                        reduceMotion
                            ? .easeOut(duration: 0.14)
                            : .spring(
                                response: 0.62,
                                dampingFraction: 0.72
                            ).delay(0.12 + (Double(index) * 0.018)),
                        value: isVisible
                    )
            }
        }
        .frame(height: 174)
    }

    private func confettiColor(_ index: Int) -> Color {
        [Color.yellow, Color(red: 1.00, green: 0.48, blue: 0.16), Color(red: 0.64, green: 0.42, blue: 1.00), Color(red: 0.20, green: 0.68, blue: 1.00)][index % 4]
    }

    private func confettiOffset(_ index: Int) -> CGSize {
        let points = [
            CGSize(width: -122, height: -28),
            CGSize(width: 116, height: -16),
            CGSize(width: -88, height: 60),
            CGSize(width: 94, height: 70),
            CGSize(width: -34, height: 84),
            CGSize(width: 42, height: -78),
            CGSize(width: -138, height: 76),
            CGSize(width: 136, height: 42)
        ]
        return points[index % points.count]
    }
}

private struct CrowdfundingEntranceModifier: ViewModifier {
    let isVisible: Bool
    let delay: Double
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (isVisible ? 0 : 18))
            .scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : 0.975))
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.14)
                    : .spring(response: 0.54, dampingFraction: 0.84).delay(delay),
                value: isVisible
            )
    }
}

private extension View {
    func crowdfundingEntrance(
        isVisible: Bool,
        delay: Double,
        reduceMotion: Bool
    ) -> some View {
        modifier(
            CrowdfundingEntranceModifier(
                isVisible: isVisible,
                delay: delay,
                reduceMotion: reduceMotion
            )
        )
    }
}

private struct CrowdfundingPressButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.80),
                value: configuration.isPressed
            )
    }
}
