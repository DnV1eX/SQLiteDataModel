//
//  SQLiteDataModel.swift
//  SQLiteDataModel
//
//  Created by Alexey Demin on 2018-12-07.
//  Copyright © 2018 Alexey Demin. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import CoreData
import SQLite3


public class SQLiteDataModel {
    
    enum Error: LocalizedError {
        case noDataModelResource(with: String?, in: Bundle)
        case unableToLoadCoreDataModel(at: URL)
        case invalidModelVersion(Int?, expected: Int?)
        case sqLiteError(code: Int32, message: UnsafePointer<Int8>?)
        case sqLiteRequestTimeout
        case unknownSQLiteSchemaVersion
        case unsupportedMigrationType
        case zeroColumnTable(String)
        
        var errorDescription: String? {
            switch self {
            case let .noDataModelResource(with: name, in: bundle):
                return "Resource \(name ?? "*").momd not found in \(bundle)"
            case let .unableToLoadCoreDataModel(at: url):
                return "Unable to load Core Data model at \(url)"
            case let .invalidModelVersion(v1, expected: v2):
                return (v1.map { "Model version \($0)" } ?? "Unknown model version") + " loaded" + (v2.map { " while version \($0) expected" } ?? "")
            case let .sqLiteError(code: result, message: errMsg):
                return "SQLite error code \(result)" + (errMsg.map { ": \(String(cString: $0))" } ?? sqlite3_errstr(result).map { " (\(String(cString: $0)))" } ?? "")
            case .sqLiteRequestTimeout:
                return "SQLite request timeout"
            case .unknownSQLiteSchemaVersion:
                return "Unknown SQLite schema version"
            case .unsupportedMigrationType:
                return "Unsupported migration type"
            case .zeroColumnTable(let name):
                return "Model entity \"\(name)\" must contain attributes"
            }
        }
    }
    
    
    let modelURL: URL
    
    let db: OpaquePointer
    
//    let dbQueue = DispatchQueue(label: "SQLiteDataModel DB Queue")
    
