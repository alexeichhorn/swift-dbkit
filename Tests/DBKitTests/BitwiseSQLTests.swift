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

/// rust-dbkit selects each expression as a projection. The tests also order by the expressions, which renders them and
/// their binds in the same order.
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

        let projected = BitRegisterModel.query()
            .select(
                (BitRegisterModel.mediumValue & 12).as("anded"),
                (BitRegisterModel.mediumValue | 3).as("ored"),
                (BitRegisterModel.mediumValue ^ 10).as("xored"),
                (~BitRegisterModel.mediumValue).as("inverted"),
                (BitRegisterModel.mediumValue << 4).as("shifted_left"),
                (BitRegisterModel.mediumValue >> Int16(2)).as("shifted_right")
            )
            .render()
        #expect(
            projected.sql
                == #"SELECT ("bit_registers"."medium_value" & $1) AS "anded", ("bit_registers"."medium_value" | $2) AS "ored", ("bit_registers"."medium_value" # $3) AS "xored", (~"bit_registers"."medium_value") AS "inverted", ("bit_registers"."medium_value" << $4) AS "shifted_left", ("bit_registers"."medium_value" >> $5) AS "shifted_right" FROM "bit_registers""#
        )
        #expect(typedBinds(projected) == ["Int32(12)", "Int32(3)", "Int32(10)", "Int32(4)", "Int16(2)"])
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

        let projected = BitRegisterModel.query()
            .select(smallAndMedium.as("small_and_medium"), mediumOrLarge.as("medium_or_large"), largeXorSmall.as("large_xor_small"))
            .render()
        #expect(
            projected.sql
                == #"SELECT ("bit_registers"."small_value" & "bit_registers"."medium_value") AS "small_and_medium", ("bit_registers"."medium_value" | "bit_registers"."large_value") AS "medium_or_large", ("bit_registers"."large_value" # "bit_registers"."small_value") AS "large_xor_small" FROM "bit_registers""#
        )
        #expect(projected.binds.isEmpty)
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

        let projected = BitRegisterModel.query()
            .select(
                (Int16(15) & BitRegisterModel.smallValue).as("anded"),
                (Int32(8) | BitRegisterModel.mediumValue).as("ored"),
                (Int64(255) ^ BitRegisterModel.largeValue).as("xored"),
                (Int64(1) << BitRegisterModel.shiftCount).as("shifted_left"),
                (Int64(-8) >> BitRegisterModel.shiftCount).as("shifted_right")
            )
            .render()
        #expect(
            projected.sql
                == #"SELECT ($1 & "bit_registers"."small_value") AS "anded", ($2 | "bit_registers"."medium_value") AS "ored", ($3 # "bit_registers"."large_value") AS "xored", ($4 << "bit_registers"."shift_count") AS "shifted_left", ($5 >> "bit_registers"."shift_count") AS "shifted_right" FROM "bit_registers""#
        )
        #expect(typedBinds(projected) == ["Int16(15)", "Int32(8)", "Int64(255)", "Int64(1)", "Int64(-8)"])
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

        let projected = BitRegisterModel.query()
            .select(
                requiredWithNullable.as("required_with_nullable"),
                nullableWithRequired.as("nullable_with_required"),
                nullableShift.as("nullable_shift"),
                nullableNot.as("nullable_not")
            )
            .render()
        #expect(
            projected.sql
                == #"SELECT ("bit_registers"."large_value" & "bit_registers"."nullable_value") AS "required_with_nullable", ("bit_registers"."nullable_value" | "bit_registers"."large_value") AS "nullable_with_required", ("bit_registers"."nullable_value" << "bit_registers"."nullable_shift_count") AS "nullable_shift", (~"bit_registers"."nullable_value") AS "nullable_not" FROM "bit_registers""#
        )
        #expect(projected.binds.isEmpty)
    }
}

/// Each bind as `<type>(<value>)`, since a bind's integer type is the width PostgreSQL computes in.
private func typedBinds(_ rendered: RenderedSQL) -> [String] {
    rendered.binds.map { "\(type(of: $0.value))(\($0))" }
}
