import DBKit
import Testing

/// rust-dbkit's `bit_registers` of `bitwise_sql.rs`, without its `permissions` column of a custom integer-backed type.
@Model(table: "bit_registers")
class BitRegisterModel {
    @Key var id: Int64
    var smallValue: Int16
    var mediumValue: Int32
    var largeValue: Int64
    var nullableValue: Int64?
    var shiftCount: Int32
    var nullableShiftCount: Int32?
}

/// rust-dbkit selects each expression as a projection. Until projections exist, the expressions are ordered by, which
/// renders them and their binds in the same order.
@Suite struct BitwiseSQLTests {
    @Test func compilesEveryBitwiseOperatorWithStableBindOrder() {
        let rendered = BitRegisterModel.query()
            .orderBy(
                (BitRegisterModel.mediumValue & 12).asc,
                (BitRegisterModel.mediumValue | 3).asc,
                (BitRegisterModel.mediumValue ^ 10).asc,
                (~BitRegisterModel.mediumValue).asc,
                (BitRegisterModel.mediumValue << 4).asc,
                (BitRegisterModel.mediumValue >> Int16(2)).asc
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT "bit_registers".* FROM "bit_registers" ORDER BY ("bit_registers"."medium_value" & $1) ASC, ("bit_registers"."medium_value" | $2) ASC, ("bit_registers"."medium_value" # $3) ASC, (~"bit_registers"."medium_value") ASC, ("bit_registers"."medium_value" << $4) ASC, ("bit_registers"."medium_value" >> $5) ASC"#
        )
        #expect(typedBinds(rendered) == ["Int32(12)", "Int32(3)", "Int32(10)", "Int32(4)", "Int16(2)"])
        // Waits for slice 14: the six expressions as the projections `anded`, `ored`, `xored`, `inverted`,
        // `shifted_left` and `shifted_right`.
    }

    @Test func compilesColumnOperandsAndMixedIntegerWidths() {
        let smallAndMedium: Expr<Int32> = BitRegisterModel.smallValue & BitRegisterModel.mediumValue
        let mediumOrLarge: Expr<Int64> = BitRegisterModel.mediumValue | BitRegisterModel.largeValue
        let largeXorSmall: Expr<Int64> = BitRegisterModel.largeValue ^ BitRegisterModel.smallValue
        let rendered = BitRegisterModel.query().orderBy(smallAndMedium.asc, mediumOrLarge.asc, largeXorSmall.asc).render()
        #expect(
            rendered.sql
                == #"SELECT "bit_registers".* FROM "bit_registers" ORDER BY ("bit_registers"."small_value" & "bit_registers"."medium_value") ASC, ("bit_registers"."medium_value" | "bit_registers"."large_value") ASC, ("bit_registers"."large_value" # "bit_registers"."small_value") ASC"#
        )
        #expect(rendered.binds.isEmpty)
        // Waits for slice 14: the three expressions as the projections `small_and_medium`, `medium_or_large` and
        // `large_xor_small`.
    }

    /// Each use of an expression binds its values again.
    @Test func compilesNestedBitwiseExpressionsWithExplicitParentheses() {
        let folded = ~(((BitRegisterModel.largeValue & 255) ^ (BitRegisterModel.largeValue >> 4)) | 1)
        let rendered = BitRegisterModel.query().filter(folded != 0).orderBy(folded.desc).render()
        #expect(
            rendered.sql
                == #"SELECT "bit_registers".* FROM "bit_registers" WHERE (~((("bit_registers"."large_value" & $1) # ("bit_registers"."large_value" >> $2)) | $3)) <> $4 ORDER BY (~((("bit_registers"."large_value" & $5) # ("bit_registers"."large_value" >> $6)) | $7)) DESC"#
        )
        #expect(
            typedBinds(rendered) == ["Int64(255)", "Int32(4)", "Int64(1)", "Int64(0)", "Int64(255)", "Int32(4)", "Int64(1)"])
    }

    @Test func compilesLiteralLeftHandOperands() {
        let rendered = BitRegisterModel.query()
            .orderBy(
                (Int16(15) & BitRegisterModel.smallValue).asc,
                (Int32(8) | BitRegisterModel.mediumValue).asc,
                (Int64(255) ^ BitRegisterModel.largeValue).asc,
                (Int64(1) << BitRegisterModel.shiftCount).asc,
                (Int64(-8) >> BitRegisterModel.shiftCount).asc
            )
            .render()
        #expect(
            rendered.sql
                == #"SELECT "bit_registers".* FROM "bit_registers" ORDER BY ($1 & "bit_registers"."small_value") ASC, ($2 | "bit_registers"."medium_value") ASC, ($3 # "bit_registers"."large_value") ASC, ($4 << "bit_registers"."shift_count") ASC, ($5 >> "bit_registers"."shift_count") ASC"#
        )
        #expect(typedBinds(rendered) == ["Int16(15)", "Int32(8)", "Int64(255)", "Int64(1)", "Int64(-8)"])
        // Waits for slice 14: the five expressions as the projections `anded`, `ored`, `xored`, `shifted_left` and
        // `shifted_right`.
    }

    @Test func compilesNullableOperandsWithoutChangingSQLShape() {
        let requiredWithNullable: Expr<Int64?> = BitRegisterModel.largeValue & BitRegisterModel.nullableValue
        let nullableWithRequired: Expr<Int64?> = BitRegisterModel.nullableValue | BitRegisterModel.largeValue
        let nullableShift: Expr<Int64?> = BitRegisterModel.nullableValue << BitRegisterModel.nullableShiftCount
        let nullableNot: Expr<Int64?> = ~BitRegisterModel.nullableValue
        let rendered = BitRegisterModel.query()
            .orderBy(requiredWithNullable.asc, nullableWithRequired.asc, nullableShift.asc, nullableNot.asc)
            .render()
        #expect(
            rendered.sql
                == #"SELECT "bit_registers".* FROM "bit_registers" ORDER BY ("bit_registers"."large_value" & "bit_registers"."nullable_value") ASC, ("bit_registers"."nullable_value" | "bit_registers"."large_value") ASC, ("bit_registers"."nullable_value" << "bit_registers"."nullable_shift_count") ASC, (~"bit_registers"."nullable_value") ASC"#
        )
        #expect(rendered.binds.isEmpty)
        // Waits for slice 14: the four expressions as the projections `required_with_nullable`, `nullable_with_required`,
        // `nullable_shift` and `nullable_not`.
    }
}

/// Each bind as `<type>(<value>)`, since a bind's integer type is the width PostgreSQL computes in.
private func typedBinds(_ rendered: RenderedSQL) -> [String] {
    rendered.binds.map { "\(type(of: $0.value))(\($0))" }
}
