import DBKit
import Foundation
import Testing

/// rust-dbkit's `nullable_arithmetic_records`. `Date` stands in for its `timestamp` columns.
@Model(table: "nullable_arithmetic_records")
class NullableArithmeticRecordModel {
    @Key @AutoIncrement var id: Int64
    var requiredValue: Int32
    var nullableLeft: Int32?
    var nullableRight: Int32?
    var requiredAt: Date
    var nullableAt: Date?
    var requiredInterval: Interval
    var nullableInterval: Interval?
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

            // Rows decode into a `Decodable` struct by alias, as rust-dbkit's `DivisionResult`.
            let quotients = try await RecordModel.query()
                .select(RecordModel.id.as("id"), integerQuotient.as("integer_quotient"), floatingQuotient.as("floating_quotient"))
                .orderBy(floatingQuotient.asc)
                .limit(2)
                .all(as: DivisionResult.self, on: tx)
            #expect(quotients.map(\.id) == [first.id, third.id])
            #expect(quotients.map(\.integerQuotient) == [-2, 2])
            #expect(quotients.map(\.floatingQuotient) == [-2.5, 2.2])
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

            // A `@Projection` stands in for rust-dbkit's `MixedRealDivisionResult`.
            @Projection struct MixedRealDivisionResult {
                let integerByReal: Double
                let realByInteger: Double
                let realByReal: Float
            }
            let result = try #require(
                try await RecordModel.query()
                    .select(
                        MixedRealDivisionResult.columns(integerByReal: integerByReal, realByInteger: realByInteger, realByReal: realByReal)
                    )
                    .filter(RecordModel.id == row.id)
                    .first(on: tx))
            #expect(result.integerByReal == 2.5)
            #expect(result.realByInteger == 0.4)
            #expect(result.realByReal == 1)
        }
    }

    @Test func arithmeticTemporalOffsetFilterAndOrderingRoundtrip() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let base = isoDate("2024-04-02T08:00:00Z")
            let row1 = try await seedRecord(on: tx, 1, 0, baseline: 0, at: base)
            let row2 = try await seedRecord(on: tx, 3, 0, baseline: 0, at: base + 3600)
            _ = try await seedRecord(on: tx, 5, 0, baseline: 0, at: base + 4 * 3600)

            let cutoff = base + 4 * 3600
            let rows = try await RecordModel.query()
                .filter(RecordModel.occurredAt + SQL.interval(hours: RecordModel.leftValue) <= cutoff)
                .orderBy((RecordModel.occurredAt - SQL.interval(hours: 1)).asc)
                .all(on: tx)

            #expect(rows.map(\.id) == [row1.id, row2.id])
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

    /// `SUM` decodes as the type PostgreSQL returns: `bigint` for `smallint` and `integer`, `numeric` for `bigint`, and
    /// the input type for `real` and `double precision`. Each integer sum here exceeds its input type. Without input rows
    /// every sum is NULL.
    @Test func sumsDecodeAsThePostgreSQLResultType() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let row = MixedNumberModel.Insert(
                small: 30_000, medium: 2_000_000_000, large: 9_000_000_000_000_000_000, fraction: 0.5, ratio: 0.25)
            try await MixedNumberModel.insert([row, row]).execute(on: tx)

            let query = MixedNumberModel.query()
                .select(
                    SQL.sum(MixedNumberModel.small),
                    SQL.sum(MixedNumberModel.medium),
                    SQL.sum(MixedNumberModel.large),
                    SQL.sum(MixedNumberModel.fraction),
                    SQL.sum(MixedNumberModel.ratio)
                )
            let sums: (Int64?, Int64?, Decimal?, Float?, Double?) = try #require(try await query.first(on: tx))
            #expect(sums.0 == 60_000)
            #expect(sums.1 == 4_000_000_000)
            #expect(sums.2 == Decimal(string: "18000000000000000000"))
            #expect(sums.3 == 1)
            #expect(sums.4 == 0.5)

            let empty = try #require(try await query.filter(MixedNumberModel.id < 0).first(on: tx))
            #expect(empty.0 == nil && empty.1 == nil && empty.2 == nil && empty.3 == nil && empty.4 == nil)
        }
    }

    @Test func nullableArithmeticPropagatesNullFromEitherOperand() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let base = isoDate("2024-04-03T12:00:00Z")
            try await NullableArithmeticRecordModel.insert([
                NullableArithmeticRecordModel.Insert(
                    requiredValue: 10, nullableLeft: 4, nullableRight: 2, requiredAt: base, nullableAt: base,
                    requiredInterval: .hours(1), nullableInterval: .hours(2)),
                NullableArithmeticRecordModel.Insert(
                    requiredValue: 10, nullableLeft: nil, nullableRight: 2, requiredAt: base, nullableAt: nil,
                    requiredInterval: .hours(1), nullableInterval: .hours(2)),
                NullableArithmeticRecordModel.Insert(
                    requiredValue: 10, nullableLeft: 4, nullableRight: nil, requiredAt: base, nullableAt: base,
                    requiredInterval: .hours(1), nullableInterval: nil),
                NullableArithmeticRecordModel.Insert(
                    requiredValue: 10, nullableLeft: nil, nullableRight: nil, requiredAt: base, nullableAt: nil,
                    requiredInterval: .hours(1), nullableInterval: nil),
            ])
            .execute(on: tx)

            typealias R = NullableArithmeticRecordModel
            let added: Expr<Int32?> = R.nullableLeft + R.requiredValue
            let subtracted: Expr<Int32?> = R.requiredValue - R.nullableRight
            let multiplied: Expr<Int32?> = R.nullableLeft * R.nullableRight
            let divided: Expr<Int32?> = R.nullableLeft / R.nullableRight
            let floatingDivided: Expr<Double?> = R.nullableLeft.cast(to: Double.self) / R.nullableRight
            let literalMinusNullable: Expr<Int32?> = 100 - R.nullableLeft
            let nullableTimeRequiredInterval: Expr<Date?> = R.nullableAt + R.requiredInterval
            let requiredTimeNullableInterval: Expr<Date?> = R.requiredAt - R.nullableInterval
            let nullableTimeNullableInterval: Expr<Date?> = R.nullableAt + R.nullableInterval
            let literalTimePlusNullableInterval: Expr<Date?> = base + SQL.interval(hours: R.nullableLeft)
            let literalTimeMinusNullableInterval: Expr<Date?> = base - SQL.interval(hours: R.nullableRight)
            let rows = try await R.query()
                .select(
                    added.as("added"),
                    subtracted.as("subtracted"),
                    multiplied.as("multiplied"),
                    divided.as("divided"),
                    floatingDivided.as("floating_divided"),
                    literalMinusNullable.as("literal_minus_nullable"),
                    nullableTimeRequiredInterval.as("nullable_time_required_interval"),
                    requiredTimeNullableInterval.as("required_time_nullable_interval"),
                    nullableTimeNullableInterval.as("nullable_time_nullable_interval"),
                    literalTimePlusNullableInterval.as("literal_time_plus_nullable_interval"),
                    literalTimeMinusNullableInterval.as("literal_time_minus_nullable_interval")
                )
                .orderBy(R.id.asc)
                .all(as: NullableArithmeticResult.self, on: tx)

            let hours = { (count: Double) in base + count * 3600 }
            #expect(rows.count == 4)
            #expect(rows.map(\.added) == [14, nil, 14, nil])
            #expect(rows.map(\.subtracted) == [8, 8, nil, nil])
            #expect(rows.map(\.multiplied) == [8, nil, nil, nil])
            #expect(rows.map(\.divided) == [2, nil, nil, nil])
            #expect(rows.map(\.floatingDivided) == [2.0, nil, nil, nil])
            #expect(rows.map(\.literalMinusNullable) == [96, nil, 96, nil])
            #expect(rows.map(\.nullableTimeRequiredInterval) == [hours(1), nil, hours(1), nil])
            #expect(rows.map(\.requiredTimeNullableInterval) == [hours(-2), hours(-2), nil, nil])
            #expect(rows.map(\.nullableTimeNullableInterval) == [hours(2), nil, nil, nil])
            #expect(rows.map(\.literalTimePlusNullableInterval) == [hours(4), nil, hours(4), nil])
            #expect(rows.map(\.literalTimeMinusNullableInterval) == [hours(-2), hours(-2), nil, nil])

            let oneHourLater = base + 3600
            let matching = try await NullableArithmeticRecordModel.query()
                .filter(100 - NullableArithmeticRecordModel.nullableLeft == 96)
                .filter(NullableArithmeticRecordModel.nullableLeft + NullableArithmeticRecordModel.requiredValue == 14)
                .filter(NullableArithmeticRecordModel.nullableAt + NullableArithmeticRecordModel.requiredInterval == oneHourLater)
                .orderBy(NullableArithmeticRecordModel.id.asc)
                .all(on: tx)
            #expect(matching.map(\.id) == [1, 3])

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
                    NullableArithmeticRecordModel.Insert(
                        requiredValue: 0, nullableLeft: left, nullableRight: right, requiredAt: Date(), requiredInterval: .hours(1))
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
                        requiredValue: required, nullableLeft: left, nullableRight: nil, requiredAt: Date(), requiredInterval: .hours(1))
                }
            )
            .execute(on: tx)

            // A `@Projection` stands in for rust-dbkit's `NullableRhsComparisonResult`, and a tuple for its
            // `DirectNullableRhsComparisonResult`. `??` is rust-dbkit's `func::coalesce` here.
            @Projection struct NullableRHSComparisonResult {
                let less: Bool?
                let lessOrEqual: Bool?
                let greater: Bool?
                let greaterOrEqual: Bool?
                let nullableLeft: Bool?
                let required: Bool
                let coalesced: Bool
            }
            typealias R = NullableArithmeticRecordModel
            let nullableRHS: Expr<Int32?> = R.nullableLeft + 1
            let requiredRHS: Expr<Int32> = R.requiredValue + 1
            let less: Expr<Bool?> = R.requiredValue < nullableRHS
            let lessOrEqual: Expr<Bool?> = R.requiredValue <= nullableRHS
            let greater: Expr<Bool?> = R.requiredValue > nullableRHS
            let greaterOrEqual: Expr<Bool?> = R.requiredValue >= nullableRHS
            let nullableLeft: Expr<Bool?> = R.nullableLeft < requiredRHS
            let required: Expr<Bool> = R.requiredValue < requiredRHS
            let coalesced: Expr<Bool> = R.requiredValue < (R.nullableLeft ?? 0)
            let rows = try await R.query()
                .select(
                    NullableRHSComparisonResult.columns(
                        less: less, lessOrEqual: lessOrEqual, greater: greater, greaterOrEqual: greaterOrEqual,
                        nullableLeft: nullableLeft, required: required, coalesced: coalesced)
                )
                .orderBy(R.id.asc)
                .all(on: tx)
            #expect(rows.map(\.less) == [false, false, true, nil])
            #expect(rows.map(\.lessOrEqual) == [false, true, true, nil])
            #expect(rows.map(\.greater) == [true, false, false, nil])
            #expect(rows.map(\.greaterOrEqual) == [true, true, false, nil])
            #expect(rows.map(\.nullableLeft) == [true, true, true, nil])
            #expect(rows.map(\.required) == [true, true, true, true])
            #expect(rows.map(\.coalesced) == [false, false, false, false])

            let directLess: Expr<Bool?> = R.requiredValue < R.nullableLeft
            let directLessOrEqual: Expr<Bool?> = R.requiredValue <= R.nullableLeft
            let directGreater: Expr<Bool?> = R.requiredValue > R.nullableLeft
            let directGreaterOrEqual: Expr<Bool?> = R.requiredValue >= R.nullableLeft
            let directRows: [(Bool?, Bool?, Bool?, Bool?)] = try await R.query()
                .select(directLess, directLessOrEqual, directGreater, directGreaterOrEqual)
                .orderBy(R.id.asc)
                .all(on: tx)
            #expect(directRows.map(\.0) == [false, false, false, nil])
            #expect(directRows.map(\.1) == [false, false, true, nil])
            #expect(directRows.map(\.2) == [true, true, false, nil])
            #expect(directRows.map(\.3) == [true, true, true, nil])

            let greaterRows = try await NullableArithmeticRecordModel.query()
                .filter(NullableArithmeticRecordModel.requiredValue > NullableArithmeticRecordModel.nullableLeft + 1)
                .all(on: tx)
            #expect(greaterRows.map(\.id) == [1])

            let lessOrEqualRows = try await NullableArithmeticRecordModel.query()
                .filter(NullableArithmeticRecordModel.requiredValue <= NullableArithmeticRecordModel.nullableLeft + 1)
                .orderBy(NullableArithmeticRecordModel.id.asc)
                .all(on: tx)
            #expect(lessOrEqualRows.map(\.id) == [2, 3])
        }
    }
}

/// rust-dbkit's `DivisionResult`.
private struct DivisionResult: Decodable {
    let id: Int64
    let integerQuotient: Int32
    let floatingQuotient: Double
}

/// rust-dbkit's `NullableArithmeticResult`.
private struct NullableArithmeticResult: Decodable {
    let added: Int32?
    let subtracted: Int32?
    let multiplied: Int32?
    let divided: Int32?
    let floatingDivided: Double?
    let literalMinusNullable: Int32?
    let nullableTimeRequiredInterval: Date?
    let requiredTimeNullableInterval: Date?
    let nullableTimeNullableInterval: Date?
    let literalTimePlusNullableInterval: Date?
    let literalTimeMinusNullableInterval: Date?
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
            required_at TIMESTAMPTZ NOT NULL, nullable_at TIMESTAMPTZ, required_interval INTERVAL NOT NULL, nullable_interval INTERVAL
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
