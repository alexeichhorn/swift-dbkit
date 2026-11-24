import DBKit
import Foundation
import Testing

/// rust-dbkit's `nullable_arithmetic_records`. `Date` stands in for its `timestamp` columns. Waits for slice 12:
/// `var requiredInterval: Interval` and `var nullableInterval: Interval?`.
@Model(table: "nullable_arithmetic_records")
class NullableArithmeticRecordModel {
    @Key @AutoIncrement var id: Int64
    var requiredValue: Int32
    var nullableLeft: Int32?
    var nullableRight: Int32?
    var requiredAt: Date
    var nullableAt: Date?
}

/// One column of each numeric type, for arithmetic across types.
@Model(table: "mixed_numbers")
class MixedNumberModel {
    @Key @AutoIncrement var id: Int64
    var small: Int16
    var medium: Int32
    var large: Int64
    var fraction: Float
    var ratio: Double
}

@Suite struct ArithmeticIntegrationTests {
    @Test func arithmeticNumericFiltersAndOrderingRoundtrip() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let row1 = try await seedRecord(on: tx, 2, 8, baseline: 10, at: isoDate("2024-04-01T09:00:00Z"))
            let row2 = try await seedRecord(on: tx, 4, 9, baseline: 20, at: isoDate("2024-04-01T10:00:00Z"))
            _ = try await seedRecord(on: tx, 7, 8, baseline: 8, at: isoDate("2024-04-01T11:00:00Z"))

            let rows = try await RecordModel.query()
                .filter(RecordModel.leftValue + 1 < RecordModel.baselineValue)
                .filter(RecordModel.rightValue - RecordModel.leftValue > 3)
                .orderBy((RecordModel.baselineValue + RecordModel.leftValue).desc)
                .all(on: tx)

