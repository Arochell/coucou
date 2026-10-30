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
    /// Two Mochis swapping places: the one arriving in the corner and the one leaving it.
    @State private var swap: Swap? = nil
    @State private var swapStart = Date.distantPast

    private struct Swap: Equatable {
        let incoming: AgentTask
        let outgoing: AgentTask
        let slot: Int
        let order: [String]
        static func == (a: Swap, b: Swap) -> Bool { a.incoming.id == b.incoming.id && a.slot == b.slot }
    }

    /// Room for five around Mochi; the others are a tap on the circle away once one leaves it.
    static let maxShown = 5
    /// Mochi's size in the corner, and on the circle (the swap grows one and shrinks the other).
    static let bigBody: CGFloat = 58
    static let smallBody: CGFloat = 24
    static let swapDuration: Double = 0.55

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
                let leaving = swap?.incoming.id == task.id
                CornerMini(task: task) { start(task, at: i, current: tasks) }
                    // Its Mochi is on its way to the corner (drawn below): the button stays empty.
                    .opacity(leaving ? 0 : 1)
                    .position(i < points.count ? points[i] : home)
                    .transition(.opacity)
            }

            // The swap: each one on its own curve, crossing the other halfway.
            if let s = swap, s.slot < points.count {
                let slot = points[s.slot]
                let small = Self.smallBody / Self.bigBody
                TimelineView(.animation) { tl in
                    let t = CornerCurve.ease(tl.date.timeIntervalSince(swapStart) / Self.swapDuration)
                    ZStack(alignment: .topLeading) {
                        MiniBotCanvasView(task: s.outgoing)
                            .frame(width: Self.bigBody / 0.6, height: Self.bigBody / 0.6)
                            .scaleEffect(1 + (small - 1) * t)
                            .position(CornerCurve.point(t, from: home, to: slot, bulge: 46))
                        MiniBotCanvasView(task: s.incoming)
                            .frame(width: Self.bigBody / 0.6, height: Self.bigBody / 0.6)
                            .scaleEffect(small + (1 - small) * t)
                            .position(CornerCurve.point(t, from: slot, to: home, bulge: 46))
                    }
                    .frame(width: islandW, height: islandH, alignment: .topLeading)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(width: islandW, height: islandH, alignment: .topLeading)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: tasks.map(\.id))
        .onDisappear { if swap != nil { finish() } }
    }

    private func start(_ task: AgentTask, at index: Int, current: [AgentTask]) {
        guard swap == nil, let focus = state.focusTask else { return }
        var ids = current.map(\.id)
        if index < ids.count { ids[index] = focus.id }
        swapStart = Date()
        swap = Swap(incoming: task, outgoing: focus, slot: index, order: ids)
        state.cornerSwapping = true
        SoundEngine.shared.play("blip")
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.swapDuration) { finish() }
    }

    /// Both have arrived: the one in the corner is now the focus, the other is on the circle.
    private func finish() {
        guard let s = swap else { return }
        var tr = Transaction()
        tr.disablesAnimations = true
        withTransaction(tr) {
            order = s.order
            state.setFocus(s.incoming.id)
            state.cornerSwapping = false
            swap = nil
        }
    }
}

/// The swap's path: a quadratic curve from `from` to `to`, bowed `bulge` points to the side.
/// Two of them with the same bulge, in opposite directions, cross halfway.
enum CornerCurve {
    static func point(_ t: CGFloat, from: CGPoint, to: CGPoint, bulge: CGFloat) -> CGPoint {
        let dx = to.x - from.x, dy = to.y - from.y
        let len = max(1, hypot(dx, dy))
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let ctrl = CGPoint(x: mid.x - dy / len * bulge, y: mid.y + dx / len * bulge)
        let u = 1 - t
        return CGPoint(x: u * u * from.x + 2 * u * t * ctrl.x + t * t * to.x,
                       y: u * u * from.y + 2 * u * t * ctrl.y + t * t * to.y)
    }

    /// Slow out of the start, softly into the end.
    static func ease(_ x: Double) -> CGFloat {
        let t = min(1, max(0, x))
        return CGFloat(t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2)
    }
}

/// One pill's Mochi on the circle: a round button in its colour, its name under it.
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
                        .frame(width: CornerArcView.smallBody / 0.6, height: CornerArcView.smallBody / 0.6)
                        .frame(width: CornerArcView.smallBody, height: CornerArcView.smallBody)
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
                    .foregroundColor(hover ? Color(hex: task.color).lighter(by: 0.3) : Color(hex: "#8E939C"))
                    .lineLimit(1)
                    .fixedSize()
                    .offset(y: 15)
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
