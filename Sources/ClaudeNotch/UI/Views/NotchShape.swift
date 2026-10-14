import SwiftUI

/// Flat top, inverse top fillets that melt into the bezel, animatable rounded bottom corners.
/// The rect includes the `topFillet` wings on both sides; the body spans [topFillet, width - topFillet].
struct NotchShape: Shape {
    var topFillet: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topFillet, bottomRadius) }
        set {
            topFillet = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let f = max(0, min(topFillet, w / 2))
        let b = max(0, min(bottomRadius, (w - 2 * f) / 2, h))
        let k: CGFloat = 0.5523

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + f, y: rect.minY + f),
                          control: CGPoint(x: rect.minX + f, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + f, y: rect.maxY - b))
        path.addCurve(to: CGPoint(x: rect.minX + f + b, y: rect.maxY),
                      control1: CGPoint(x: rect.minX + f, y: rect.maxY - b + b * k),
                      control2: CGPoint(x: rect.minX + f + b - b * k, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - f - b, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.maxX - f, y: rect.maxY - b),
                      control1: CGPoint(x: rect.maxX - f - b + b * k, y: rect.maxY),
                      control2: CGPoint(x: rect.maxX - f, y: rect.maxY - b + b * k))
        path.addLine(to: CGPoint(x: rect.maxX - f, y: rect.minY + f))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - f, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
