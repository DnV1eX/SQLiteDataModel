//
//  SQLiteDataModel.swift
//  SQLiteDataModel
//
//  Created by Alexey Demin on 2018-12-07.
//

import CoreData
import SQLite3


class SQLiteDataModel {
    
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
    
    
    init(coreDataModelName modelName: String? = nil, bundle: Bundle = Bundle.main, sqliteDB dbURL: URL) throws {
        
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
        
        try execute("PRAGMA journal_mode = WAL")
        
//        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
//        try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: dbURL, options: nil)
//        print(coordinator.persistentStore(for: dbURL)?.metadata)
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    
    lazy var modelName: String = { modelURL.deletingPathExtension().lastPathComponent }()

    
    private func loadModel(_ version: Int? = nil) throws -> (model: NSManagedObjectModel, version: Int) {
        
        let url = version.map { modelURL.appendingPathComponent(modelName + ($0 == 1 ? "" : " \($0)")).appendingPathExtension("mom") } ?? modelURL
        guard let model = NSManagedObjectModel(contentsOf: url) else {
            throw Error.unableToLoadCoreDataModel(at: url)
        }
        
        guard let modelVersionIdentifier = model.versionIdentifiers.first as? String, let modelVersion = Int(modelVersionIdentifier) else {
            throw Error.invalidModelVersion(nil, expected: version)
        }
        
        if let version = version, version != modelVersion {
            throw Error.invalidModelVersion(modelVersion, expected: version)
        }
        
        return (model, modelVersion)
    }
    
    
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
    

    private func createTable(for entity: NSEntityDescription, name: String? = nil) throws {
        
        let name = name ?? entity.name!
        
        guard !entity.properties.isEmpty else {
            throw Error.zeroColumnTable(name)
        }
        
        var columns = ""
        for property in entity.properties {
            print(property)
            switch property {
            case let attribute as NSAttributeDescription:
                if !columns.isEmpty {
                    columns += ", "
                }
                columns += attribute.name
                switch attribute.attributeType {
                case .integer16AttributeType,
                     .integer32AttributeType,
                     .integer64AttributeType,
                     .objectIDAttributeType:
                    columns += " INTEGER"
                case .stringAttributeType,
                     .URIAttributeType,
                     .UUIDAttributeType:
                    columns += " TEXT"
                case .binaryDataAttributeType:
                    columns += " BLOB"
                case .doubleAttributeType,
                     .floatAttributeType:
                    columns += " REAL"
                case .decimalAttributeType,
                     .dateAttributeType,
                     .booleanAttributeType:
                    columns += " NUMERIC"
                case .transformableAttributeType,
                     .undefinedAttributeType: break
                }
                if !attribute.isOptional {
                    columns += " NOT NULL"
                }
                if let defaultValue = attribute.defaultValue {
                    columns += " DEFAULT \(defaultValue)"
                }
//            case let relationship as NSRelationshipDescription:
            default: break
            }
        }
        let query = "CREATE TABLE \"\(name)\"(\(columns))"
        try execute(query)
    }
    
    
    private func dropTable(_ name: String) throws {
        
        try execute("DROP TABLE \"\(name)\"")
    }
    
    
    private func renameTable(_ name: String, to newName: String) throws {
        
        try execute("ALTER TABLE \"\(name)\" RENAME TO \"\(newName)\"")
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
    
    
    func create(version: Int? = nil) throws {
        
        let (model, version) = try loadModel(version)
        
        for entity in model.entities {
            print(entity)
            try createTable(for: entity)
        }
//        let timestamp = "STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')"
        let query = "CREATE TABLE schema_migrations(version INTEGER NOT NULL, timestamp NUMERIC NOT NULL DEFAULT CURRENT_TIMESTAMP)"
        try execute(query)
        try insertVersion(version)
    }
    
    
    func currentVersion() throws -> Int {
        
//        let query = "SELECT version, max(timestamp) FROM schema_migrations"
        let query = "SELECT version FROM schema_migrations ORDER BY rowid DESC LIMIT 1"
        guard let versionString = try request(query).first?["version"], let version = Int(versionString) else {
            throw Error.unknownSQLiteSchemaVersion
        }
        
        return version
    }
    
    
    func migrate(to version: Int? = nil) throws {
        
        let (model, version) = try loadModel(version)
        let currentVersion = try self.currentVersion()
        let (currentModel, _) = try loadModel(currentVersion)
        let mappingModel = try NSMappingModel.inferredMappingModel(forSourceModel: currentModel, destinationModel: model)
        print(mappingModel)
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
            }
        }
        try insertVersion(version)
    }
}