            #expect(rows.map(\.id) == [row2.id, row1.id])
        }
    }

    /// Integer division truncates toward zero, as in PostgreSQL; casting one operand divides in `double precision`.
    @Test func divisionRoundtripsAndSortsBeforePagination() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let occurredAt = isoDate("2024-04-01T09:00:00Z")
            let first = try await seedRecord(on: tx, -5, 2, baseline: 0, at: occurredAt)
            _ = try await seedRecord(on: tx, 9, 4, baseline: 0, at: occurredAt)
            let third = try await seedRecord(on: tx, 11, 5, baseline: 0, at: occurredAt)

            let floatingQuotient: Expr<Double> = RecordModel.leftValue.cast(to: Double.self) / RecordModel.rightValue
            let rows = try await RecordModel.query().orderBy(floatingQuotient.asc).limit(2).all(on: tx)
            #expect(rows.map(\.id) == [first.id, third.id])

            let integerQuotient: Expr<Int32> = RecordModel.leftValue / RecordModel.rightValue
            let negative = try await RecordModel.query().filter(integerQuotient == -2).all(on: tx)
            #expect(negative.map(\.id) == [first.id])
            // Waits for slice 14: `integerQuotient` and `floatingQuotient` as the projections `integer_quotient` and
            // `floating_quotient` of `RecordModel.id`, ordered by `floatingQuotient` with `limit(2)`: quotients
            // `[-2, 2]` and `[-2.5, 2.2]`.
        }
    }

    /// An integer divided by a `real` or the reverse is `double precision`; `real` by `real` stays `real`.
    @Test func mixedIntegerAndRealDivisionRoundtripsAsDoublePrecision() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let row = try await seedRecord(on: tx, 5, 2, baseline: 0, at: isoDate("2024-04-01T09:00:00Z"))

            let integerByReal: Expr<Double> = RecordModel.leftValue / RecordModel.realValue
            let realByInteger: Expr<Double> = RecordModel.realValue / RecordModel.leftValue
            let realByReal: Expr<Float> = RecordModel.realValue / RecordModel.realValue
            // `real` 2 / 5 equals the `Double` 0.4 only when PostgreSQL divides in `double precision`.
            let rows = try await RecordModel.query()
                .filter(integerByReal == 2.5)
                .filter(realByInteger == 0.4)
                .filter(realByReal == 1)
                .filter(RecordModel.id == row.id)
                .all(on: tx)
            #expect(rows.map(\.id) == [row.id])
            // Waits for slice 14: the three quotients as projections, decoded as `Double` 2.5, `Double` 0.4 and `Float` 1.
        }
    }

    @Test func divisionByZeroReturnsPostgresError() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            _ = try await seedRecord(on: tx, 1, 0, baseline: 0, at: isoDate("2024-04-01T09:00:00Z"))

            let error = try await #require(throws: PSQLError.self) {
                try await RecordModel.query().filter(RecordModel.leftValue / RecordModel.rightValue > 0).all(on: tx)
            }
            #expect(error.serverInfo?[.sqlState] == "22012")
        }
    }

    /// `smallint` arithmetic with an `integer` operand composes with `integer` predicates, and two `smallint`s order rows.
    @Test func smallintArithmeticFiltersRoundtripWithIntegerRHS() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let row1 = try await seedCompactRecord(on: tx, 5, 5)
            let row2 = try await seedCompactRecord(on: tx, 6, 5)
            _ = try await seedCompactRecord(on: tx, 8, 5)

            let rows = try await CompactRecordModel.query()
                .filter(CompactRecordModel.leftUnits + CompactRecordModel.rightUnits.cast(to: Int32.self) > Int32(9))
                .filter(CompactRecordModel.leftUnits - CompactRecordModel.rightUnits.cast(to: Int32.self) < Int32(2))
                .orderBy((CompactRecordModel.leftUnits - CompactRecordModel.rightUnits).asc)
                .all(on: tx)

            #expect(rows.map(\.id) == [row1.id, row2.id])
        }
    }

    /// Mixed types follow PostgreSQL's promotion: the wider integer, and `double precision` once a float meets an
    /// integer or a `real` meets a `double precision`. `smallint` 3 times `integer` 40000 runs in `integer`.
    @Test func mixedNumericArithmeticRunsAndDecodesAsThePromotedType() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let insert = MixedNumberModel.Insert(small: 3, medium: 40_000, large: 5_000_000_000, fraction: 0.5, ratio: 0.25)
            let row = try #require(try await MixedNumberModel.insert(insert).returningAll().first(on: tx))

            let large: Expr<Int64> = MixedNumberModel.small * MixedNumberModel.medium + MixedNumberModel.large
            let ratio: Expr<Double> = MixedNumberModel.medium + MixedNumberModel.fraction - MixedNumberModel.ratio
            let scaled: Expr<Double> = MixedNumberModel.large * MixedNumberModel.fraction
            let updated = try await MixedNumberModel.update()
                .set(MixedNumberModel.large, to: large)
                .set(MixedNumberModel.ratio, to: ratio)
                .filter(MixedNumberModel.id == row.id)
                .filter(scaled == 2_500_000_000)
                .returningAll()
                .all(on: tx)

            #expect(updated.map(\.large) == [5_000_120_000])
            #expect(updated.map(\.ratio) == [40_000.25])
        }
    }

    @Test func nullableArithmeticPropagatesNullFromEitherOperand() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let base = isoDate("2024-04-03T12:00:00Z")
            try await NullableArithmeticRecordModel.insert([
                NullableArithmeticRecordModel.Insert(
                    requiredValue: 10, nullableLeft: 4, nullableRight: 2, requiredAt: base, nullableAt: base),
                NullableArithmeticRecordModel.Insert(
                    requiredValue: 10, nullableLeft: nil, nullableRight: 2, requiredAt: base, nullableAt: nil),
                NullableArithmeticRecordModel.Insert(
                    requiredValue: 10, nullableLeft: 4, nullableRight: nil, requiredAt: base, nullableAt: base),
                NullableArithmeticRecordModel.Insert(
                    requiredValue: 10, nullableLeft: nil, nullableRight: nil, requiredAt: base, nullableAt: nil),
            ])
            .execute(on: tx)
            // Waits for slice 14: the projections `added`, `subtracted`, `multiplied`, `divided`, `floating_divided`
            // and `literal_minus_nullable` per row, NULL wherever an operand is NULL.
            // Waits for slice 12: the projections of `nullableAt` and `requiredAt` plus or minus the interval columns, and
            // of `base` plus or minus `SQL.interval(hours:)` of the nullable columns.

            let matching = try await NullableArithmeticRecordModel.query()
                .filter(100 - NullableArithmeticRecordModel.nullableLeft == 96)
                .filter(NullableArithmeticRecordModel.nullableLeft + NullableArithmeticRecordModel.requiredValue == 14)
                .orderBy(NullableArithmeticRecordModel.id.asc)
                .all(on: tx)
            #expect(matching.map(\.id) == [1, 3])
            // Waits for slice 12: the filter `nullableAt + requiredInterval == base + 1 hour` on `matching`.

            let nullResults = try await NullableArithmeticRecordModel.query()
                .filter((100 - NullableArithmeticRecordModel.nullableLeft).isNull)
                .orderBy(NullableArithmeticRecordModel.id.asc)
                .all(on: tx)
            #expect(nullResults.map(\.id) == [2, 4])
        }
    }

    @Test func nullableOrderedColumnComparisonsExcludeNullOperands() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let operands: [(Int32?, Int32?)] = [(4, 2), (1, 2), (3, 3), (nil, 2), (4, nil), (nil, nil)]
            try await NullableArithmeticRecordModel.insert(
                operands.map { left, right in
                    NullableArithmeticRecordModel.Insert(requiredValue: 0, nullableLeft: left, nullableRight: right, requiredAt: Date())
                }
            )
            .execute(on: tx)

            func ids(_ predicate: Expr<Bool?>) async throws -> [Int64] {
                try await NullableArithmeticRecordModel.query().filter(predicate).orderBy(NullableArithmeticRecordModel.id.asc).all(on: tx)
                    .map(\.id)
            }
            #expect(try await ids(NullableArithmeticRecordModel.nullableLeft < NullableArithmeticRecordModel.nullableRight) == [2])
            #expect(try await ids(NullableArithmeticRecordModel.nullableLeft <= NullableArithmeticRecordModel.nullableRight) == [2, 3])
            #expect(try await ids(NullableArithmeticRecordModel.nullableLeft > NullableArithmeticRecordModel.nullableRight) == [1])
            #expect(try await ids(NullableArithmeticRecordModel.nullableLeft >= NullableArithmeticRecordModel.nullableRight) == [1, 3])
        }
    }

    @Test func requiredColumnsCompareToNullableRHSExpressions() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let operands: [(Int32, Int32?)] = [(5, 2), (3, 2), (2, 2), (5, nil)]
            try await NullableArithmeticRecordModel.insert(
                operands.map { required, left in
                    NullableArithmeticRecordModel.Insert(
                        requiredValue: required, nullableLeft: left, nullableRight: nil, requiredAt: Date())
                }
            )
            .execute(on: tx)
            // Waits for slice 14: the projections `less`, `less_or_equal`, `greater`, `greater_or_equal`, `nullable_left`,
            // `required` and `coalesced` comparing with `nullableLeft + 1`, `requiredValue + 1` and `nullableLeft ?? 0`,
            // and the projections comparing `requiredValue` with `nullableLeft` directly.

            let greater = try await NullableArithmeticRecordModel.query()
                .filter(NullableArithmeticRecordModel.requiredValue > NullableArithmeticRecordModel.nullableLeft + 1)
                .all(on: tx)
            #expect(greater.map(\.id) == [1])

            let lessOrEqual = try await NullableArithmeticRecordModel.query()
                .filter(NullableArithmeticRecordModel.requiredValue <= NullableArithmeticRecordModel.nullableLeft + 1)
                .orderBy(NullableArithmeticRecordModel.id.asc)
                .all(on: tx)
            #expect(lessOrEqual.map(\.id) == [2, 3])
        }
    }
}

