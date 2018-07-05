import XCTest
@testable import FDB

final class FDBTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(FDB().text, "Hello, World!")
    }


    static var allTests = [
        ("testExample", testExample),
    ]
}
