import SwiftUI

@available(iOS 26.0, *)
struct InviteView: View {
    private static let inviteURL = ReferralStateStore().inviteURL
    private let invitedCount = 0

    private var remainingCount: Int {
        max(0, 1 - invitedCount)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SmartWakeAmbientBackdrop(style: .mist)

                ScrollView {
                    GlassEffectContainer(spacing: 18) {
                        LazyVStack(spacing: 18) {
                            hero
                            rewardFlow
                            shareCard
                            rulesCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("邀请好友")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(SmartWakeTheme.teal)
    }

    private var hero: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(SmartWakeTheme.teal.opacity(0.13))
                    .frame(width: 84, height: 84)
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(SmartWakeTheme.teal)
            }

            Text("一起把明早安排得更从容")
                .font(.title2.weight(.bold))
                .foregroundStyle(SmartWakeTheme.ink)
                .multilineTextAlignment(.center)

            Text("好友通过你的链接打开 SmartWake 可获得 50 元代金券；TA 完成天气永久买断后，你可获得 100 元永久立减券。")
                .font(.subheadline)
                .foregroundStyle(SmartWakeTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("已邀 \(invitedCount) 人")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Text(remainingCount == 0 ? "奖励已达成" : "再邀 \(remainingCount) 人")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SmartWakeTheme.tealDeep)
                }

                ProgressView(value: Double(min(invitedCount, 1)), total: 1)
                    .tint(SmartWakeTheme.teal)
            }
        }
        .padding(22)
        .smartWakeCrystalSurface(cornerRadius: 30, tint: SmartWakeTheme.teal)
    }

    private var rewardFlow: some View {
        HStack(spacing: 10) {
            rewardStep(symbol: "square.and.arrow.up.fill", title: "分享链接", tint: SmartWakeTheme.sky)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
            rewardStep(symbol: "iphone.gen3", title: "好友打开", tint: SmartWakeTheme.teal)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
            rewardStep(symbol: "ticket.fill", title: "双方得券", tint: SmartWakeTheme.sunrise)
        }
        .padding(18)
        .smartWakeCrystalSurface(cornerRadius: 24, tint: SmartWakeTheme.sky)
    }

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("你的专属邀请", systemImage: "link")
                .font(.headline.weight(.bold))
                .foregroundStyle(SmartWakeTheme.ink)

            Text("分享时会使用系统分享面板，你可以发送到信息、微信或其他已安装的 App。")
                .font(.subheadline)
                .foregroundStyle(SmartWakeTheme.secondaryInk)

            ShareLink(
                item: Self.inviteURL,
                subject: Text("SmartWake 好友邀请"),
                message: Text("和我一起用 SmartWake 安排更从容的早晨。打开链接可领取好友代金券。")
            ) {
                Label("分享邀请链接", systemImage: "square.and.arrow.up.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.glassProminent)
            .tint(SmartWakeTheme.teal)
        }
        .padding(18)
        .smartWakeCrystalSurface(cornerRadius: 24, tint: SmartWakeTheme.teal)
    }

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("奖励说明")
                .font(.headline.weight(.bold))
                .foregroundStyle(SmartWakeTheme.ink)

            rule("好友券在对方通过邀请链接打开 App 后发放。")
            rule("邀请人的 100 元券需要收到好友购买结果后发放。")
            rule("代金券仅用于天气永久买断或路径订阅，不用于天气月/年订阅，也不可叠加。")
        }
        .padding(18)
        .smartWakeCrystalSurface(cornerRadius: 24, tint: SmartWakeTheme.sunrise)
    }

    private func rewardStep(symbol: String, title: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: Circle())
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(SmartWakeTheme.secondaryInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func rule(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(SmartWakeTheme.sunrise)
                .padding(.top, 3)
            Text(text)
                .font(.footnote)
                .foregroundStyle(SmartWakeTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    if #available(iOS 26.0, *) {
        InviteView()
    }
}
