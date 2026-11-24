import DBKit
import Foundation
import Testing

/// rust-dbkit's `cast_records` of `cast_integration.rs`. `Date` stands in for its `timestamp`, `timestamptz` and
/// `date` columns; Swift has no type for its `time` column `clock_time`, so the table leaves it out.
@Model(table: "cast_records")
class CastRecordModel {
    @Key @AutoIncrement var id: Int64
    var enabled: Bool
    var integerValue: Int32
    var floatValue: Double
    var numericText: String
    var uuidText: String
    var externalID: UUID
    var recordedAt: Date
    var recordedAtUTC: Date
    var day: Date
    var elapsed: Interval
    var nullableInteger: Int32?
    var nullableText: String?
}

/// rust-dbkit's `CastResult`, without the casts to and from `timestamp`, `date` and `time`, which have no Swift type.
private struct CastResult: Decodable {
    let integerToSmall: Int16
    let integerToBig: Int64
    let integerToFloat: Double
    let floatToInteger: Int32
    let integerToBool: Bool
    let boolToInteger: Int32
    let numericTextToFloat: Double
    let integerToText: String
    let textToUUID: UUID
    let uuidToText: String
    let dateToTimestamptz: Date
    let timestampToTimestamptz: Date
    let nullableIntegerToFloat: Double?
    let nullableTextToUUID: UUID?
}

/// Rows decode into `CastResult` by alias.
@Suite struct CastIntegrationTests {
    @Test func castsRoundtripAcrossNumericTextUUIDAndTemporalTypes() async throws {
        try await withRollback { tx in
            try await tx.query("SET LOCAL TIME ZONE 'UTC'")
            try await setupSchema(on: tx)
            let row = try await seedRecord(on: tx, numericText: "12.5", floatValue: 2.6)

            let result = try #require(
                try await CastRecordModel.query()
                    .select(
                        CastRecordModel.integerValue.cast(to: Int16.self).as("integer_to_small"),
                        CastRecordModel.integerValue.cast(to: Int64.self).as("integer_to_big"),
                        CastRecordModel.integerValue.cast(to: Double.self).as("integer_to_float"),
                        CastRecordModel.floatValue.cast(to: Int32.self).as("float_to_integer"),
                        CastRecordModel.integerValue.cast(to: Bool.self).as("integer_to_bool"),
                        CastRecordModel.enabled.cast(to: Int32.self).as("bool_to_integer"),
                        CastRecordModel.numericText.cast(to: Double.self).as("numeric_text_to_float"),
                        CastRecordModel.integerValue.cast(to: String.self).as("integer_to_text"),
                        CastRecordModel.uuidText.cast(to: UUID.self).as("text_to_uuid"),
                        CastRecordModel.externalID.cast(to: String.self).as("uuid_to_text"),
                        CastRecordModel.day.cast(to: Date.self).as("date_to_timestamptz"),
                        CastRecordModel.recordedAt.cast(to: Date.self).as("timestamp_to_timestamptz"),
                        CastRecordModel.nullableInteger.cast(to: Double.self).as("nullable_integer_to_float"),
                        CastRecordModel.nullableText.cast(to: UUID.self).as("nullable_text_to_uuid")
                    )
                    .filter(CastRecordModel.id == row.id)
                    .first(as: CastResult.self, on: tx))

            #expect(result.integerToSmall == 7)
            #expect(result.integerToBig == 7)
            #expect(result.integerToFloat == 7.0)
            #expect(result.floatToInteger == 3)
            #expect(result.integerToBool)
            #expect(result.boolToInteger == 1)
            #expect(result.numericTextToFloat == 12.5)
            #expect(result.integerToText == "7")
            #expect(result.textToUUID == row.externalID)
            #expect(result.uuidToText == row.externalID.uuidString.lowercased())
            #expect(result.dateToTimestamptz == isoDate("2025-02-03T00:00:00Z"))
            #expect(result.timestampToTimestamptz == row.recordedAtUTC)
            #expect(result.nullableIntegerToFloat == nil)
            #expect(result.nullableTextToUUID == nil)
        }
    }

    /// The query decodes as a one-element tuple, where rust-dbkit decodes a struct with one field.
    @Test func invalidTextCastReturnsPostgresError() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let row = try await seedRecord(on: tx, numericText: "not-a-number", floatValue: 2.6)

            let error = try await #require(throws: PSQLError.self) {
                try await CastRecordModel.query()
                    .select(CastRecordModel.numericText.cast(to: Double.self))
                    .filter(CastRecordModel.id == row.id)
                    .first(on: tx)
            }
            #expect(error.serverInfo?[.sqlState] == "22P02")
        }
    }

    @Test func overflowingNumericCastReturnsPostgresError() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let row = try await seedRecord(on: tx, numericText: "12.5", floatValue: 100_000)

            let error = try await #require(throws: PSQLError.self) {
                try await CastRecordModel.query()
                    .select(CastRecordModel.floatValue.cast(to: Int16.self))
                    .filter(CastRecordModel.id == row.id)
                    .first(on: tx)
            }
            #expect(error.serverInfo?[.sqlState] == "22003")
        }
    }
}

private func setupSchema(on tx: Transaction) async throws {
    try await tx.query(
        """
        CREATE TEMP TABLE cast_records (
            id BIGSERIAL PRIMARY KEY, enabled BOOLEAN NOT NULL, integer_value INTEGER NOT NULL,
            float_value DOUBLE PRECISION NOT NULL, numeric_text TEXT NOT NULL, uuid_text TEXT NOT NULL, external_id UUID NOT NULL,
            recorded_at TIMESTAMP NOT NULL, recorded_at_utc TIMESTAMPTZ NOT NULL, day DATE NOT NULL, elapsed INTERVAL NOT NULL,
            nullable_integer INTEGER, nullable_text TEXT
        )
        """)
}

/// A row recorded at 2025-02-03 12:34:56 UTC.
private func seedRecord(on tx: Transaction, numericText: String, floatValue: Double) async throws -> CastRecordModel {
    let externalID = try #require(UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000"))
    let recordedAt = isoDate("2025-02-03T12:34:56Z")
    let insert = CastRecordModel.Insert(
        enabled: true, integerValue: 7, floatValue: floatValue, numericText: numericText, uuidText: externalID.uuidString.lowercased(),
        externalID: externalID, recordedAt: recordedAt, recordedAtUTC: recordedAt, day: isoDate("2025-02-03T00:00:00Z"),
        elapsed: .hours(2), nullableInteger: nil, nullableText: nil)
    return try #require(try await CastRecordModel.insert(insert).returningAll().first(on: tx))
}
