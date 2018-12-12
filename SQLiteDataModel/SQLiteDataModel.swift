//
//  SQLiteDataModel.swift
//  SQLiteDataModel
//
//  Created by Alexey Demin on 2018-12-07.
//

import CoreData
import SQLite3


class SQLiteDataModel {
    
    enum Error: Swift.Error {
        case noCoreDataModel(at: URL)
        case sqLiteError(code: Int32, message: UnsafePointer<Int8>?)
        
        var localizedDescription: String {
            switch self {
            case let .noCoreDataModel(at: url):
                return "Unable to load Core Data model at \(url)"
            case let .sqLiteError(code: result, message: errMsg):
                return "SQLite error code \(result)" + (errMsg.map { ": \($0)" } ?? sqlite3_errstr(result).map { " (\($0))" } ?? "")
            }
        }
    }
    
    
    let model: NSManagedObjectModel
    
    let db: OpaquePointer
    
    
    init(coreDataModel modelURL: URL, sqliteDB dbURL: URL) throws {
        
        guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
            throw Error.noCoreDataModel(at: modelURL)
        }
        
        self.model = model
        
        var db: OpaquePointer!
        let result = sqlite3_open(dbURL.path, &db)
        guard result == SQLITE_OK, db != nil else {
            if let db = db {
                sqlite3_close(db)
            }
            throw Error.sqLiteError(code: result, message: sqlite3_errmsg(db))
        }
        
        self.db = db
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    
    func create() throws {
        
        var query = ""
        for (name, entity) in model.entitiesByName {
            print(entity)
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
//                case let relationship as NSRelationshipDescription:
                default: break
                }
            }
            if !columns.isEmpty {
                if !query.isEmpty {
                    query += ";\n"
                }
                query += "CREATE TABLE \(name)(\(columns))"// WITHOUT ROWID"
            }
        }
        var errMsg: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, query, nil, nil, &errMsg)
        guard result == SQLITE_OK else {
            throw Error.sqLiteError(code: result, message: errMsg)
        }
    }
}
