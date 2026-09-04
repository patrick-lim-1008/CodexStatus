import SwiftUI

struct CodexMarkView: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let orbit = size.width * 0.225
            let radius = size.width * 0.225

            let centerRect = CGRect(
                x: center.x - size.width * 0.29,
                y: center.y - size.height * 0.29,
                width: size.width * 0.58,
                height: size.height * 0.58
            )
            context.fill(Path(ellipseIn: centerRect), with: .color(color))

            for index in 0..<6 {
                let angle = Double(index) * .pi / 3
                let lobeCenter = CGPoint(
                    x: center.x + CGFloat(cos(angle)) * orbit,
                    y: center.y + CGFloat(sin(angle)) * orbit
                )
                let lobeRect = CGRect(
                    x: lobeCenter.x - radius,
                    y: lobeCenter.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.fill(Path(ellipseIn: lobeRect), with: .color(color))
            }

            var prompt = Path()
            prompt.move(to: CGPoint(x: size.width * 0.28, y: size.height * 0.31))
            prompt.addLine(to: CGPoint(x: size.width * 0.42, y: size.height * 0.5))
            prompt.addLine(to: CGPoint(x: size.width * 0.28, y: size.height * 0.69))
            context.stroke(prompt, with: .color(.white.opacity(0.94)), style: .init(lineWidth: 1.25, lineCap: .round, lineJoin: .round))

            var underscore = Path()
            underscore.move(to: CGPoint(x: size.width * 0.54, y: size.height * 0.69))
            underscore.addLine(to: CGPoint(x: size.width * 0.74, y: size.height * 0.69))
            context.stroke(underscore, with: .color(.white.opacity(0.94)), style: .init(lineWidth: 1.25, lineCap: .round))
        }
    }
}
