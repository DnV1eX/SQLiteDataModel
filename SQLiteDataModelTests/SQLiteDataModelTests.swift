//
//  SQLiteDataModelTests.swift
//  SQLiteDataModelTests
//
//  Created by Alexey Demin on 2018-12-08.
//

import XCTest
@testable import SQLiteDataModel


class SQLiteDataModelTests: XCTestCase {

    static let modelURL = Bundle(for: SQLiteDataModelTests.self).url(forResource: "TestModel", withExtension: "momd")!
    static let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("SQLiteDataModelTestDB").appendingPathExtension("sqlite")
    
    
    override class func setUp() {
        try? FileManager.default.removeItem(at: dbURL)
    }

    
    func testDBCreation() throws {
        let model = try SQLiteDataModel(coreDataModel: SQLiteDataModelTests.modelURL, sqliteDB: SQLiteDataModelTests.dbURL)
        try model.create()
    }
}
