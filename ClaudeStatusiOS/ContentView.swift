import SwiftUI
import ClaudeStatusCore

struct ContentView: View {
    @State private var snapshot = ResetTimeSync.read()
    @State private var showingSettings = false
    @AppStorage("iosNotificationsEnabled") private var notificationsEnabled = true
    @AppStorage("iosNotificationSound") private var notificationSound: String = "default"

    /// Refresh the snapshot every second so the percentage and timer stay in sync.
    /// (The Text(date, style: .timer) ticks on its own, but this re-reads iCloud KV in case
    /// the Mac just published a new reset date.)
    let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        let accent = ThemeStore.readAccentColor(forUtilization: snapshot.utilization)
        ZStack {
            Rectangle()
                .fill(ThemeStore.readBackgroundStyle())
                .ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "hourglass")
                        .foregroundStyle(Color(white: 0.55))
                    Text("CLAUDE STATUS")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(Color(white: 0.55))
                    Spacer()
                    Button { showingSettings = true } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(white: 0.55))
                    }
                }
                .padding(.horizontal)
                Spacer()
                ZStack {
                    UsageDonut(utilization: snapshot.utilization ?? 0,
                               diameter: 260,
                               strokeWidth: 18) { EmptyView() }
                    VStack(spacing: 6) {
                        Text("Current Session resets in")
                            .font(.caption)
                            .foregroundStyle(Color(white: 0.55))
                        if let d = snapshot.resetDate {
                            Text(d, style: .timer)
                                .font(.system(size: 44, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(accent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        } else {
                            Text("--:--")
                                .font(.system(size: 44, weight: .semibold, design: .rounded))
                                .foregroundStyle(accent.opacity(0.4))
                        }
                        if let u = snapshot.utilization {
                            Text("\(Int(u))% used")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(accent.opacity(0.7))
                        }
                    }
                }
                Spacer()
                Text("Synced from your Mac via iCloud")
                    .font(.caption2)
                    .foregroundStyle(Color(white: 0.4))
            }
            .padding(.vertical, 24)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings) { iOSSettingsView() }
        .onAppear {
            Task { _ = await NotificationManager.requestAuthorization() }
            snapshot = ResetTimeSync.read()
            scheduleNotification()
        }
        .onReceive(tick) { _ in
            let fresh = ResetTimeSync.read()
            if fresh.resetDate != snapshot.resetDate || fresh.utilization != snapshot.utilization {
                snapshot = fresh
                scheduleNotification()
            }
        }
    }

    private func scheduleNotification() {
        NotificationManager.scheduleResetNotification(
            at: snapshot.resetDate,
            enabled: notificationsEnabled,
            soundName: notificationSound
        )
    }
}
