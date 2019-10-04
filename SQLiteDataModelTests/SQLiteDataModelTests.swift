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
    
    var db: Connection {
        let db = try! Connection(storageLocation: .onDisk(SQLiteDataModelTests.dbURL.path))
        try! db.execute("PRAGMA foreign_keys = true")
        return db
    }

    
    override class func setUp() {
        try? FileManager.default.removeItem(at: dbURL)
    }

    
    func testDBCreation() throws {
        
        let model = try SQLiteDataModel(bundle: Bundle(for: SQLiteDataModelTests.self), sqliteDB: SQLiteDataModelTests.dbURL, profile: true)
//        print(model.db)
        try model.create(by: model.loadModel(1))
        XCTAssertEqual(try model.currentVersion(), 1)
        
        try db.execute("INSERT INTO Country(name, flag) VALUES ('USA', '🇺🇸'), ('USSR', '🚩'), ('Russia', '🇷🇺'), ('China', '🇨🇳'), ('India', '🇮🇳')")
        
        try db.execute("INSERT INTO Spacecraft(name, launchMass) VALUES ('UFO', 0)")
        XCTAssertThrowsError(try db.execute("INSERT INTO Spacecraft(name, launchMass) VALUES ('UFO', 0)"))
        XCTAssertThrowsError(try db.execute("INSERT INTO Spacecraft(name, launchMass, origin) VALUES ('Millennium Falcon', 100000, 'Galactic Empire')"))
        try db.execute("INSERT INTO Spacecraft(name, crewSize, launchMass, origin, firstFlight) VALUES ('Vostok', 1, 4725, 'USSR', '1961-04-12')")
        try db.execute("INSERT INTO Spacecraft(name, crewSize, launchMass, origin, firstFlight) VALUES ('Mercury', 1, 1830, 'USA', '1961-05-05')")

        if let row = try db.query("SELECT * FROM Spacecraft, Country AS c ON origin = c.name ORDER BY firstFlight") {
            XCTAssertEqual(row.columnCount, 7)
            XCTAssertEqual(row["crewSize"], 1)
            XCTAssertEqual(row["name"], "Vostok")
            XCTAssertEqual(row["launchMass"], 4725)
            XCTAssertEqual(row["origin"], "USSR")
            XCTAssertEqual(row["flag"], "🚩")
            XCTAssertNotEqual(row["flag"], "🇺🇸")
        } else {
            XCTFail("Spacecraft not found")
        }
        try db.execute("INSERT INTO Cosmodrome(name) VALUES ('Baikonur')")
        
//        try model.migrate(to: model.loadModel(2))
//        XCTAssertEqual(try model.currentVersion(), 2)
//
//        row = try db.query("SELECT * FROM Spaceport")
//        XCTAssertEqual(row?.columnCount, 1)
//        XCTAssertEqual(row?["name"], "Baikonur")
//
//        XCTAssertNoThrow(try db.query("SELECT * FROM Manufacturer"))
//        XCTAssertThrowsError(try db.query("SELECT * FROM Country"))
//
//        try db.execute("INSERT INTO Manufacturer(name) VALUES ('OKB-1'), ('USSR'), ('Russia'), ('China'), ('India')")
    }
}
