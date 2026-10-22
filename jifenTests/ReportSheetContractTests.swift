import XCTest
@testable import jifen

final class ReportSheetContractTests: XCTestCase {
    func testReportLengthContractsKeepEmojiIntact() {
        let value = "A👨‍👩‍👧‍👦B"
        XCTAssertEqual(ReportDetailLength.characters.count(value), 3)
        XCTAssertEqual(ReportDetailLength.characters.limited(value, maximum: 2), "A👨‍👩‍👧‍👦")
        XCTAssertEqual(ReportDetailLength.utf16.limited(value, maximum: 2), "A")
        XCTAssertEqual(ReportDetailLength.utf16.limited(value, maximum: value.utf16.count - 1), "A👨‍👩‍👧‍👦")
        XCTAssertEqual(ReportDetailLength.utf16.count("😀"), 2)
    }
}
