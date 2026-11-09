import Foundation

/// Decimal MB throughout, matching the encoder's byte limit.
public struct VideoSizeTarget:Sendable {
    public let sourceBytes:Int64
    public var percentage:Double
    public init(sourceBytes:Int64,percentage:Double=100) { self.sourceBytes=sourceBytes;self.percentage=percentage }
    public var megabytes:Double { Double(sourceBytes)/1_000_000*percentage/100 }
    public mutating func setMegabytes(_ value:Double) {
        guard sourceBytes>0,value.isFinite else { return }
        percentage=value*1_000_000/Double(sourceBytes)*100
    }
    public func targetMegabytes(for bytes:Int64)->Double { Double(bytes)/1_000_000*percentage/100 }
    public func validate() throws {
        guard sourceBytes>0,percentage.isFinite,percentage>0,percentage<=100,megabytes>=0.01,megabytes<=10000 else { throw UtilityError.message("Choose a target between 0.01 MB and the source size (up to 10,000 MB)") }
    }
}
