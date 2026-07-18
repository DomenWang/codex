import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: AuthSessionViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("邮箱", text: $viewModel.email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("密码", text: $viewModel.password)
                        .textContentType(viewModel.isRegistering ? .newPassword : .password)

                    if viewModel.isRegistering {
                        TextField("昵称（可选）", text: $viewModel.displayName)
                            .textContentType(.name)
                    }
                }

                Section {
                    Button {
                        Task {
                            await viewModel.submit()
                        }
                    } label: {
                        HStack {
                            Text(viewModel.isRegistering ? "创建账号" : "登录")

                            if viewModel.state == .authenticating {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(viewModel.state == .authenticating)

                    Button(viewModel.isRegistering ? "已有账号，去登录" : "没有账号，注册") {
                        viewModel.isRegistering.toggle()
                        viewModel.message = nil
                    }
                }

                if let message = viewModel.message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Text("登录后可以同步订阅权益和闹钟设置，换手机也能继续使用。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background {
                if #available(iOS 26.0, *) {
                    SmartWakeAmbientBackdrop(style: .mist)
                } else {
                    Color(uiColor: .systemGroupedBackground)
                }
            }
            .navigationTitle("智能闹钟")
        }
        .tint(
            {
                if #available(iOS 26.0, *) {
                    return SmartWakeTheme.teal
                }
                return Color.accentColor
            }()
        )
    }
}

#Preview {
    LoginView(viewModel: AuthSessionViewModel())
}
