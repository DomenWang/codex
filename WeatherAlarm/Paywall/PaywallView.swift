import StoreKit
import SwiftUI

@available(iOS 26.0, *)
struct PaywallView: View {
    @ObservedObject var store: StoreKitSubscriptionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    productRow(
                        id: WeatherAlarmProductID.monthly,
                        title: "月费",
                        fallbackPrice: "5 元"
                    )

                    productRow(
                        id: WeatherAlarmProductID.yearly,
                        title: "年费",
                        fallbackPrice: "50 元"
                    )

                    productRow(
                        id: WeatherAlarmProductID.lifetime,
                        title: "永久",
                        fallbackPrice: "198 元"
                    )
                }

                Section {
                    Button("恢复购买") {
                        Task {
                            await store.restorePurchases()
                            if store.hasPremiumAccess {
                                dismiss()
                            }
                        }
                    }
                }

                if case .failed(let message) = store.state {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("开启智能天气调整")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .task {
                await store.loadProductsAndEntitlements()
            }
            .onChange(of: store.hasPremiumAccess) { _, hasAccess in
                if hasAccess {
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private func productRow(
        id: String,
        title: String,
        fallbackPrice: String
    ) -> some View {
        if let product = store.product(for: id) {
            Button {
                Task {
                    await store.purchase(product)
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)

                        Text(product.displayName.isEmpty ? fallbackPrice : product.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(product.displayPrice)
                        .font(.headline)
                }
            }
            .disabled(store.state == .purchasing)
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    Text(fallbackPrice)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ProgressView()
            }
        }
    }
}

