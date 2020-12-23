import XCTest
import FDBTests

@main public struct Main {
    public static func main() {
        var tests = [XCTestCaseEntry]()
        tests += FDBTests.__allTests()
        XCTMain(tests)
    }
}
