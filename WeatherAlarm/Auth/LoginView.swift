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
                    Text("账号系统会通过你的后端 HTTPS API 登录，访问令牌保存在 iOS Keychain。请先部署 auth-backend 并配置 AuthAPIBaseURL。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("智能闹钟")
        }
    }
}

#Preview {
    LoginView(viewModel: AuthSessionViewModel())
}
