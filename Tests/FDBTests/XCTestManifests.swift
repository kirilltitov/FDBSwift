import XCTest

#if !os(macOS)
    public func allTests() -> [XCTestCaseEntry] {
        return [
            testCase(FDBTests.allTests),
            testCase(TupleTests.allTests),
        ]
    }
#endif
