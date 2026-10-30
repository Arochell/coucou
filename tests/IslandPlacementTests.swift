import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

@main
enum IslandPlacementTests {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 70, width: 1512, height: 879)   // menu bar 33, Dock 70
        let panel = CGSize(width: 720, height: 560)
        let open = CGSize(width: 640, height: 160)

        // Notch: top centre, as before.
        let n = IslandPlacement.notch.panelOrigin(screen: screen, visible: visible, panelSize: panel)
        precondition(n == CGPoint(x: 396, y: 422))
        precondition(IslandPlacement.notch.islandRect(panelSize: panel, size: open) == CGRect(x: 40, y: 400, width: 640, height: 160))

        // Corners: the island 10 pt from the visible edges, whatever its size.
        for p in IslandPlacement.allCases where p.isCorner {
            let o = p.panelOrigin(screen: screen, visible: visible, panelSize: panel)
            for size in [CGSize(width: 80, height: 24), CGSize(width: 240, height: 24), open] {
                let r = p.islandRect(panelSize: panel, size: size).offsetBy(dx: o.x, dy: o.y)
                if p.isLeft { precondition(r.minX == 10, "\(p) \(r)") }
                if p.isRight { precondition(r.maxX == 1502, "\(p) \(r)") }
                if p.isBottom { precondition(r.minY == 80, "\(p) \(r): above the Dock") }
                else { precondition(r.maxY == 939, "\(p) \(r): under the menu bar") }
            }
        }

        // Drops: a corner, the notch, or nothing.
        precondition(IslandPlacement.snap(CGPoint(x: 40, y: 950), screen: screen) == .topLeft)
        precondition(IslandPlacement.snap(CGPoint(x: 1490, y: 960), screen: screen) == .topRight)
        precondition(IslandPlacement.snap(CGPoint(x: 60, y: 30), screen: screen) == .bottomLeft)
        precondition(IslandPlacement.snap(CGPoint(x: 1450, y: 100), screen: screen) == .bottomRight)
        precondition(IslandPlacement.snap(CGPoint(x: 760, y: 960), screen: screen) == .notch)
        precondition(IslandPlacement.snap(CGPoint(x: 760, y: 500), screen: screen) == nil)
        precondition(IslandPlacement.snap(CGPoint(x: 400, y: 960), screen: screen) == nil, "top, but not near the notch nor a corner")
        precondition(IslandPlacement(rawValue: "bottomRight") == .bottomRight)

        // Open in a corner: Mochi in the corner, the others on a quarter circle facing inwards.
        let home = IslandPlacement.homeSize
        precondition(IslandPlacement.topRight.cornerBotCenter(in: home) == CGPoint(x: 590, y: 46))
        precondition(IslandPlacement.bottomLeft.cornerBotCenter(in: home) == CGPoint(x: 50, y: 206))
        for p in IslandPlacement.allCases where p.isCorner {
            let c = p.cornerBotCenter(in: home)
            let pts = p.arcPoints(count: 4, in: home)
            precondition(pts.count == 4)
            for q in pts {
                precondition(abs(hypot(q.x - c.x, q.y - c.y) - IslandPlacement.arcRadius) < 0.01)
                // Inside the island with room for the name under it, inside the corner column.
                precondition(q.x > 20 && q.x < home.width - 20 && q.y > 20 && q.y + 20 + 16 < home.height, "\(p) \(q) inside the island")
                precondition(abs(q.x - c.x) + 20 <= IslandPlacement.cornerColumn, "\(p) \(q) in the corner column")
                // Towards the inside: away from the corner's two edges.
                precondition(p.isRight ? q.x <= c.x + 0.01 : q.x >= c.x - 0.01, "\(p) \(q)")
                precondition(p.isBottom ? q.y <= c.y + 0.01 : q.y >= c.y - 0.01, "\(p) \(q)")
            }
        }
        // Four on the circle: room between two for a line of text and their crossing.
        let four = IslandPlacement.topRight.arcPoints(count: 4, in: home)
        for (a, b) in zip(four, four.dropFirst()) { precondition(hypot(a.x - b.x, a.y - b.y) > 70) }
        precondition(IslandPlacement.notch.arcPoints(count: 3, in: home).isEmpty)
        let t = IslandPlacement.bottomRight.dropTarget(screen: screen, visible: visible, panelSize: panel)
        precondition(t == CGRect(x: 1442, y: 80, width: 60, height: 60), "\(t)")
        print("IslandPlacement tests: all passed")
    }
}