    lazy var modelName: String = { modelURL.deletingPathExtension().lastPathComponent }()

    
    public init(coreDataModelName modelName: String? = nil, bundle: Bundle = Bundle.main, sqliteDB dbURL: URL, profile: Bool = false) throws {
        
        guard let modelURL = bundle.url(forResource: modelName, withExtension: "momd") else {
            throw Error.noDataModelResource(with: modelName, in: bundle)
        }
        
        self.modelURL = modelURL
        
        var db: OpaquePointer!
        let result = sqlite3_open(dbURL.path, &db)
        guard result == SQLITE_OK, db != nil else {
            if let db = db {
                sqlite3_close(db)
            }
            throw Error.sqLiteError(code: result, message: sqlite3_errmsg(db))
        }
        
        self.db = db
        if profile { trace(2) }

        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")

//        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
//        try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: dbURL, options: nil)
//        print(coordinator.persistentStore(for: dbURL)?.metadata)
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    
    public func currentVersion() throws -> Int {
        
//        let query = "SELECT version, max(timestamp) FROM schema_migrations"
        let query = "SELECT version FROM schema_migrations ORDER BY rowid DESC LIMIT 1"
        guard let versionString = try request(query).first?["version"], let version = Int(versionString) else {
            throw Error.unknownSQLiteSchemaVersion
        }
        
        return version
    }
    
    
    public func setup(version: Int? = nil) throws {
        
        let model = try loadModel(version)
        guard let currentVersion = try? currentVersion() else {
            try create(by: model)
            return
        }
        if model.version != currentVersion {
            try migrate(to: model)
        }
    }
    
    
    func create(by model: NSManagedObjectModel) throws {
        
        for entity in model.entities {
//            print(entity)
            try createTable(for: entity)
        }
//        let timestamp = "STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')"
        let query = "CREATE TABLE schema_migrations(version INTEGER NOT NULL, timestamp NUMERIC NOT NULL DEFAULT CURRENT_TIMESTAMP)"
        try execute(query)
        try insertVersion(model.version)
    }
    
    
    func migrate(to model: NSManagedObjectModel) throws {
        
        let currentVersion = try self.currentVersion()
        let currentModel = try loadModel(currentVersion)
        let mappingModel = try NSMappingModel.inferredMappingModel(forSourceModel: currentModel, destinationModel: model)
//        print(mappingModel)
        for entityMapping in mappingModel.entityMappings {
            let sourceEntityName: String! = entityMapping.sourceEntityName
            let destinationEntityName: String! = entityMapping.destinationEntityName
            
            switch entityMapping.mappingType {
            case .addEntityMappingType:
                try createTable(for: model.entitiesByName[destinationEntityName]!)
            case .removeEntityMappingType:
                try dropTable(sourceEntityName)
            case .copyEntityMappingType:
            break // leave the table as-is
            case .transformEntityMappingType:
                if sourceEntityName != destinationEntityName {
                    try renameTable(sourceEntityName, to: destinationEntityName)
                }
                
//                guard let userInfo = entityMapping.userInfo as? [String: Any] else { continue }
//
//                let addedProperties = userInfo["addedProperties"] as? [String]
//                let removedProperties = userInfo["removedProperties"] as? [String]
//                let mappedProperties = userInfo["mappedProperties"] as? [String]
//                for propertyMapping in entityMapping.attributeMappings ?? [] {
//                    print(propertyMapping)
//                }
            case .customEntityMappingType, .undefinedEntityMappingType:
                throw Error.unsupportedMigrationType
            @unknown default: break
            }
        }
        try insertVersion(model.version)
    }

    
    func loadModel(_ version: Int? = nil) throws -> NSManagedObjectModel {
        
        let url = version.map { modelURL.appendingPathComponent(modelName + ($0 == 1 ? "" : " \($0)")).appendingPathExtension("mom") } ?? modelURL
        guard let model = NSManagedObjectModel(contentsOf: url) else {
            throw Error.unableToLoadCoreDataModel(at: url)
        }
        
        guard let modelVersion = model.version, version == modelVersion || version == nil else {
            throw Error.invalidModelVersion(model.version, expected: version)
        }
        
        return model
    }
    
    
    // MARK: - SQLite3 Library Wrappers

    private func execute(_ query: String) throws {
        
        var errMsg: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, query, nil, nil, &errMsg)
//        while result == SQLITE_LOCKED {
//            usleep(10_000)
//            result = sqlite3_exec(db, query, nil, nil, &errMsg)
//        }
        guard result == SQLITE_OK else {
            throw Error.sqLiteError(code: result, message: errMsg)
        }
    }
    
    
    private func request(_ query: String) throws -> [[String: String]] {
        
        class Callback {
            let group = DispatchGroup()
            var result = [[String: String]]()
        }
        
        var errMsg: UnsafeMutablePointer<Int8>?
        let callback = Callback()
        callback.group.enter()
        let result = sqlite3_exec(db, query, { callback, count, values, columns in
            let callback = Unmanaged<Callback>.fromOpaque(callback!).takeUnretainedValue()
            var row = [String: String]()
            for i in 0..<Int(count) {
                guard let value = values?[i], let column = columns?[i] else { continue }
                row[String(cString: column)] = String(cString: value)
            }
            if count > 0 {
                callback.result.append(row)
            }
            callback.group.leave()
            return SQLITE_OK
        }, Unmanaged.passUnretained(callback).toOpaque(), &errMsg)
        guard result == SQLITE_OK else {
            throw Error.sqLiteError(code: result, message: errMsg)
        }
        
        switch callback.group.wait(timeout: .now() + 5) {
        case .success:
            return callback.result
        case .timedOut:
            throw Error.sqLiteRequestTimeout
        }
    }
    
    
    private func trace(_ mask: UInt32 = 0xF) {
        
        sqlite3_trace_v2(db, mask, { event, _, p1, p2 in
            switch Int32(event) {
            case SQLITE_TRACE_STMT:
                guard let statement = sqlite3_expanded_sql(OpaquePointer(p1)), let sql = p2?.assumingMemoryBound(to: CChar.self) else { break }
                
                print("SQLite statement: \(String(cString: statement)) (\(String(cString: sql)))")
                
            case SQLITE_TRACE_PROFILE:
                guard let statement = sqlite3_expanded_sql(OpaquePointer(p1)), let duration = p2?.load(as: Int64.self) else { break }
                
                print("SQLite profile: \(String(cString: statement)) (\(Double(duration) * 1e-9) seconds)")
                
            case SQLITE_TRACE_ROW:
                guard let statement = sqlite3_expanded_sql(OpaquePointer(p1)) else { break }
                
                print("SQLite row: \(String(cString: statement))")
                
            case SQLITE_TRACE_CLOSE:
                guard let connection = p1 else { break }
                
                print("SQLite connection \"\(connection)\" closed")
                
            default: break
            }
            return 0
        }, nil)
    }
    
    
    // MARK: - SQL Command Wrappers

