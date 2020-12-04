//
//  SQLiteDataModelTests.swift
//  SQLiteDataModelTests
//
//  Created by Alexey Demin on 2018-12-08.
//

import XCTest
@testable import SQLiteDataModel


final class SQLiteDataModelTests: XCTestCase {

    static let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("SQLiteDataModelTestDB").appendingPathExtension("sqlite")
    
    static let model = try! SQLiteDataModel(bundle: Bundle.module, sqliteDB: dbURL, profile: true)

    
    override class func setUp() {
        try? FileManager.default.removeItem(at: dbURL)
    }

    
    func testCreation() throws {
        
//        print(model.db)
        try SQLiteDataModelTests.model.create(by: SQLiteDataModelTests.model.loadModel(1))
        XCTAssertEqual(try SQLiteDataModelTests.model.currentVersion(), 1)
        
        let db = Self.model
        try db.execute("INSERT INTO Country(name, flag) VALUES ('USA', '🇺🇸'), ('USSR', '🚩'), ('Russia', '🇷🇺'), ('China', '🇨🇳'), ('India', '🇮🇳')")
        
        try db.execute("INSERT INTO Spacecraft(name, launchMass) VALUES ('UFO', 0)")
        XCTAssertThrowsError(try db.execute("INSERT INTO Spacecraft(name, launchMass) VALUES ('UFO', 0)"))
        XCTAssertThrowsError(try db.execute("INSERT INTO Spacecraft(name, launchMass, origin) VALUES ('Millennium Falcon', 100000, 'Galactic Empire')"))
        try db.execute("INSERT INTO Spacecraft(name, crewSize, launchMass, origin, firstFlight) VALUES ('Vostok', 1, 4725, 'USSR', '1961-04-12')")
        try db.execute("INSERT INTO Spacecraft(name, crewSize, launchMass, origin, firstFlight) VALUES ('Mercury', 1, 1830, 'USA', '1961-05-05')")

        let rows = try db.request("SELECT * FROM Spacecraft, Country AS c ON origin = c.name ORDER BY firstFlight")
        XCTAssertEqual(rows.count, 2)
        if let row = rows.first {
            XCTAssertEqual(row.count, 6)
            XCTAssertEqual(row["crewSize"], "1")
            XCTAssertEqual(row["name"], "Vostok")
            XCTAssertEqual(row["launchMass"], "4725")
            XCTAssertEqual(row["origin"], "USSR")
            XCTAssertEqual(row["flag"], "🚩")
            XCTAssertNotEqual(row["flag"], "🇺🇸")
        }
        try db.execute("INSERT INTO Cosmodrome(name) VALUES ('Baikonur')")
        
//        throw NSError(domain: "test error", code: 0, userInfo: nil)

//        row = try db.query("SELECT * FROM Spaceport")
//        XCTAssertEqual(row?.columnCount, 1)
//        XCTAssertEqual(row?["name"], "Baikonur")
//
//        XCTAssertNoThrow(try db.query("SELECT * FROM Manufacturer"))
//        XCTAssertThrowsError(try db.query("SELECT * FROM Country"))
//
//        try db.execute("INSERT INTO Manufacturer(name) VALUES ('OKB-1'), ('USSR'), ('Russia'), ('China'), ('India')")
    }
    
    
    func testMigration() {
        
        do {
            try SQLiteDataModelTests.model.migrate(to: SQLiteDataModelTests.model.loadModel(2))
            XCTAssertEqual(try SQLiteDataModelTests.model.currentVersion(), 2)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    
    static var allTests = [
        ("testCreation", testCreation),
        ("testMigration", testMigration),
    ]
}
