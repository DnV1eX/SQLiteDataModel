//
//  SQLiteDataModelTests.swift
//  SQLiteDataModelTests
//
//  Created by Alexey Demin on 2018-12-08.
//

import XCTest
@testable import SQLiteDataModel
import SQift


class SQLiteDataModelTests: XCTestCase {

//    static let modelURL = Bundle(for: SQLiteDataModelTests.self).url(forResource: "TestModel", withExtension: "momd")!
    static let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("SQLiteDataModelTestDB").appendingPathExtension("sqlite")
    var db: Connection { return try! Connection(storageLocation: .onDisk(SQLiteDataModelTests.dbURL.path)) }

    
    override class func setUp() {
        try? FileManager.default.removeItem(at: dbURL)
    }

    
    func testDBCreation() throws {
        
        let model = try SQLiteDataModel(bundle: Bundle(for: SQLiteDataModelTests.self), sqliteDB: SQLiteDataModelTests.dbURL)
        try model.create(version: 1)
        XCTAssertEqual(try model.currentVersion(), 1)
        
        try db.execute("INSERT INTO Spacecraft(name, crewSize, launchMass) VALUES('Vostok', 1, 4725)")
        var row = try db.query("SELECT * FROM Spacecraft")
        XCTAssertEqual(row?.columnCount, 3)
        XCTAssertEqual(row?["crewSize"], 1)
        XCTAssertEqual(row?["name"], "Vostok")
        XCTAssertEqual(row?["launchMass"], 4725)
        
        try db.execute("INSERT INTO Cosmodrome(name) VALUES('Baikonur')")
        
        try model.migrate()
        XCTAssertEqual(try model.currentVersion(), 2)
        
        row = try db.query("SELECT * FROM Spaceport")
        XCTAssertEqual(row?.columnCount, 1)
        XCTAssertEqual(row?["name"], "Baikonur")
        
        XCTAssertNoThrow(try db.query("SELECT * FROM Manufacturer"))
        XCTAssertThrowsError(try db.query("SELECT * FROM Cathedral"))
    }
}
