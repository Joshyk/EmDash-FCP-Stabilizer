#!/usr/bin/env swift

import Foundation
import SQLite3

enum TestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw TestFailure.failed(message)
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    guard actual == expected else {
        throw TestFailure.failed("\(message). expected=\(expected) actual=\(actual)")
    }
}

func expectContains(_ string: String, _ expectedSubstring: String, _ message: String) throws {
    guard string.contains(expectedSubstring) else {
        throw TestFailure.failed("\(message). expected substring=\(expectedSubstring) actual=\(string)")
    }
}

func expectThrowsContaining(_ expectedSubstring: String, _ body: () throws -> Void) throws {
    do {
        try body()
    } catch {
        try expectContains(String(describing: error), expectedSubstring, "Unexpected thrown error")
        return
    }
    throw TestFailure.failed("Expected error containing \(expectedSubstring)")
}

struct ActiveLibrarySidebarResolver {
    struct SidebarSelection {
        let rawSelection: String
        let identifiers: [String]

        var eventIdentifier: String? {
            identifiers.last
        }
    }

    struct EventSelection {
        let bundleRoot: URL
        let eventRoot: URL
        let sourceDescription: String
    }

    enum ResolverError: Error, CustomStringConvertible {
        case rejected(String)

        var description: String {
            switch self {
            case .rejected(let message):
                return message
            }
        }
    }

