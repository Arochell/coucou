import SwiftUI

// The island open in a corner of the screen (IslandPlacement): Mochi sits in the island's
// corner, the other pills' Mochis on a quarter circle around him, and the focused pill's card
// fills the rest. A tap on one of them swaps it with Mochi: it flies to the corner and becomes
// the one in focus, and the one that was in focus takes its place on the circle.

struct CornerArcView: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    let islandH: CGFloat

    /// The circle's order, kept across swaps (the one leaving the corner takes the place of the
    /// one arriving), new pills added at the end.
    @State private var order: [String] = []
    /// The Mochi flying to the corner, during the swap.
    @State private var flying: String? = nil

    /// Room for five around Mochi; the others are a tap on the circle away once one leaves it.
    static let maxShown = 5

    private var arcTasks: [AgentTask] {
        let focus = state.focusTask?.id
        let others = state.tasks.filter { $0.id != focus }
        let known = order.compactMap { id in others.first { $0.id == id } }
        let rest = others.filter { t in !order.contains(t.id) }
        return Array((known + rest).prefix(Self.maxShown))
    }

    var body: some View {
        let placement = state.islandPlacement
        let size = CGSize(width: islandW, height: islandH)
        let tasks = arcTasks
        let points = placement.arcPoints(count: tasks.count, in: size)
        let home = placement.cornerBotCenter(in: size)

        ZStack(alignment: .topLeading) {
            // A faint quarter of the circle the Mochis sit on.
            Path { p in
                let pts = placement.arcPoints(count: 9, in: size)
                guard let first = pts.first else { return }
                p.move(to: first)
                for q in pts.dropFirst() { p.addLine(to: q) }
            }
            .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 5]))
            .allowsHitTesting(false)

            ForEach(Array(tasks.enumerated()), id: \.element.id) { i, task in
                let isFlying = flying == task.id
                CornerMini(task: task) { swap(to: task, at: i, current: tasks) }
                    .scaleEffect(isFlying ? 1.45 : 1)
                    .opacity(isFlying ? 0 : 1)
                    .position(isFlying ? home : (i < points.count ? points[i] : home))
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: islandW, height: islandH, alignment: .topLeading)
        .clipped()
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: tasks.map(\.id))
        .animation(.spring(response: 0.26, dampingFraction: 0.85), value: flying)
    }

    private func swap(to task: AgentTask, at index: Int, current: [AgentTask]) {
        guard flying == nil else { return }
        var ids = current.map(\.id)
        if let focus = state.focusTask?.id, index < ids.count { ids[index] = focus }
        flying = task.id
        SoundEngine.shared.play("blip")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            order = ids
            state.setFocus(task.id)
            flying = nil
        }
    }
}

/// One pill's Mochi on the circle: a round button in its colour, its name on hover.
private struct CornerMini: View {
    let task: AgentTask
    let onTap: () -> Void
    @State private var hover = false

    private var name: String {
        task.id == "integration_claude" ? ClaudeHost.pillName(hostApp: task.hostApp) : task.name
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(hover ? Color(hex: task.color).opacity(0.18) : Color(hex: "#0E0F11"))
                    Circle()
                        .stroke(Color(hex: task.color).opacity(hover ? 0.6 : 0.22), lineWidth: 1.2)
                    MiniBotCanvasView(task: task)
                        .frame(width: 24 / 0.6, height: 24 / 0.6)
                        .frame(width: 24, height: 24)
                }
                .frame(width: 40, height: 40)
                .shadow(color: Color(hex: task.color).opacity(hover ? 0.35 : 0), radius: 10)

                if let badge = task.pillBadge {
                    PillBadgeView(badge: badge, taskColor: task.color)
                        .offset(x: 2, y: -2)
                }
            }
            .overlay(alignment: .bottom) {
                Text(verbatim: name)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(Color(hex: task.color).lighter(by: 0.3))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                    .offset(y: 18)
                    .opacity(hover ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(hover ? 1.1 : 1)
        .onHover { h in withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { hover = h } }
        .help(name)
    }
}

/// While Mochi is dragged near a corner (or back to the top centre): the place he will take,
/// shown before he is let go.
struct SnapTargetView: View {
    let corner: Bool
    @State private var shown = false

    var body: some View {
        RoundedRectangle(cornerRadius: corner ? 18 : 17, style: .continuous)
            .fill(Color.black.opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: corner ? 18 : 17, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
            .scaleEffect(shown ? 1 : 0.7)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { shown = true } }
    }
}
