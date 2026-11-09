import XCTest
@testable import UtilityCore

final class SourceLineMapTests:XCTestCase {
    func testEmptyDocumentAndTrailingBlankLines() {
        let empty=SourceLineMap("");XCTAssertEqual(empty.lineStarts,[0]);XCTAssertEqual(empty.utf16Offset(forLine:10,column:20),0)
        let map=SourceLineMap("first\n\n");XCTAssertEqual(map.lineStarts,[0,6,7]);XCTAssertEqual(map.line(atUTF16Offset:7),2);XCTAssertEqual(map.contentRange(forLine:2),NSRange(location:7,length:0))
    }
    func testCRLFAndLoneCRMatchMarkdownNormalizedLines() {
        let map=SourceLineMap("ab\r\ncd\ref\n")
        XCTAssertEqual(map.lineStarts,[0,4,7,10]);XCTAssertEqual(map.line(atUTF16Offset:3),0);XCTAssertEqual(map.line(atUTF16Offset:4),1)
        XCTAssertEqual(map.contentRange(forLine:0),NSRange(location:0,length:2));XCTAssertEqual(map.contentRange(forLine:1),NSRange(location:4,length:2))
    }
    func testUnicodeUsesTextViewUTF16OffsetsWithoutSplittingEmoji() {
        let map=SourceLineMap("标题\nA😀B café\n尾")
        XCTAssertEqual(map.lineStarts,[0,3,13]);XCTAssertEqual(map.utf16Offset(forLine:1,column:2),4)
        XCTAssertEqual(map.utf16Offset(forLine:1,column:3),6);XCTAssertEqual(map.line(atUTF16Offset:13),2)
        XCTAssertEqual(map.utf16Offset(forLine:1,column:100),12)
    }
    func testLongDocumentLineRoundTripAndClamp() {
        let source=(0..<500).map{"Line \($0) — 文件 😀"}.joined(separator:"\n"),map=SourceLineMap(source)
        XCTAssertEqual(map.lineStarts.count,500)
        for line in 0..<500 {let offset=map.utf16Offset(forLine:line);XCTAssertEqual(map.line(atUTF16Offset:offset),line);XCTAssertTrue((source as NSString).substring(with:map.contentRange(forLine:line)).hasPrefix("Line \(line)"))}
        XCTAssertEqual(map.line(atUTF16Offset:-1),0);XCTAssertEqual(map.line(atUTF16Offset:Int.max),499)
        XCTAssertEqual(map.utf16Offset(forLine:-1,column:-1),0)
    }
}