    func sidebarSelection(fromPreferencePlist preferenceURL: URL) throws -> SidebarSelection {
        let data = try Data(contentsOf: preferenceURL)
        var plistFormat = PropertyListSerialization.PropertyListFormat.binary
        guard let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &plistFormat
        ) as? [String: Any] else {
            throw ResolverError.rejected("preferences plist is not a dictionary at \(preferenceURL.path)")
        }
        guard let librarySidebar = plist["FFSidebarModuleLibrary"] as? [String: Any],
              let rawSelections = librarySidebar["media sidebar selection"] as? [String],
              let rawSelection = rawSelections.first(where: { !$0.isEmpty })
        else {
            throw ResolverError.rejected("FFSidebarModuleLibrary media sidebar selection missing at \(preferenceURL.path)")
        }
        let identifiers = uuidStrings(in: rawSelection)
        guard identifiers.count >= 2 else {
            throw ResolverError.rejected("FFSidebarModuleLibrary media sidebar selection has fewer than two UUIDs at \(preferenceURL.path): \(rawSelection)")
        }
        return SidebarSelection(rawSelection: rawSelection, identifiers: identifiers)
    }

    func resolveActiveLibraryEvent(
        candidates: [URL],
        rangeMatchedSelections: [EventSelection] = [],
        sidebarSelection: SidebarSelection
    ) throws -> EventSelection {
        if rangeMatchedSelections.count == 1, let selection = rangeMatchedSelections.first {
            return selection
        }
        if rangeMatchedSelections.count > 1 {
            throw ResolverError.rejected(
                "Multiple active library Events matched the Host Analysis range: \(rangeMatchedSelections.map { $0.eventRoot.path }.joined(separator: " | "))"
            )
        }
        return try activeFinalCutLibrarySidebarEventSelection(from: candidates, sidebarSelection: sidebarSelection)
    }

    private func activeFinalCutLibrarySidebarEventSelection(
        from candidates: [URL],
        sidebarSelection: SidebarSelection
    ) throws -> EventSelection {
        guard let eventIdentifier = sidebarSelection.eventIdentifier else {
            throw ResolverError.rejected("Final Cut Pro library sidebar selection has no Event identifier: \(sidebarSelection.rawSelection)")
        }

        var matches: [EventSelection] = []
        var inspectedBundles: [String] = []
        for candidate in candidates {
            let bundleRoot = candidate.standardizedFileURL
            let libraryMarkerURL = bundleRoot.appendingPathComponent("CurrentVersion.flexolibrary", isDirectory: false)
            guard FileManager.default.fileExists(atPath: libraryMarkerURL.path) else {
                inspectedBundles.append("\(bundleRoot.path)(missing CurrentVersion.flexolibrary)")
                continue
            }
            let markerMatch = libraryMarkerContainsIdentifiers(sidebarSelection.identifiers, markerURL: libraryMarkerURL)
            guard markerMatch.containsAllIdentifiers else {
                inspectedBundles.append("\(bundleRoot.path)(sidebarIDs:no: \(markerMatch.rejectReason))")
                continue
            }

            let eventLookup = eventRootForEventIdentifier(eventIdentifier, in: bundleRoot)
            guard let eventRoot = eventLookup.eventRoot else {
                inspectedBundles.append("\(bundleRoot.path)(sidebarIDs:yes,event:no: \(eventLookup.rejectReason))")
                continue
            }
            inspectedBundles.append("\(bundleRoot.path)(sidebarIDs:yes,event:\(eventRoot.lastPathComponent))")
            matches.append(EventSelection(
                bundleRoot: bundleRoot,
                eventRoot: eventRoot,
                sourceDescription: "Final Cut Pro library sidebar selection"
            ))
        }

        if matches.count == 1, let match = matches.first {
            return match
        }
        if matches.isEmpty {
            throw ResolverError.rejected(
                "No active library matched Final Cut Pro library sidebar selection \(sidebarSelection.rawSelection). inspected=\(inspectedBundles.joined(separator: " | "))"
            )
        }
        throw ResolverError.rejected(
            "Multiple active libraries matched Final Cut Pro library sidebar selection \(sidebarSelection.rawSelection): \(matches.map { "\($0.bundleRoot.path) -> \($0.eventRoot.path)" }.joined(separator: " | "))"
        )
    }

    private func uuidStrings(in string: String) -> [String] {
        let pattern = #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return expression.matches(in: string, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: string) else {
                return nil
            }
            return String(string[matchRange]).uppercased()
        }
    }

    private func libraryMarkerContainsIdentifiers(
        _ identifiers: [String],
        markerURL: URL
    ) -> (containsAllIdentifiers: Bool, rejectReason: String) {
        do {
            let markerData = try Data(contentsOf: markerURL)
            for identifier in identifiers {
                guard markerData.range(of: Data(identifier.utf8)) != nil else {
                    return (false, "missing \(identifier)")
                }
            }
            return (true, "")
        } catch {
            return (false, "unreadable CurrentVersion.flexolibrary: \(error.localizedDescription)")
        }
    }

    private func eventRootForEventIdentifier(
        _ eventIdentifier: String,
        in bundleRoot: URL
    ) -> (eventRoot: URL?, rejectReason: String) {
        let libraryMarkerURL = bundleRoot.appendingPathComponent("CurrentVersion.flexolibrary", isDirectory: false)
        let metadataLookup = eventMetadataBlobForEventIdentifier(eventIdentifier, libraryMarkerURL: libraryMarkerURL)
        guard let metadataData = metadataLookup.metadataData else {
            return (nil, metadataLookup.rejectReason)
        }
        let relativePathLookup = eventRelativePath(from: metadataData, eventIdentifier: eventIdentifier)
        guard let relativePath = relativePathLookup.relativePath else {
            return (nil, relativePathLookup.rejectReason)
        }
        let eventRoot = bundleRoot.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL
        let bundleRoot = bundleRoot.standardizedFileURL
        guard eventRoot.deletingLastPathComponent().standardizedFileURL.path == bundleRoot.path else {
            return (nil, "selected Event relativePath is not top-level in the active library: \(relativePath)")
        }
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: eventRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return (nil, "selected Event root does not exist at \(eventRoot.path)")
        }
        let eventMarkerURL = eventRoot.appendingPathComponent("CurrentVersion.fcpevent", isDirectory: false)
        guard FileManager.default.fileExists(atPath: eventMarkerURL.path) else {
            return (nil, "selected Event marker is missing at \(eventMarkerURL.path)")
        }
        return (eventRoot, "")
    }

    private func eventMetadataBlobForEventIdentifier(
        _ eventIdentifier: String,
        libraryMarkerURL: URL
    ) -> (metadataData: Data?, rejectReason: String) {
        var database: OpaquePointer?
        let openResult = libraryMarkerURL.path.withCString { path in
            sqlite3_open_v2(
                path,
                &database,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
                nil
            )
        }
        guard openResult == SQLITE_OK, let database else {
            let message = sqliteErrorMessage(database)
            if let database {
                sqlite3_close(database)
            }
            return (nil, "could not open CurrentVersion.flexolibrary read-only at \(libraryMarkerURL.path): \(message)")
        }
        defer {
            sqlite3_close(database)
        }

        let sql = """
        SELECT md.ZDICTIONARYDATA
        FROM ZCOLLECTION c
        JOIN ZCOLLECTIONMD md ON c.ZMETADATA = md.Z_PK
        WHERE c.ZIDENTIFIER = ? AND c.ZTYPE = 'FFEventRecord'
        LIMIT 2
        """
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            return (nil, "could not prepare Event metadata lookup: \(sqliteErrorMessage(database))")
        }
        defer {
            sqlite3_finalize(statement)
        }

        let bindResult = eventIdentifier.withCString { eventIdentifierCString in
            sqlite3_bind_text(statement, 1, eventIdentifierCString, -1, sqliteTransientDestructor)
        }
        guard bindResult == SQLITE_OK else {
            return (nil, "could not bind Event identifier \(eventIdentifier): \(sqliteErrorMessage(database))")
        }

        var blobs: [Data] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                let byteCount = Int(sqlite3_column_bytes(statement, 0))
                guard byteCount > 0,
                      let bytes = sqlite3_column_blob(statement, 0)
                else {
                    return (nil, "Event metadata blob is empty for \(eventIdentifier)")
                }
                blobs.append(Data(bytes: bytes, count: byteCount))
            } else if stepResult == SQLITE_DONE {
                break
            } else {
                return (nil, "could not step Event metadata lookup: \(sqliteErrorMessage(database))")
            }
        }

        if blobs.count == 1, let blob = blobs.first {
            return (blob, "")
        }
        if blobs.isEmpty {
            return (nil, "Event identifier \(eventIdentifier) not found in \(libraryMarkerURL.path)")
        }
        return (nil, "Event identifier \(eventIdentifier) matched multiple Event metadata rows in \(libraryMarkerURL.path)")
    }

    private var sqliteTransientDestructor: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    private func sqliteErrorMessage(_ database: OpaquePointer?) -> String {
        guard let database,
              let message = sqlite3_errmsg(database)
        else {
            return "unknown SQLite error"
        }
        return String(cString: message)
    }

    private func eventRelativePath(
        from metadataData: Data,
        eventIdentifier: String
    ) -> (relativePath: String?, rejectReason: String) {
        do {
            let allowedClasses: [AnyClass] = [
                NSDictionary.self,
                NSMutableDictionary.self,
                NSString.self,
                NSNumber.self,
                NSNull.self
            ]
            guard let dictionary = try NSKeyedUnarchiver.unarchivedObject(
                ofClasses: allowedClasses,
                from: metadataData
            ) as? NSDictionary else {
                return (nil, "Event metadata archive is not a dictionary for \(eventIdentifier)")
            }
            guard let relativePath = dictionary["relativePath"] as? String,
                  !relativePath.isEmpty
            else {
                return (nil, "Event metadata archive has no relativePath for \(eventIdentifier)")
            }
            return (relativePath, "")
        } catch {
            return (nil, "could not unarchive Event metadata for \(eventIdentifier): \(error.localizedDescription)")
        }
    }
}

