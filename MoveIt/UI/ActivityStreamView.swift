import SwiftUI

/// Fixed-slot conveyor: past ← now → next. Events slide right-to-left when the
/// current action changes — layout width never grows with history.
struct ActivityStreamView: View {
    let past: [ActivityEvent]
    let current: ActivityEvent?
    let upcoming: [ActivityEvent]

    private let pastSlots = 3
    private let nextSlots = 3
    private let slotWidth: CGFloat = 70
    private let rowHeight: CGFloat = 92

    @Namespace private var streamNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Past")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Now")
                    .font(.caption2.weight(.semibold))
                Spacer()
                Text("Next")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)

            ZStack {
                conveyor
                    .frame(width: totalWidth, height: rowHeight)
                    .clipped()
                    .mask(edgeFadeMask)

                // Stable center highlight — chips slide underneath.
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
                    .frame(width: slotWidth + 10, height: rowHeight - 10)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
            .nativeGlassCard(cornerRadius: 14)

            currentCaption
        }
    }

    private var totalWidth: CGFloat {
        CGFloat(pastSlots + 1 + nextSlots) * slotWidth
    }

    private var conveyor: some View {
        HStack(spacing: 0) {
            ForEach(timeline) { entry in
                slotView(entry)
                    .frame(width: slotWidth, height: rowHeight)
            }
        }
        .animation(.spring(response: 0.48, dampingFraction: 0.86), value: timeline.map(\.animationID))
    }

    @ViewBuilder
    private func slotView(_ entry: TimelineEntry) -> some View {
        switch entry {
        case .event(let event, let role):
            eventChip(event, role: role)
                .matchedGeometryEffect(id: event.id, in: streamNamespace, properties: .position, anchor: .center, isSource: true)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    )
                )
        case .empty:
            Color.clear
        }
    }

    @ViewBuilder
    private var currentCaption: some View {
        if let current {
            HStack(spacing: 8) {
                Image(systemName: current.kind.systemImage)
                    .foregroundStyle(tint(for: current.kind))
                Text(current.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .animation(.easeInOut(duration: 0.2), value: current.id)
        } else {
            Text("Start simulation to see live activity.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var edgeFadeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .black],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 40)
            Rectangle().fill(.black)
            LinearGradient(
                colors: [.black, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 40)
        }
    }

    // MARK: - Timeline (always pastSlots + 1 + nextSlots)

    private enum SlotRole {
        case past, now, next
    }

    private enum TimelineEntry: Identifiable, Equatable {
        case event(ActivityEvent, role: SlotRole)
        case empty(id: String)

        var id: String {
            switch self {
            case .event(let event, _): return event.id.uuidString
            case .empty(let id): return id
            }
        }

        var animationID: String { id }
    }

    private var timeline: [TimelineEntry] {
        var entries: [TimelineEntry] = []
        let pastSlice = Array(past.suffix(pastSlots))
        let pastPad = pastSlots - pastSlice.count
        for i in 0..<pastPad {
            entries.append(.empty(id: "pad-past-\(i)"))
        }
        for event in pastSlice {
            entries.append(.event(event, role: .past))
        }

        if let current {
            entries.append(.event(current, role: .now))
        } else {
            entries.append(.empty(id: "now-empty"))
        }

        let nextSlice = Array(upcoming.prefix(nextSlots))
        for event in nextSlice {
            entries.append(.event(event, role: .next))
        }
        for i in nextSlice.count..<nextSlots {
            entries.append(.empty(id: "pad-next-\(i)"))
        }
        return entries
    }

    private func eventChip(_ event: ActivityEvent, role: SlotRole) -> some View {
        let isNow = role == .now
        let scale: CGFloat = isNow ? 1.0 : (role == .past ? 0.86 : 0.9)
        let opacity: Double = isNow ? 1.0 : (role == .past ? 0.55 : 0.7)

        return VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(tint(for: event.kind).opacity(isNow ? 0.24 : 0.12))
                    .frame(width: isNow ? 40 : 30, height: isNow ? 40 : 30)
                Image(systemName: event.kind.systemImage)
                    .font(isNow ? .body.weight(.semibold) : .caption.weight(.semibold))
                    .foregroundStyle(tint(for: event.kind))
            }
            Text(shortLabel(for: event))
                .font(isNow ? .caption2.weight(.semibold) : .system(size: 9, weight: .medium))
                .foregroundStyle(isNow ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: slotWidth - 8)
        }
        .scaleEffect(scale)
        .opacity(opacity)
    }

    private func shortLabel(for event: ActivityEvent) -> String {
        switch event.kind {
        case .mouse:
            if event.title.localizedCaseInsensitiveContains("jitter") { return "Jitter" }
            return "Mouse"
        case .scroll: return "Scroll"
        case .keyboard: return "Keys"
        case .silentKeys: return "Silent"
        case .appSwitch: return "Switch"
        case .waiting: return "Wait"
        case .skipped: return "Skip"
        }
    }

    private func tint(for kind: ActivityKind) -> Color {
        switch kind {
        case .mouse: return .blue
        case .scroll: return .cyan
        case .keyboard: return .purple
        case .silentKeys: return .indigo
        case .appSwitch: return .orange
        case .waiting: return .secondary
        case .skipped: return .secondary
        }
    }
}
