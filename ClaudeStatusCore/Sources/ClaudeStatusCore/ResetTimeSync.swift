import Foundation

/// Cross-platform helper for sharing the next 5h reset date across devices.
///
/// On macOS, the main app writes the reset date here whenever it polls.
/// On iOS, the widget/app reads from here.
///
/// Storage is iCloud Key-Value Store (NSUbiquitousKeyValueStore). On both platforms it also
/// writes to UserDefaults.standard as a local fallback so the data survives without iCloud
/// (useful in the iOS Simulator where iCloud may not be configured, and on macOS as a
/// belt-and-suspenders backup).
public enum ResetTimeSync {
    public static let resetDateKey = "fiveHourResetDate"
    public static let utilizationKey = "fiveHourUtilization"

    // MARK: - Write (macOS side calls this from UsageStore)

    public static func write(resetDate: Date?, utilization: Double?) {
        let kv = NSUbiquitousKeyValueStore.default
        let local = UserDefaults.standard

        if let d = resetDate {
            let interval = d.timeIntervalSince1970
            kv.set(interval, forKey: resetDateKey)
            local.set(interval, forKey: resetDateKey)
        } else {
            kv.removeObject(forKey: resetDateKey)
            local.removeObject(forKey: resetDateKey)
        }

        if let u = utilization {
            kv.set(u, forKey: utilizationKey)
            local.set(u, forKey: utilizationKey)
        }
        kv.synchronize()
    }

    // MARK: - Read (iOS side calls this from widget timeline / app view)

    public struct Snapshot {
        public let resetDate: Date?
        public let utilization: Double?
        public init(resetDate: Date?, utilization: Double?) {
            self.resetDate = resetDate
            self.utilization = utilization
        }
    }

    /// Read the latest synced values. Prefers iCloud KV, falls back to local UserDefaults,
    /// then to a development mock so the Simulator has something to render.
    public static func read() -> Snapshot {
        let kv = NSUbiquitousKeyValueStore.default
        let local = UserDefaults.standard

        // Force iCloud to pull the latest from server (safe to call frequently)
        kv.synchronize()

        let resetInterval = kv.double(forKey: resetDateKey)
        let localResetInterval = local.double(forKey: resetDateKey)
        let resetDate: Date? = {
            if resetInterval > 0 { return Date(timeIntervalSince1970: resetInterval) }
            if localResetInterval > 0 { return Date(timeIntervalSince1970: localResetInterval) }
            #if DEBUG && os(iOS)
            // Simulator/dev: pretend session resets in 4 hours so UI has data to show
            return Date().addingTimeInterval(4 * 3600)
            #else
            return nil
            #endif
        }()

        let utilFromCloud = kv.double(forKey: utilizationKey)
        let utilFromLocal = local.double(forKey: utilizationKey)
        let utilization: Double? = {
            if utilFromCloud > 0 { return utilFromCloud }
            if utilFromLocal > 0 { return utilFromLocal }
            #if DEBUG && os(iOS)
            return 47.0  // dev mock
            #else
            return nil
            #endif
        }()

        return Snapshot(resetDate: resetDate, utilization: utilization)
    }
}