struct FakeEvent {
    let identifier: String
    let relativePath: String
    let createFolder: Bool
    let createMarker: Bool

    init(
        identifier: String,
        relativePath: String,
        createFolder: Bool = true,
        createMarker: Bool = true
    ) {
        self.identifier = identifier
        self.relativePath = relativePath
        self.createFolder = createFolder
        self.createMarker = createMarker
    }
}

final class SQLiteFixtureDatabase {
    private let database: OpaquePointer
    private var metadataPrimaryKey = 1
    private var collectionPrimaryKey = 1

    static func create(at url: URL, body: (SQLiteFixtureDatabase) throws -> Void) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let openedDatabase = database
        else {
            let message = database.flatMap { sqlite3_errmsg($0) }.map(String.init(cString:)) ?? "unknown SQLite error"
            if let database {
                sqlite3_close(database)
            }
            throw TestFailure.failed("could not create fixture database at \(url.path): \(message)")
        }
        let fixtureDatabase = SQLiteFixtureDatabase(database: openedDatabase)
        defer {
            sqlite3_close(openedDatabase)
        }
        try fixtureDatabase.exec("""
        CREATE TABLE ZCOLLECTION (
            Z_PK INTEGER PRIMARY KEY,
            ZIDENTIFIER TEXT NOT NULL,
            ZTYPE TEXT NOT NULL,
            ZMETADATA INTEGER NOT NULL
        );
        CREATE TABLE ZCOLLECTIONMD (
            Z_PK INTEGER PRIMARY KEY,
            ZDICTIONARYDATA BLOB NOT NULL
        );
        """)
        try body(fixtureDatabase)
    }

    private init(database: OpaquePointer) {
        self.database = database
    }

    func exec(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown SQLite error"
            sqlite3_free(errorMessage)
            throw TestFailure.failed("fixture sqlite exec failed: \(message)")
        }
    }

    func insertCollection(identifier: String, type: String, metadata: Data) throws {
        let metadataKey = metadataPrimaryKey
        metadataPrimaryKey += 1

        var metadataStatement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT INTO ZCOLLECTIONMD (Z_PK, ZDICTIONARYDATA) VALUES (?, ?)", -1, &metadataStatement, nil) == SQLITE_OK,
              let preparedMetadataStatement = metadataStatement
        else {
            throw TestFailure.failed("could not prepare metadata insert: \(sqliteErrorMessage())")
        }
        defer {
            sqlite3_finalize(preparedMetadataStatement)
        }
        sqlite3_bind_int(preparedMetadataStatement, 1, Int32(metadataKey))
        try metadata.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                throw TestFailure.failed("metadata blob for \(identifier) is empty")
            }
            sqlite3_bind_blob(preparedMetadataStatement, 2, baseAddress, Int32(bytes.count), sqliteTransientDestructor)
        }
        guard sqlite3_step(preparedMetadataStatement) == SQLITE_DONE else {
            throw TestFailure.failed("could not insert metadata for \(identifier): \(sqliteErrorMessage())")
        }

        let collectionKey = collectionPrimaryKey
        collectionPrimaryKey += 1

        var collectionStatement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT INTO ZCOLLECTION (Z_PK, ZIDENTIFIER, ZTYPE, ZMETADATA) VALUES (?, ?, ?, ?)", -1, &collectionStatement, nil) == SQLITE_OK,
              let preparedCollectionStatement = collectionStatement
        else {
            throw TestFailure.failed("could not prepare collection insert: \(sqliteErrorMessage())")
        }
        defer {
            sqlite3_finalize(preparedCollectionStatement)
        }
        sqlite3_bind_int(preparedCollectionStatement, 1, Int32(collectionKey))
        _ = identifier.withCString { sqlite3_bind_text(preparedCollectionStatement, 2, $0, -1, sqliteTransientDestructor) }
        _ = type.withCString { sqlite3_bind_text(preparedCollectionStatement, 3, $0, -1, sqliteTransientDestructor) }
        sqlite3_bind_int(preparedCollectionStatement, 4, Int32(metadataKey))
        guard sqlite3_step(preparedCollectionStatement) == SQLITE_DONE else {
            throw TestFailure.failed("could not insert collection for \(identifier): \(sqliteErrorMessage())")
        }
    }

    private var sqliteTransientDestructor: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    private func sqliteErrorMessage() -> String {
        guard let message = sqlite3_errmsg(database) else {
            return "unknown SQLite error"
        }
        return String(cString: message)
    }
}

