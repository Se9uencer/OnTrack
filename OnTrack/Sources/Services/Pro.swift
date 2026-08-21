import Foundation

/// Single source of truth for the "OnTrack Pro" entitlement that gates the AI
/// features (Coach, daily insight, Photo Meal). Launch state: everyone is Pro
/// (AI is free). To monetize later, flip the default to false and replace this
/// with StoreKit currentEntitlements — the call-site guards don't change.
enum Pro {
    static let key = "isPro"
    static var isActive: Bool {
        // ponytail: UserDefaults-backed stub; swap for StoreKit.Transaction.currentEntitlements
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}
