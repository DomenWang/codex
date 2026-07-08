import SwiftUI

@available(iOS 26.0, *)
struct InviteView: View {
    @StateObject private var referralStateStore = ReferralStateStore()
    @State private var invitedCount = 0

    private var remainingCount: Int {
        max(0, 1 - invitedCount)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("已邀 \(invitedCount) 人，再邀 \(remainingCount) 人得 100 元永久立减券")
                            .font(.headline)

                        ProgressView(value: Double(min(invitedCount, 1)), total: 1)

                        Text("好友买 298 永久买断可用 50 元券；你获得 100 元永久立减券，购买 298 永久买断实付 198 元。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Text("每邀 1 位好友完成购买，你得 100 元永久立减券，TA 得 50 元代金券（仅可用于天气永久买断/高德增强）~")
                        .foregroundStyle(.secondary)

                    ShareLink(item: referralStateStore.inviteURL) {
                        Label("分享邀请链接", systemImage: "square.and.arrow.up")
                    }
                } footer: {
                    Text("代金券不可用于天气月/年订阅，不可叠加使用。奖励仅为立减券/代金券，不可兑换其他权益或转赠。")
                }
            }
            .navigationTitle("邀请好友")
        }
    }
}

#Preview {
    if #available(iOS 26.0, *) {
        InviteView()
    }
}
