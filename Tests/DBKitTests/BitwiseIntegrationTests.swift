import DBKit
import Testing

/// rust-dbkit's `bitwise_samples`, without its `permissions` column of a custom integer-backed type.
@Model(table: "bitwise_samples")
class BitwiseSampleModel {
    @Key @AutoIncrement var id: Int64
    var smallValue: Int16
    var mediumValue: Int32
    var largeValue: Int64
    var nullableLarge: Int64?
    var shiftCount: Int32
    var nullableShiftCount: Int32?
}

private typealias Sample = BitwiseSampleModel

/// rust-dbkit selects the results as projections. Filters also compare them with the expected values, so a row comes
/// back only when PostgreSQL computes every one of them.
@Suite struct BitwiseIntegrationTests {
    @Test func allScalarOperatorsRoundtrip() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let sample = try await seedSample(on: tx, medium: 0b1010, shiftCount: 2)

            let andValue: Expr<Int32> = Sample.mediumValue & 0b1100
            let orValue: Expr<Int32> = Sample.mediumValue | 0b0101
            let xorValue: Expr<Int32> = Sample.mediumValue ^ 0b1111
            let inverted: Expr<Int32> = ~Sample.mediumValue
            let shiftedLeft: Expr<Int32> = Sample.mediumValue << Sample.shiftCount
            let shiftedRight: Expr<Int32> = Sample.mediumValue >> Int16(1)
            let rows = try await Sample.query()
                .filter(andValue == 0b1000)
                .filter(orValue == 0b1111)
                .filter(xorValue == 0b0101)
                .filter(inverted == ~Int32(0b1010))
                .filter(shiftedLeft == 0b10_1000)
                .filter(shiftedRight == 0b0101)
                .all(on: tx)
            #expect(rows.map(\.id) == [sample.id])