private func setupSchema(on tx: Transaction) async throws {
    try await tx.query(
        """
        CREATE TEMP TABLE records (
            id BIGSERIAL PRIMARY KEY, left_value INTEGER NOT NULL, right_value INTEGER NOT NULL, real_value REAL NOT NULL,
            baseline_value INTEGER NOT NULL, occurred_at TIMESTAMPTZ NOT NULL
        )
        """)
    try await tx.query(
        """
        CREATE TEMP TABLE mixed_numbers (
            id BIGSERIAL PRIMARY KEY, small SMALLINT NOT NULL, medium INTEGER NOT NULL, large BIGINT NOT NULL,
            fraction REAL NOT NULL, ratio DOUBLE PRECISION NOT NULL
        )
        """)
    try await tx.query(
        "CREATE TEMP TABLE compact_records (id BIGSERIAL PRIMARY KEY, left_units SMALLINT NOT NULL, right_units SMALLINT NOT NULL)")
    try await tx.query(
        """
        CREATE TEMP TABLE nullable_arithmetic_records (
            id BIGSERIAL PRIMARY KEY, required_value INTEGER NOT NULL, nullable_left INTEGER, nullable_right INTEGER,
            required_at TIMESTAMPTZ NOT NULL, nullable_at TIMESTAMPTZ
        )
        """)
}

private func seedRecord(on tx: Transaction, _ leftValue: Int32, _ rightValue: Int32, baseline: Int32, at occurredAt: Date) async throws
    -> RecordModel
{
    let insert = RecordModel.Insert(
        leftValue: leftValue, rightValue: rightValue, realValue: 2, baselineValue: baseline, occurredAt: occurredAt)
    return try #require(try await RecordModel.insert(insert).returningAll().first(on: tx))
}

private func seedCompactRecord(on tx: Transaction, _ leftUnits: Int16, _ rightUnits: Int16) async throws -> CompactRecordModel {
    try #require(
        try await CompactRecordModel.insert(CompactRecordModel.Insert(leftUnits: leftUnits, rightUnits: rightUnits)).returningAll().first(
            on: tx))
}
