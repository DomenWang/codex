import Combine
import Foundation
import UIKit

final class ReferralStateStore: ObservableObject {
    private let defaults: UserDefaults
    private let referrerIDKey = "referrer_id"
    private let inviterIDKey = "ww_inviter_id"
    private let pendingFriendCouponKey = "ww_pending_friend_coupon"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var referrerID: UUID? {
        guard let rawValue = defaults.string(forKey: referrerIDKey) else {
            return nil
        }

        return UUID(uuidString: rawValue)
    }

    var inviterID: UUID {
        if let rawValue = defaults.string(forKey: inviterIDKey),
           let id = UUID(uuidString: rawValue) {
            return id
        }

        let id = UUID()
        defaults.set(id.uuidString, forKey: inviterIDKey)
        return id
    }

    var inviteURL: URL {
        URL(string: "weatherwake://invite?ref=\(inviterID.uuidString)")!
    }

    func handleInviteURL(_ url: URL) {
        guard url.scheme == "weatherwake",
              url.host == "invite",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let refValue = components.queryItems?.first(where: { $0.name == "ref" })?.value,
              let referrerID = UUID(uuidString: refValue),
              referrerID != inviterID else {
            return
        }

        defaults.set(referrerID.uuidString, forKey: referrerIDKey)
        defaults.set(UIDevice.current.identifierForVendor?.uuidString, forKey: "ww_invite_idfv")
        defaults.set(true, forKey: pendingFriendCouponKey)
    }
}
