import SwiftUI

struct PermissionsView: View {
    @Binding var isTrusted: Bool

    @State private var requestAttempts = 0
    @State private var pollTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: isTrusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .foregroundStyle(isTrusted ? .green : .orange)
                Text(isTrusted ? "Accessibility granted" : "Accessibility required")
                    .font(.callout.weight(.semibold))
            }

            if !isTrusted {
                Text("Grant Accessibility so MoveIt can inject test input. Enable MoveIt in System Settings, then this status updates automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Request Permission", action: requestPermission)
                        .controlSize(.small)

                    if requestAttempts >= 2 {
                        Button("Refresh", action: refresh)
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            refresh()
            startPolling()
        }
        .onDisappear {
            stopPolling()
        }
        .onChange(of: isTrusted) { trusted in
            if trusted {
                stopPolling()
            }
        }
    }

    private func requestPermission() {
        requestAttempts += 1
        // First try: system prompt only (it already has “Open System Settings”).
        // Later tries: open Settings directly — macOS often won’t show the modal again.
        if requestAttempts == 1 {
            _ = Permissions.ensureAccessibility(prompt: true)
        } else {
            Permissions.openAccessibilitySettings()
        }
        refresh()
        startPolling()
    }

    private func refresh() {
        isTrusted = Permissions.hasAccessibility
        if isTrusted {
            stopPolling()
        }
    }

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { _ in
            let trusted = Permissions.hasAccessibility
            DispatchQueue.main.async {
                if trusted != isTrusted {
                    isTrusted = trusted
                }
                if trusted {
                    stopPolling()
                }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
