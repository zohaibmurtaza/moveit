import SwiftUI
import AppKit

/// First-launch tip pointing people at the menu bar icon (standard menu-bar app pattern).
struct WelcomeGuideView: View {
    var onContinue: () -> Void

    @State private var accessibilityTrusted = Permissions.hasAccessibility

    /// Matches WelcomeGuidePreview asset (tall menu-bar screenshot).
    private let previewAspect: CGFloat = 576.0 / 900.0
    private let previewWidth: CGFloat = 270

    private var previewHeight: CGFloat { previewWidth / previewAspect }

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            guideColumn
                .frame(width: 300, alignment: .leading)

            previewColumn
        }
        .padding(22)
        .fixedSize()
        .background(
            WindowAccessor { window in
                AppAppearance.tagControlsWindow(window)
                window.styleMask.remove(.resizable)
                if let fitting = window.contentView?.fittingSize, fitting.width > 0, fitting.height > 0 {
                    window.setContentSize(fitting)
                }
            }
        )
    }

    private var guideColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Image("AppMark")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    .accessibilityHidden(true)

                Text("MoveIt lives in the menu bar")
                    .font(.title2.weight(.semibold))

                Text("Look at the top of your screen for the cursor icon. Click it anytime to open controls — no Dock needed.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                tipRow("menubar.arrow.up.rectangle", "Click the cursor icon in the top-right menu bar")
                tipRow("slider.horizontal.3", "Start / stop activity and tweak settings")
                tipRow("dock.rectangle", "Closing this window hides MoveIt from the Dock")
            }

            permissionCard

            primaryButton
                .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .frame(minHeight: previewHeight + 16, alignment: .top)
    }

    private var permissionCard: some View {
        PermissionsView(isTrusted: $accessibilityTrusted)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accessibilityTrusted ? Color.green.opacity(0.08) : Color.orange.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        accessibilityTrusted ? Color.green.opacity(0.25) : Color.orange.opacity(0.25),
                        lineWidth: 1
                    )
            )
    }

    @ViewBuilder
    private var primaryButton: some View {
        if accessibilityTrusted {
            Button(action: onContinue) {
                Text("Got it — continue in menu bar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var previewColumn: some View {
        Image("WelcomeGuidePreview")
            .resizable()
            .interpolation(.high)
            .aspectRatio(previewAspect, contentMode: .fit)
            .frame(width: previewWidth)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .accessibilityLabel("Preview of the MoveIt menu bar controls")
    }

    private func tipRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
