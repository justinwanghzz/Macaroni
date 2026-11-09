import AppKit

/// A crisp template counterpart to the full-color pasta app icon.
@MainActor enum MacaroniIcon {
    static func menuBarImage()->NSImage {
        let image=NSImage(size:NSSize(width:22,height:22),flipped:false) { _ in
            NSColor.black.setStroke()
            let curve=NSBezierPath();curve.lineWidth=6;curve.lineCapStyle = .round
            curve.move(to:NSPoint(x:6,y:6));curve.curve(to:NSPoint(x:16,y:16),controlPoint1:NSPoint(x:12,y:6),controlPoint2:NSPoint(x:16,y:10));curve.stroke()
            if let context=NSGraphicsContext.current?.cgContext {
                context.setBlendMode(.clear)
                context.fillEllipse(in:CGRect(x:4.6,y:4.6,width:2.8,height:2.8))
                context.fillEllipse(in:CGRect(x:14.6,y:14.6,width:2.8,height:2.8))
            }
            return true
        }
        image.isTemplate=true;image.accessibilityDescription="Macaroni";return image
    }
}
