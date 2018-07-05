import XCTest

import FDBTests

var tests = [XCTestCaseEntry]()
tests += FDBTests.allTests()
XCTMain(tests)