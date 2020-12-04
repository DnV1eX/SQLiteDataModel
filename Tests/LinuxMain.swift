import XCTest

import SQLiteDataModelTests

var tests = [XCTestCaseEntry]()
tests += SQLiteDataModelTests.allTests()
XCTMain(tests)
