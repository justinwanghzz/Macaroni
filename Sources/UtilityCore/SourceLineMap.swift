import Foundation

/// Markdown line numbers use LF (with CRLF / CR normalized); NSTextView uses UTF-16 offsets.
public struct SourceLineMap {
    private let units:[UInt16]
    public let lineStarts:[Int]
    public init(_ source:String) {
        units=Array(source.utf16)
        var starts=[0],i=0
        while i<units.count {
            if units[i]==13 {if i+1<units.count,units[i+1]==10 {i+=1};starts.append(i+1)}
            else if units[i]==10 {starts.append(i+1)}
            i+=1
        }
        lineStarts=starts
    }
    public func line(atUTF16Offset offset:Int)->Int {
        let position=max(0,min(units.count,offset));var low=0,high=lineStarts.count
        while low+1<high {let mid=(low+high)/2;if lineStarts[mid]<=position {low=mid}else{high=mid}}
        return low
    }
    public func contentRange(forLine line:Int)->NSRange {
        let index=max(0,min(lineStarts.count-1,line)),start=lineStarts[index]
        var end=index+1<lineStarts.count ? lineStarts[index+1]:units.count
        while end>start,(units[end-1]==10 || units[end-1]==13) {end-=1}
        return NSRange(location:start,length:end-start)
    }
    public func utf16Offset(forLine line:Int,column:Int=0)->Int {
        let range=contentRange(forLine:line)
        var offset=range.location+max(0,min(range.length,column))
        // A caret must not land in the middle of an emoji / surrogate pair.
        if offset>range.location,offset<units.count,(0xDC00...0xDFFF).contains(units[offset]),(0xD800...0xDBFF).contains(units[offset-1]) {offset-=1}
        return offset
    }
}
