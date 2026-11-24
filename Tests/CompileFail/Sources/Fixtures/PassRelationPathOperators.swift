import DBKit

/// rust-dbkit's `Sample` of `pass_relation_path_operators.rs`.
@Model(table: "numeric_samples")
class SampleModel {
    @Key var id: Int64
    var small: Int16
    var integer: Int32
    var real: Float
    var double: Double
    var nullable: Int32?
    var parentID: Int64?
    @BelongsTo(key: "parentID") var parent: SampleModel?
}

// Every operator a column takes with a value on its left, a path column takes too, and the result stays nullable.
// Arithmetic on two `Int16`s stays `Int16`, where rust-dbkit widens it to `Int32` (see "Arithmetic result types" in
// docs/rust-parity.md).

private func arithmeticKeepsThePathNullable() {
    let parent = SampleModel.Relations.parent
    let _: Expr<Int16?> = Int16(12) + parent.small
    let _: Expr<Int16?> = Int16(12) - parent.small
    let _: Expr<Int16?> = Int16(12) * parent.small
    let _: Expr<Int16?> = Int16(12) / parent.small
    let _: Expr<Int32?> = Int32(12) + parent.integer
    let _: Expr<Int32?> = Int32(12) - parent.integer
    let _: Expr<Int32?> = Int32(12) * parent.integer
    let _: Expr<Int32?> = Int32(12) / parent.integer
    let _: Expr<Int64?> = Int64(12) + parent.id
    let _: Expr<Int64?> = Int64(12) - parent.id
    let _: Expr<Int64?> = Int64(12) * parent.id
    let _: Expr<Int64?> = Int64(12) / parent.id
    let _: Expr<Float?> = Float(12) + parent.real
    let _: Expr<Float?> = Float(12) - parent.real
    let _: Expr<Float?> = Float(12) * parent.real
    let _: Expr<Float?> = Float(12) / parent.real
    let _: Expr<Double?> = Double(12) + parent.double
    let _: Expr<Double?> = Double(12) - parent.double
    let _: Expr<Double?> = Double(12) * parent.double
    let _: Expr<Double?> = Double(12) / parent.double

    // Mixed numeric types promote as PostgreSQL does.
    let _: Expr<Int32?> = Int16(12) / parent.integer
    let _: Expr<Int64?> = Int32(12) / parent.id
    let _: Expr<Double?> = Float(12) / parent.integer
    let _: Expr<Double?> = Int32(12) / parent.real
}

private func bitwiseAndShiftsKeepThePathNullable() {
    let parent = SampleModel.Relations.parent
    let _: Expr<Int16?> = Int16(7) & parent.small
    let _: Expr<Int16?> = Int16(7) | parent.small
    let _: Expr<Int16?> = Int16(7) ^ parent.small
    let _: Expr<Int32?> = Int32(7) & parent.integer
    let _: Expr<Int32?> = Int32(7) | parent.integer
    let _: Expr<Int32?> = Int32(7) ^ parent.integer
    let _: Expr<Int64?> = Int64(7) & parent.id
    let _: Expr<Int64?> = Int64(7) | parent.id
    let _: Expr<Int64?> = Int64(7) ^ parent.id
    let _: Expr<Int32?> = Int16(7) & parent.integer
    let _: Expr<Int32?> = Int16(7) | parent.integer
    let _: Expr<Int32?> = Int16(7) ^ parent.integer
    let _: Expr<Int64?> = Int32(7) & parent.id
    let _: Expr<Int64?> = Int32(7) | parent.id
    let _: Expr<Int64?> = Int32(7) ^ parent.id
    let _: Expr<Int64?> = Int64(7) & parent.small
    let _: Expr<Int64?> = Int64(7) | parent.small
    let _: Expr<Int64?> = Int64(7) ^ parent.small

    let _: Expr<Int16?> = Int16(1) << parent.small
    let _: Expr<Int16?> = Int16(1) >> parent.small
    let _: Expr<Int16?> = Int16(1) << parent.integer
    let _: Expr<Int16?> = Int16(1) >> parent.integer
    let _: Expr<Int32?> = Int32(1) << parent.small
    let _: Expr<Int32?> = Int32(1) >> parent.small
    let _: Expr<Int32?> = Int32(1) << parent.integer
    let _: Expr<Int32?> = Int32(1) >> parent.integer
    let _: Expr<Int64?> = Int64(1) << parent.small
    let _: Expr<Int64?> = Int64(1) >> parent.small
    let _: Expr<Int64?> = Int64(1) << parent.integer
    let _: Expr<Int64?> = Int64(1) >> parent.integer
}

private func nullableColumnsStaySinglyNullableThroughNestedPaths() {
    let parent = SampleModel.Relations.parent
    let column: Expr<Int32?> = parent.parent.nullable
    let _: Expr<Int32?> = Int32(12) + column
    let _: Expr<Int32?> = Int32(12) - column
    let _: Expr<Int32?> = Int32(12) * column
    let _: Expr<Int32?> = Int32(12) / column
    let _: Expr<Int32?> = Int32(7) & column
    let _: Expr<Int32?> = Int32(7) | column
    let _: Expr<Int32?> = Int32(7) ^ column
    let _: Expr<Int64?> = Int64(1) << column
    let _: Expr<Int64?> = Int64(64) >> column

    // Values, columns, expressions and paths compose.
    let _: Expr<Int32?> = (Int32(1) + column) * (parent.integer + Int32(2))
    let _: Expr<Int32?> = SampleModel.integer + column
    let _: Expr<Int32?> = SampleModel.integer - column
    let _: Expr<Int32?> = parent.integer / column
    let _: Expr<Int32?> = SampleModel.integer & column
    let _: Expr<Int32?> = SampleModel.integer | column
    let _: Expr<Int32?> = parent.integer ^ column
}
