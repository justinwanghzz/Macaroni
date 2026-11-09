import Foundation
import CoreGraphics

/// Catalog order is formats, shelf, tools; geometry is chosen for full or sparse menus.
public enum RadialLayout {
    public struct Layout: Sendable { public var center:CGPoint;public var frames:[CGRect] }
    public static func make(anchor:CGPoint,screen:CGRect,upper:Int,lower:Int,compact:Bool=false,upperColumns:Int=3,preset:Bool=false)->Layout {
        let w:CGFloat=104,h:CGFloat=64,gap:CGFloat=8,clearance:CGFloat=48
        let safe=screen.insetBy(dx:12,dy:12)
        let tools=max(0,lower-1)
        var frames:[CGRect]=[]
        var center=anchor
        if compact {
            let count=upper+lower,width=CGFloat(max(1,count))*(w+gap)-gap
            let x=max(safe.minX,min(anchor.x-width/2,safe.maxX-width))
            let y=max(safe.minY,min(anchor.y-clearance-h,safe.maxY-h))
            for i in 0..<upper { frames.append(CGRect(x:x+CGFloat(i)*(w+gap),y:y,width:w,height:h)) }
            if lower>0 { frames.append(CGRect(x:x+CGFloat(count-1)*(w+gap),y:y,width:w,height:h)) }
            for i in 0..<tools { frames.append(CGRect(x:x+CGFloat(upper+i)*(w+gap),y:y,width:w,height:h)) }
        } else {
            let columns=max(1,upperColumns)
            let upperRows=(upper+columns-1)/columns
            let upperWidth=CGFloat(min(columns,max(1,upper)))*(w+gap)-gap
            let upperHeight=upper>0 ? CGFloat(upperRows)*(h+gap)-gap:0
            let toolWidth=3*w+2*gap
            let width=max(toolWidth,upperWidth)
            let topHeight=upper>0 ? upperHeight+clearance:h/2
            let bottomHeight=tools>0 ? CGFloat((tools+2)/3)*(h+gap)-gap+clearance:h/2
            let x=max(safe.minX,min(anchor.x-width/2,safe.maxX-width))
            let cy=max(safe.minY+bottomHeight,min(anchor.y,safe.maxY-topHeight))
            center=CGPoint(x:x+width/2,y:cy)
            let upperX=columns==3 ? x:x+(width-upperWidth)/2
            let toolX=x+(width-toolWidth)/2
            for i in 0..<upper { frames.append(CGRect(x:upperX+CGFloat(i%columns)*(w+gap),y:cy+clearance+CGFloat(upperRows-1-i/columns)*(h+gap),width:w,height:h)) }
            if lower>0 {
                frames.append(CGRect(x:toolX+2*(w+gap),y:cy-h/2,width:w,height:h))
            }
            for i in 0..<tools { frames.append(CGRect(x:toolX+CGFloat(i%3)*(w+gap),y:cy-clearance-h-CGFloat(i/3)*(h+gap),width:w,height:h)) }
        }
        if preset {frames.append(CGRect(x:center.x-164,y:center.y-32,width:w,height:h))}
        // Correct edge collisions by translating the complete grid, never individual cards.
        let source=CGRect(x:anchor.x-36,y:anchor.y-36,width:72,height:72)
        if frames.contains(where: { $0.intersects(source) }),let first=frames.first {
            let bounds=frames.dropFirst().reduce(first) { $0.union($1) }
            let offsets=[CGPoint(x:0,y:source.maxY+8-bounds.minY),CGPoint(x:0,y:source.minY-8-bounds.maxY),CGPoint(x:source.maxX+8-bounds.minX,y:0),CGPoint(x:source.minX-8-bounds.maxX,y:0)]
            if let offset=offsets.first(where: { safe.contains(bounds.offsetBy(dx:$0.x,dy:$0.y)) }) {
                return Layout(center:CGPoint(x:center.x+offset.x,y:center.y+offset.y),frames:frames.map { $0.offsetBy(dx:offset.x,dy:offset.y) })
            }
        }
        return Layout(center:center,frames:frames)
    }
}