final class FixtureFactory {
    let root: URL
    private let fileManager = FileManager.default

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokyoWalkingStabilizerActiveLibraryResolverTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func makeLibrary(
        name: String,
        libraryIdentifier: String,
        events: [FakeEvent],
        extraIdentifiers: [String] = []
    ) throws -> URL {
        let bundleRoot = root.appendingPathComponent("\(name).fcpbundle", isDirectory: true)
        try fileManager.createDirectory(at: bundleRoot, withIntermediateDirectories: true)

        let libraryMarkerURL = bundleRoot.appendingPathComponent("CurrentVersion.flexolibrary", isDirectory: false)
        try SQLiteFixtureDatabase.create(at: libraryMarkerURL) { database in
            try database.insertCollection(
                identifier: libraryIdentifier,
                type: "FFLibraryRecord",
                metadata: metadataArchive(["relativePath": ""])
            )
            for event in events {
                try database.insertCollection(
                    identifier: event.identifier,
                    type: "FFEventRecord",
                    metadata: metadataArchive(["relativePath": event.relativePath])
                )
            }
            for identifier in extraIdentifiers {
                try database.insertCollection(
                    identifier: identifier,
                    type: "FFSyntheticReference",
                    metadata: metadataArchive(["identifier": identifier])
                )
            }
        }

        for event in events where event.createFolder {
            let eventRoot = bundleRoot.appendingPathComponent(event.relativePath, isDirectory: true)
            try fileManager.createDirectory(at: eventRoot, withIntermediateDirectories: true)
            if event.createMarker {
                let markerURL = eventRoot.appendingPathComponent("CurrentVersion.fcpevent", isDirectory: false)
                fileManager.createFile(atPath: markerURL.path, contents: Data("fixture event marker".utf8))
            }
        }

        return bundleRoot.standardizedFileURL
    }

