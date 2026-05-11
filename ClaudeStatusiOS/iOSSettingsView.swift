import SwiftUI
import ClaudeStatusCore

struct iOSSettingsView: View {
    @AppStorage("iosNotificationsEnabled") private var notificationsEnabled = true
    @AppStorage("iosNotificationSound") private var notificationSound: String = "default"
    @Environment(\.dismiss) private var dismiss

    /// iOS system sound names that work with UNNotificationSound(named:)
    private let sounds: [(label: String, value: String)] = [
        ("Default", "default"),
        ("Bell.caf", "Bell.caf"),
        ("Tritone.caf", "Tritone.caf"),
        ("Note.caf", "Note.caf"),
        ("Glass.caf", "Glass.caf"),
        ("Suspense.caf", "Suspense.caf"),
        ("None (silent)", ""),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Notifications") {
                    Toggle("Alert me when session resets", isOn: $notificationsEnabled)
                    Picker("Sound", selection: $notificationSound) {
                        ForEach(sounds, id: \.value) { s in
                            Text(s.label).tag(s.value)
                        }
                    }
                    .disabled(!notificationsEnabled)
                }
                Section("About") {
                    Text("Claude Status iOS").font(.subheadline)
                    Text("Reads your 5h reset time from your Mac via iCloud.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