    private func createTable(for entity: NSEntityDescription, name: String? = nil) throws {
        
        let childTable = name ?? entity.name!
        
        guard !entity.properties.isEmpty else {
            throw Error.zeroColumnTable(childTable)
        }
        
        var queries = [String]()
        var columns = [String]()
        var constraints = [String]()
        
        for property in entity.properties {
//            print(property)
            switch property {
            case let attribute as NSAttributeDescription:
                var column = #""\#(attribute.name)""#
                switch attribute.attributeType {
                case .integer16AttributeType,
                     .integer32AttributeType,
                     .integer64AttributeType,
                     .objectIDAttributeType:
                    column += " INTEGER"
                case .stringAttributeType,
                     .URIAttributeType,
                     .UUIDAttributeType:
                    column += " TEXT"
                case .binaryDataAttributeType:
                    column += " BLOB"
                case .doubleAttributeType,
                     .floatAttributeType:
                    column += " REAL"
                case .decimalAttributeType,
                     .dateAttributeType,
                     .booleanAttributeType:
                    column += " NUMERIC"
                case .transformableAttributeType,
                     .undefinedAttributeType: break
                @unknown default: break
                }
                if !attribute.isOptional {
                    column += " NOT NULL"
                }
                if let defaultValue = attribute.defaultValue {
                    column += " DEFAULT \(defaultValue)"
                }
                columns.append(column)
                
            case let relationship as NSRelationshipDescription:
                let parentTable = relationship.destinationEntity!.name!
                let parentKey = (relationship.userInfo?["parent"] as? String).map { "(\($0))" } ?? ""
                let childKey = (relationship.userInfo?["child"] as? String).map { "(\($0))" } ?? ""
                
                let onDeleteAction: String
                switch relationship.deleteRule {
                case .denyDeleteRule: onDeleteAction = " ON DELETE RESTRICT"
                case .nullifyDeleteRule: onDeleteAction = " ON DELETE SET NULL"
                case .cascadeDeleteRule: onDeleteAction = " ON DELETE CASCADE"
                default: onDeleteAction = ""
                }
                if relationship.isToMany {
                    let column1 = #""\#(childTable)" REFERENCES "\#(childTable)""# + childKey + onDeleteAction
                    let column2 = #""\#(parentTable)" REFERENCES "\#(parentTable)""# + parentKey + onDeleteAction
                    let key = #"PRIMARY KEY("\#(childTable)", "\#(parentTable)")"#
                    let query = #"CREATE TABLE "\#(relationship.name)"(\#(column1), \#(column2), \#(key)) WITHOUT ROWID"#
                    queries.append(query)
                }
                else if !childKey.isEmpty {
                    var constraint = "FOREIGN KEY" + childKey
                    constraint += #" REFERENCES "\#(parentTable)""# + parentKey + onDeleteAction
                    constraints.append(constraint)
                }
                else {
                    var column = #""\#(relationship.name)""#
                    if !relationship.isOptional {
                        column += " NOT NULL"
                    }
                    column += #" REFERENCES "\#(parentTable)""# + parentKey + onDeleteAction
                    columns.append(column)
                }
                
            default: break
            }
        }
        
        constraints += (entity.uniquenessConstraints as! [[String]]).enumerated().map { "\($0.0 == 0 ? "PRIMARY KEY" : "UNIQUE")(\($0.1.map { "\"\($0)\"" }.joined(separator: ",")))" }
        
        var query = #"CREATE TABLE "\#(childTable)"(\#((columns + constraints).joined(separator: ", ")))"#
        if !entity.uniquenessConstraints.isEmpty { query += " WITHOUT ROWID" }
        queries.insert(query, at: 0)
        
        try execute(queries.joined(separator: ";\n"))
    }
    
    
    private func dropTable(_ name: String) throws {
        
        try execute(#"DROP TABLE "\#(name)""#)
    }
    
    
    private func renameTable(_ name: String, to newName: String) throws {
        
        try execute(#"ALTER TABLE "\#(name)" RENAME TO "\#(newName)""#)
    }
    
    /// Generalized ALTER TABLE procedure will work even if the schema change causes the information stored in the table to change, e.g. dropping a column, changing the order of columns, adding or removing a UNIQUE constraint or PRIMARY KEY, adding CHECK or FOREIGN KEY or NOT NULL constraints, or changing the datatype for a column. https://www.sqlite.org/lang_altertable.html#otheralter
    private func alterTable(with mapping: NSEntityMapping) throws {
        
    }
    
    /// Simpler and faster procedure can optionally be used for some changes that do no affect the on-disk content in any way, e.g. removing CHECK or FOREIGN KEY or NOT NULL constraints, or adding, removing, or changing default values on a column. https://www.sqlite.org/lang_altertable.html#otheralter
    private func updateSchema(with mapping: NSEntityMapping) throws {
        
    }
    
    
    private func insertVersion(_ version: Int) throws {
        
        try execute("INSERT INTO schema_migrations(version) VALUES(\(version))")
    }
    
}



extension NSManagedObjectModel {
    
    var version: Int! {
        return (versionIdentifiers.first as? String).flatMap(Int.init)
    }
}