    func writePreferencePlist(
        name: String,
        sidebarRawSelection: String,
        staleImportTargetLibraryIdentifier: String,
        staleImportTargetEventIdentifier: String
    ) throws -> URL {
        let preferenceURL = root.appendingPathComponent("\(name).plist", isDirectory: false)
        let plist: [String: Any] = [
            "FFSidebarModuleLibrary": [
                "media sidebar selection": [sidebarRawSelection]
            ],
            "FFImportTargetLibraryIdentifier": staleImportTargetLibraryIdentifier,
            "FFImportTargetEventIdentifier": staleImportTargetEventIdentifier,
            "FFImportTargetBookmarkData": Data("stale import target fixture".utf8)
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try data.write(to: preferenceURL)
        return preferenceURL
    }

    private func metadataArchive(_ dictionary: [String: String]) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: dictionary as NSDictionary, requiringSecureCoding: false)
    }
}

let selectedLibraryID = "11111111-1111-4111-8111-111111111111"
let selectedEventID = "22222222-2222-4222-8222-222222222222"
let otherLibraryID = "33333333-3333-4333-8333-333333333333"
let otherEventID = "44444444-4444-4444-8444-444444444444"
let staleImportTargetLibraryID = "55555555-5555-4555-8555-555555555555"
let staleImportTargetEventID = "66666666-6666-4666-8666-666666666666"
let duplicateLibraryID = "77777777-7777-4777-8777-777777777777"
let duplicateEventID = "88888888-8888-4888-8888-888888888888"

func sidebarRawSelection(libraryID: String, eventID: String) -> String {
    "FinalCutLibrarySidebar(selection: \(libraryID), event: \(eventID))"
}

let resolver = ActiveLibrarySidebarResolver()
let fixtures = try FixtureFactory()

func testSidebarSelectionMatchesOnlyCorrectFlexolibraryAndEventRelativePath() throws {
    let selectedLibrary = try fixtures.makeLibrary(
        name: "Selected",
        libraryIdentifier: selectedLibraryID,
        events: [
            FakeEvent(identifier: selectedEventID, relativePath: "Selected Event")
        ]
    )
    let wrongLibrary = try fixtures.makeLibrary(
        name: "WrongEventOnlyMatch",
        libraryIdentifier: otherLibraryID,
        events: [
            FakeEvent(identifier: selectedEventID, relativePath: "Wrong Event")
        ]
    )

    let sidebarSelection = ActiveLibrarySidebarResolver.SidebarSelection(
        rawSelection: sidebarRawSelection(libraryID: selectedLibraryID, eventID: selectedEventID),
        identifiers: [selectedLibraryID, selectedEventID]
    )
    let result = try resolver.resolveActiveLibraryEvent(
        candidates: [wrongLibrary, selectedLibrary],
        rangeMatchedSelections: [],
        sidebarSelection: sidebarSelection
    )

    try expectEqual(result.bundleRoot.path, selectedLibrary.path, "Sidebar selection should choose the library whose flexolibrary contains all selected UUIDs")
    try expectEqual(result.eventRoot.lastPathComponent, "Selected Event", "Selected Event relativePath should come from CurrentVersion.flexolibrary metadata")
    try expectEqual(result.sourceDescription, "Final Cut Pro library sidebar selection", "Selection source should be visible")
}