            // A tuple stands in for rust-dbkit's `OperatorProjection`.
            let projected = try #require(
                try await Sample.query()
                    .select(andValue, orValue, xorValue, inverted, shiftedLeft, shiftedRight)
                    .filter(Sample.id == sample.id)
                    .first(on: tx))
            #expect(projected.0 == 0b1000)
            #expect(projected.1 == 0b1111)
            #expect(projected.2 == 0b0101)
            #expect(projected.3 == ~Int32(0b1010))
            #expect(projected.4 == 0b10_1000)
            #expect(projected.5 == 0b0101)
        }
    }

    /// PostgreSQL widens mixed integer operands instead of truncating either side. The results are assigned to columns
    /// of their type.
    @Test func mixedIntegerWidthsPromoteToTheWiderType() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let sample = try await seedSample(on: tx, small: 0b1100, medium: 0b1010, large: 0b1_0001)

            let smallAndMedium: Expr<Int32> = Sample.smallValue & Sample.mediumValue
            let mediumOrLarge: Expr<Int64> = Sample.mediumValue | Sample.largeValue
            let largeXorSmall: Expr<Int64> = Sample.largeValue ^ Sample.smallValue
            let updated = try await Sample.update()
                .set(Sample.mediumValue, to: smallAndMedium)
                .set(Sample.largeValue, to: mediumOrLarge)
                .set(Sample.nullableLarge, to: largeXorSmall)
                .filter(Sample.id == sample.id)
                .returningAll()
                .all(on: tx)

            #expect(updated.map(\.mediumValue) == [0b1000])
            #expect(updated.map(\.largeValue) == [0b1_1011])
            #expect(updated.map(\.nullableLarge) == [0b1_1101])

            // A `@Projection` stands in for rust-dbkit's `MixedWidthProjection`. The update above changed the row, so
            // this projects a second one with the same values.
            @Projection struct MixedWidthProjection {
                let smallAndMedium: Int32
                let mediumOrLarge: Int64
                let largeXorSmall: Int64
            }
            let unchanged = try await seedSample(on: tx, small: 0b1100, medium: 0b1010, large: 0b1_0001)
            let projected = try #require(
                try await Sample.query()
                    .select(
                        MixedWidthProjection.columns(
                            smallAndMedium: smallAndMedium, mediumOrLarge: mediumOrLarge, largeXorSmall: largeXorSmall)
                    )
                    .filter(Sample.id == unchanged.id)
                    .first(on: tx))
            #expect(projected.smallAndMedium == 0b1000)
            #expect(projected.mediumOrLarge == 0b1_1011)
            #expect(projected.largeXorSmall == 0b1_1101)
        }
    }

    /// rust-dbkit computes `1 << 63` in Rust and binds the result; here PostgreSQL shifts into the sign bit.
    @Test func zeroAllBitsAndSignedShiftsFollowPostgresSemantics() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let sample = try await seedSample(on: tx, large: -8)

            let zeroAnd: Expr<Int64> = Sample.largeValue & 0
            let zeroOr: Expr<Int64> = Sample.largeValue | 0
            let allBits: Expr<Int64> = Sample.largeValue & -1
            let literalAllBits: Expr<Int64> = ~Int64(0) & Sample.largeValue
            let signBit: Expr<Int64> = Expr<Int64>.value(1) << 63
            let signedRightShift: Expr<Int64> = Sample.largeValue >> 2
            let unchangedByZeroShift: Expr<Int64> = Sample.largeValue << 0
            let rows = try await Sample.query()
                .filter(zeroAnd == 0)
                .filter(zeroOr == -8)
                .filter(allBits == -8)
                .filter(literalAllBits == -8)
                .filter(signBit == Int64.min)
                .filter(signedRightShift == -2)
                .filter(unchangedByZeroShift == -8)
                .all(on: tx)
            #expect(rows.map(\.id) == [sample.id])

            let projected = try #require(
                try await Sample.query()
                    .select(
                        zeroAnd.as("zero_and"),
                        zeroOr.as("zero_or"),
                        allBits.as("all_bits"),
                        literalAllBits.as("literal_all_bits"),
                        signBit.as("sign_bit"),
                        signedRightShift.as("signed_right_shift"),
                        unchangedByZeroShift.as("unchanged_by_zero_shift")
                    )
                    .filter(Sample.id == sample.id)
                    .first(as: EdgeProjection.self, on: tx))
            #expect(
                projected
                    == EdgeProjection(
                        zeroAnd: 0, zeroOr: -8, allBits: -8, literalAllBits: -8, signBit: Int64.min, signedRightShift: -2,
                        unchangedByZeroShift: -8))
        }
    }

    @Test func nullPropagatesFromValuesAndShiftCounts() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let filled = try await seedSample(on: tx, large: 0b1010, nullableLarge: 0b1100, shiftCount: 2, nullableShiftCount: 1)
            let empty = try await seedSample(on: tx, large: 0b1010, shiftCount: 2)

            let andValue: Expr<Int64?> = Sample.nullableLarge & 0b1010
            let orValue: Expr<Int64?> = Sample.nullableLarge | Sample.largeValue
            let xorValue: Expr<Int64?> = Sample.largeValue ^ Sample.nullableLarge
            let inverted: Expr<Int64?> = ~Sample.nullableLarge
            let shiftedByRequired: Expr<Int64?> = Sample.nullableLarge << Sample.shiftCount
            let shiftedByNullable: Expr<Int64?> = Sample.largeValue >> Sample.nullableShiftCount

            let values = try await Sample.query()
                .filter(andValue == 0b1000)
                .filter(orValue == 0b1110)
                .filter(xorValue == 0b0110)
                .filter(inverted == ~Int64(0b1100))
                .filter(shiftedByRequired == 0b11_0000)
                .filter(shiftedByNullable == 0b0101)
                .all(on: tx)
            #expect(values.map(\.id) == [filled.id])

            let nulls = try await Sample.query()
                .filter(andValue.isNull)
                .filter(orValue.isNull)
                .filter(xorValue.isNull)
                .filter(inverted.isNull)
                .filter(shiftedByRequired.isNull)
                .filter(shiftedByNullable.isNull)
                .all(on: tx)
            #expect(nulls.map(\.id) == [empty.id])

            // Aliased expressions decode as a tuple too; rust-dbkit decodes them into its `NullableProjection`.
            let projected = try await Sample.query()
                .select(
                    andValue.as("and_value"),
                    orValue.as("or_value"),
                    xorValue.as("xor_value"),
                    inverted.as("inverted"),
                    shiftedByRequired.as("shifted_by_required"),
                    shiftedByNullable.as("shifted_by_nullable")
                )
                .orderBy(Sample.id.asc)
                .all(on: tx)
            #expect(projected.count == 2)
            #expect(projected.map(\.0) == [0b1000, nil])
            #expect(projected.map(\.1) == [0b1110, nil])
            #expect(projected.map(\.2) == [0b0110, nil])
            #expect(projected.map(\.3) == [~Int64(0b1100), nil])
            #expect(projected.map(\.4) == [0b11_0000, nil])
            #expect(projected.map(\.5) == [0b0101, nil])
        }
    }

    @Test func composedExpressionsFilterAndOrderRows() async throws {
        try await withRollback { tx in
            try await setupSchema(on: tx)
            let first = try await seedSample(on: tx, large: 0b0011)
            let second = try await seedSample(on: tx, large: 0b0110)
            let third = try await seedSample(on: tx, large: 0b1100)

            let score = ((Sample.largeValue & 0b1111) ^ 0b0011) << 1
            let rows = try await Sample.query().filter(score > 0b1000).orderBy(score.desc).all(on: tx)

            #expect(rows.map(\.id) == [third.id, second.id])
            #expect(!rows.contains { $0.id == first.id })
        }
    }
}

/// rust-dbkit's `EdgeProjection`, decoded by alias.
private struct EdgeProjection: Decodable, Equatable {
    let zeroAnd: Int64
    let zeroOr: Int64
    let allBits: Int64
    let literalAllBits: Int64
    let signBit: Int64
    let signedRightShift: Int64
    let unchangedByZeroShift: Int64
}

private func setupSchema(on tx: Transaction) async throws {
    try await tx.query(
        """
        CREATE TEMP TABLE bitwise_samples (
            id BIGSERIAL PRIMARY KEY, small_value SMALLINT NOT NULL, medium_value INTEGER NOT NULL, large_value BIGINT NOT NULL,
            nullable_large BIGINT, shift_count INTEGER NOT NULL, nullable_shift_count INTEGER
        )
        """)
}

private func seedSample(
    on tx: Transaction, small: Int16 = 0, medium: Int32 = 0, large: Int64 = 0, nullableLarge: Int64? = nil, shiftCount: Int32 = 0,
    nullableShiftCount: Int32? = nil
) async throws -> BitwiseSampleModel {
    let insert = BitwiseSampleModel.Insert(
        smallValue: small, mediumValue: medium, largeValue: large, nullableLarge: nullableLarge, shiftCount: shiftCount,
        nullableShiftCount: nullableShiftCount)
    return try #require(try await BitwiseSampleModel.insert(insert).returningAll().first(on: tx))
}
