import Foundation
import Combine

/// UI Toast 事件通道。
///
/// AlarmManager 负责业务错误判断，但不直接持有 SwiftUI View。
/// ViewModel 或根 View 可以监听具体实现并显示 Toast。
@MainActor
protocol ToastPresenting: AnyObject {
    func showToast(_ message: String)
}

/// 默认实现：什么都不显示。
///
/// 后台任务运行时没有前台 UI，此实现可以避免后台代码强行展示 UI。
@MainActor
final class NoopToastPresenter: ToastPresenting {
    func showToast(_ message: String) {}
}

/// SwiftUI 可观察 Toast 中心。
///
/// 在前台页面中注入这个对象到 AlarmManager，View 监听 `message` 后弹出 Toast。
@MainActor
final class ToastMessageCenter: ObservableObject, ToastPresenting {
    @Published var message: String?
    private var dismissTask: Task<Void, Never>?

    func showToast(_ message: String) {
        showToast(message, duration: .seconds(4))
    }

    func showToast(_ message: String, duration: Duration = .seconds(4)) {
        dismissTask?.cancel()
        self.message = nil
        self.message = message
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                self?.message = nil
            }
        }
    }

    func clear() {
        dismissTask?.cancel()
        message = nil
    }
}