func testRangeMatchAbsentUsesSidebarSelectionForUniqueEvent() throws {
    let firstLibrary = try fixtures.makeLibrary(
        name: "RangeAbsentFirst",
        libraryIdentifier: selectedLibraryID,
        events: [
            FakeEvent(identifier: selectedEventID, relativePath: "First Event")
        ]
    )
    let secondLibrary = try fixtures.makeLibrary(
        name: "RangeAbsentSelected",
        libraryIdentifier: otherLibraryID,
        events: [
            FakeEvent(identifier: otherEventID, relativePath: "Sidebar Event")
        ]
    )

    let sidebarSelection = ActiveLibrarySidebarResolver.SidebarSelection(
        rawSelection: sidebarRawSelection(libraryID: otherLibraryID, eventID: otherEventID),
        identifiers: [otherLibraryID, otherEventID]
    )
    let result = try resolver.resolveActiveLibraryEvent(
        candidates: [firstLibrary, secondLibrary],
        rangeMatchedSelections: [],
        sidebarSelection: sidebarSelection
    )

    try expectEqual(result.bundleRoot.path, secondLibrary.path, "No range match should fall through to a unique sidebar Event")
    try expectEqual(result.eventRoot.lastPathComponent, "Sidebar Event", "Sidebar Event should be selected when range disambiguation has no match")
}

func testIgnoresStaleFFImportTargetValuesAndUsesFFSidebarModuleLibrarySelection() throws {
    let currentLibrary = try fixtures.makeLibrary(
        name: "CurrentSidebarLibrary",
        libraryIdentifier: selectedLibraryID,
        events: [
            FakeEvent(identifier: selectedEventID, relativePath: "Current Sidebar Event")
        ]
    )
    let staleLibrary = try fixtures.makeLibrary(
        name: "StaleFFImportTargetLibrary",
        libraryIdentifier: staleImportTargetLibraryID,
        events: [
            FakeEvent(identifier: staleImportTargetEventID, relativePath: "Stale Import Target Event")
        ]
    )

    let preferenceURL = try fixtures.writePreferencePlist(
        name: "FinalCutWithStaleImportTarget",
        sidebarRawSelection: sidebarRawSelection(libraryID: selectedLibraryID, eventID: selectedEventID),
        staleImportTargetLibraryIdentifier: staleImportTargetLibraryID,
        staleImportTargetEventIdentifier: staleImportTargetEventID
    )
    let preferenceData = try Data(contentsOf: preferenceURL)
    let preferencePlist = try PropertyListSerialization.propertyList(from: preferenceData, options: [], format: nil) as? [String: Any]
    try expectEqual(preferencePlist?["FFImportTargetLibraryIdentifier"] as? String, staleImportTargetLibraryID, "Fixture should contain stale FFImportTargetLibraryIdentifier")
    try expectEqual(preferencePlist?["FFImportTargetEventIdentifier"] as? String, staleImportTargetEventID, "Fixture should contain stale FFImportTargetEventIdentifier")

    let sidebarSelection = try resolver.sidebarSelection(fromPreferencePlist: preferenceURL)
    let result = try resolver.resolveActiveLibraryEvent(
        candidates: [staleLibrary, currentLibrary],
        rangeMatchedSelections: [],
        sidebarSelection: sidebarSelection
    )

    try expectEqual(result.bundleRoot.path, currentLibrary.path, "Resolver should ignore stale FFImportTarget* values and use FFSidebarModuleLibrary")
    try expect(result.bundleRoot.path != staleLibrary.path, "Stale FFImportTarget library must not be selected")
    try expectEqual(result.eventRoot.lastPathComponent, "Current Sidebar Event", "Current sidebar Event should win over stale import target Event")
}

