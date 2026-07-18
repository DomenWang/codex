import SwiftUI

struct ToastViewModifier: ViewModifier {
    @Binding var message: String?
    let actionTitle: String?
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content

            if let message {
                HStack(spacing: 12) {
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)

                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(Color.cyan)
                    }
                }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 340, alignment: .leading)
                    .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: message)
    }
}

extension View {
    func toast(message: Binding<String?>) -> some View {
        modifier(ToastViewModifier(message: message, actionTitle: nil, action: nil))
    }

    func toast(
        message: Binding<String?>,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        modifier(ToastViewModifier(message: message, actionTitle: actionTitle, action: action))
    }
}
