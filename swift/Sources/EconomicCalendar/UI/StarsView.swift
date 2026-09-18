import SwiftUI

/// Importance stars — SwiftUI port of widget._make_stars_pixmap/_make_star_path.
struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let r = min(rect.width, rect.height) / 2 - 0.5
        for i in 0..<10 {
            let angle = -Double.pi / 2 + Double(i) * .pi / 5
            let radius = i % 2 == 0 ? r : r * 0.4
            let x = cx + radius * cos(angle)
            let y = cy + radius * sin(angle)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}

struct StarsView: View {
    let level: Importance
    var size: CGFloat = 11
    var gap: CGFloat = 2

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<level.rawValue, id: \.self) { _ in
                StarShape()
                    .fill(Theme.importanceColor(level))
                    .frame(width: size, height: size)
            }
        }
    }
}