func testMultipleSidebarMatchesFailVisibly() throws {
    let firstLibrary = try fixtures.makeLibrary(
        name: "DuplicateOne",
        libraryIdentifier: duplicateLibraryID,
        events: [
            FakeEvent(identifier: duplicateEventID, relativePath: "Duplicate Event One")
        ]
    )
    let secondLibrary = try fixtures.makeLibrary(
        name: "DuplicateTwo",
        libraryIdentifier: duplicateLibraryID,
        events: [
            FakeEvent(identifier: duplicateEventID, relativePath: "Duplicate Event Two")
        ]
    )
    let sidebarSelection = ActiveLibrarySidebarResolver.SidebarSelection(
        rawSelection: sidebarRawSelection(libraryID: duplicateLibraryID, eventID: duplicateEventID),
        identifiers: [duplicateLibraryID, duplicateEventID]
    )

    try expectThrowsContaining("Multiple active libraries matched Final Cut Pro library sidebar selection") {
        _ = try resolver.resolveActiveLibraryEvent(
            candidates: [firstLibrary, secondLibrary],
            rangeMatchedSelections: [],
            sidebarSelection: sidebarSelection
        )
    }
}

func testSidebarSelectionWithMissingEventFolderFailsVisibly() throws {
    let missingEventLibrary = try fixtures.makeLibrary(
        name: "MissingEventFolder",
        libraryIdentifier: selectedLibraryID,
        events: [
            FakeEvent(identifier: selectedEventID, relativePath: "Missing Event Folder", createFolder: false)
        ]
    )
    let sidebarSelection = ActiveLibrarySidebarResolver.SidebarSelection(
        rawSelection: sidebarRawSelection(libraryID: selectedLibraryID, eventID: selectedEventID),
        identifiers: [selectedLibraryID, selectedEventID]
    )

    try expectThrowsContaining("selected Event root does not exist") {
        _ = try resolver.resolveActiveLibraryEvent(
            candidates: [missingEventLibrary],
            rangeMatchedSelections: [],
            sidebarSelection: sidebarSelection
        )
    }
}

func testProductionSourceDoesNotReintroduceFFImportTargetSelectionHints() throws {
    let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
    let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
    let productionSource = repoRoot
        .appendingPathComponent("fxplug", isDirectory: true)
        .appendingPathComponent("TokyoWalkingStabilizer", isDirectory: true)
        .appendingPathComponent("Plugin", isDirectory: true)
        .appendingPathComponent("TokyoWalkingStabilizer.swift", isDirectory: false)
    let sourceText = try String(contentsOf: productionSource, encoding: .utf8)

    try expectContains(sourceText, "FFSidebarModuleLibrary", "Production source sanity check should read the active library resolver implementation")
    for bannedToken in ["FFImportTarget", "activeFinalCutLibrarySelectionHints", "selectionHints"] {
        try expect(!sourceText.contains(bannedToken), "Production resolver should not reintroduce stale \(bannedToken)-based active library selection")
    }
}

let tests: [(String, () throws -> Void)] = [
    ("sidebar selection matches only the correct flexolibrary and Event relativePath", testSidebarSelectionMatchesOnlyCorrectFlexolibraryAndEventRelativePath),
    ("range match absent uses sidebar selection for a unique Event", testRangeMatchAbsentUsesSidebarSelectionForUniqueEvent),
    ("ignores stale FFImportTarget values and uses FFSidebarModuleLibrary selection", testIgnoresStaleFFImportTargetValuesAndUsesFFSidebarModuleLibrarySelection),
    ("multiple sidebar matches fail visibly", testMultipleSidebarMatchesFailVisibly),
    ("missing Event folder fails visibly", testSidebarSelectionWithMissingEventFolderFailsVisibly),
    ("production source does not reintroduce FFImportTarget selection hints", testProductionSourceDoesNotReintroduceFFImportTargetSelectionHints)
]

var failures: [String] = []
for (name, test) in tests {
    do {
        try test()
        print("PASS \(name)")
    } catch {
        let message = "FAIL \(name): \(error)"
        failures.append(message)
        print(message)
    }
}

print("fixture root: \(fixtures.root.path)")

if !failures.isEmpty {
    exit(1)
}

print("All \(tests.count) active library resolver tests passed.")
