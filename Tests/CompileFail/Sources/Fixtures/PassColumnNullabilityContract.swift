import DBKit

// A comparison on a nullable operand can be NULL, so it is `Expr<Bool?>`; on required operands it is `Expr<Bool>`.
// Only `isNull` and `isNotNull` are never NULL. Filters take both. The annotations fail to compile when a result type changes.

private func columnsKeepTheirNullability() {
    let _: Column<NullabilityRowModel, String> = NullabilityRowModel.requiredText
    let _: Column<NullabilityRowModel, String?> = NullabilityRowModel.nullableText
    let _: Column<NullabilityRowModel, Int32> = NullabilityRowModel.requiredCount
    let _: Column<NullabilityRowModel, Int32?> = NullabilityRowModel.nullableCount
    let _: Column<NullabilityRowModel, Int32?> = NullabilityRowModel.nullableLimit
}

private func valueComparisonsFollowTheColumn() {
    let text: String? = "owned"
    let nullText: String? = nil
    let count: Int32? = 5
    let nullCount: Int32? = nil

    let _: Expr<Bool> = NullabilityRowModel.requiredText == "required"
    let _: Expr<Bool> = NullabilityRowModel.requiredText != "other"
    let _: Expr<Bool> = NullabilityRowModel.requiredCount < 5
    let _: Expr<Bool> = NullabilityRowModel.requiredCount <= 5
    let _: Expr<Bool> = NullabilityRowModel.requiredCount > 5
    let _: Expr<Bool> = NullabilityRowModel.requiredCount >= 5
    let _: Expr<Bool> = NullabilityRowModel.requiredCount.between(1, 10)
    let _: Expr<Bool> = NullabilityRowModel.requiredText.like("req%")
    let _: Expr<Bool> = NullabilityRowModel.requiredText.ilike("REQ%")
    let _: Expr<Bool> = NullabilityRowModel.requiredText.in(["required", "other"])
    let _: Expr<Bool> = NullabilityRowModel.requiredText.notIn(["required", "other"])

    let _: Expr<Bool?> = NullabilityRowModel.nullableText == "present"
    let _: Expr<Bool?> = NullabilityRowModel.nullableText == text
    let _: Expr<Bool?> = NullabilityRowModel.nullableText == nullText
    let _: Expr<Bool?> = NullabilityRowModel.nullableText != "present"
    let _: Expr<Bool?> = NullabilityRowModel.nullableText != text
    let _: Expr<Bool?> = NullabilityRowModel.nullableText != nullText
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount < 5
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount < count
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount < nullCount
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount <= 5
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount <= count
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount <= nullCount
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount > 5
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount > count
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount > nullCount
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount >= 5
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount >= count
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount >= nullCount
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount.between(1, 10)
    let _: Expr<Bool?> = NullabilityRowModel.nullableText.like("pre%")
    let _: Expr<Bool?> = NullabilityRowModel.nullableText.ilike("PRE%")
    let _: Expr<Bool?> = NullabilityRowModel.nullableText.in(["present", "other"])
    let _: Expr<Bool?> = NullabilityRowModel.nullableText.in([String]())
    let _: Expr<Bool?> = NullabilityRowModel.nullableText.notIn(["present", "other"])

    // Optional arguments to the list and pattern operators, as rust-dbkit accepts them for nullable columns.
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount.between(count, count)
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount.between(nullCount, count)
    let _: Expr<Bool?> = NullabilityRowModel.nullableText.like(text)
    let _: Expr<Bool?> = NullabilityRowModel.nullableText.like(nullText)
    let _: Expr<Bool?> = NullabilityRowModel.nullableText.ilike(nullText)
    let _: Expr<Bool?> = NullabilityRowModel.nullableText.in([text, nullText])
    let _: Expr<Bool?> = NullabilityRowModel.nullableText.notIn([text, nullText])

    let _: Expr<Bool?> = NullabilityRowModel.nullableText == nil
    let _: Expr<Bool?> = NullabilityRowModel.nullableText != nil
    let _: Expr<Bool> = NullabilityRowModel.nullableText.isNull
    let _: Expr<Bool> = NullabilityRowModel.nullableText.isNotNull

    // Waits for slice 15: `lowercased()` keeping nullability, comparisons on it, `SQL.coalesce`, `SQL.greatest` and
    // `SQL.least` (a required argument makes them required).

    // Arithmetic on a nullable column is nullable, and so are comparisons on it.
    let nullableSum = NullabilityRowModel.nullableCount + NullabilityRowModel.requiredCount
    let requiredSum = NullabilityRowModel.requiredCount + 1
    let _: Expr<Bool?> = nullableSum == 10
    let _: Expr<Bool?> = nullableSum == nil
    let _: Expr<Bool?> = nullableSum < 10
    let _: Expr<Bool?> = nullableSum.between(1, 10)
    let _: Expr<Bool> = requiredSum == 10
    let _: Expr<Bool> = requiredSum < 10
}

// rust-dbkit's `eq_col`, `ne_col`, `lt_col`, `le_col`, `gt_col` and `ge_col` are the operators between two columns, and
// so is its `lt` with a column as the value.
private func columnComparisonsAreNullableWhenEitherColumnIs() {
    let _: Expr<Bool> = NullabilityRowModel.requiredText == NullabilityRowModel.requiredText
    let _: Expr<Bool> = NullabilityRowModel.requiredText != NullabilityRowModel.requiredText
    let _: Expr<Bool?> = NullabilityRowModel.requiredText == NullabilityRowModel.nullableText
    let _: Expr<Bool?> = NullabilityRowModel.nullableText == NullabilityRowModel.requiredText
    let _: Expr<Bool?> = NullabilityRowModel.nullableText == NullabilityRowModel.nullableText
    let _: Expr<Bool?> = NullabilityRowModel.requiredText != NullabilityRowModel.nullableText
    let _: Expr<Bool?> = NullabilityRowModel.nullableText != NullabilityRowModel.requiredText
    let _: Expr<Bool?> = NullabilityRowModel.nullableText != NullabilityRowModel.nullableText

    let _: Expr<Bool> = NullabilityRowModel.requiredText.isDistinct(from: NullabilityRowModel.nullableText)
    let _: Expr<Bool> = NullabilityRowModel.nullableText.isDistinct(from: NullabilityRowModel.requiredText)
    let _: Expr<Bool> = NullabilityRowModel.nullableText.isDistinct(from: NullabilityRowModel.nullableText)
    let _: Expr<Bool> = NullabilityRowModel.requiredText.isNotDistinct(from: NullabilityRowModel.nullableText)
    let _: Expr<Bool> = NullabilityRowModel.nullableText.isNotDistinct(from: NullabilityRowModel.requiredText)
    let _: Expr<Bool> = NullabilityRowModel.nullableText.isNotDistinct(from: NullabilityRowModel.nullableText)

    let _: Expr<Bool> = NullabilityRowModel.requiredCount < NullabilityRowModel.requiredCount
    let _: Expr<Bool> = NullabilityRowModel.requiredCount <= NullabilityRowModel.requiredCount
    let _: Expr<Bool> = NullabilityRowModel.requiredCount > NullabilityRowModel.requiredCount
    let _: Expr<Bool> = NullabilityRowModel.requiredCount >= NullabilityRowModel.requiredCount
    let _: Expr<Bool?> = NullabilityRowModel.requiredCount < NullabilityRowModel.nullableCount
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount < NullabilityRowModel.requiredCount
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount < NullabilityRowModel.nullableLimit
    let _: Expr<Bool?> = NullabilityRowModel.requiredCount <= NullabilityRowModel.nullableCount
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount <= NullabilityRowModel.requiredCount
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount <= NullabilityRowModel.nullableLimit
    let _: Expr<Bool?> = NullabilityRowModel.requiredCount > NullabilityRowModel.nullableCount
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount > NullabilityRowModel.requiredCount
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount > NullabilityRowModel.nullableLimit
    let _: Expr<Bool?> = NullabilityRowModel.requiredCount >= NullabilityRowModel.nullableCount
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount >= NullabilityRowModel.requiredCount
    let _: Expr<Bool?> = NullabilityRowModel.nullableCount >= NullabilityRowModel.nullableLimit

    // An expression on either side follows the same rule.
    let _: Expr<Bool> = (NullabilityRowModel.nullableText ?? "fallback") == NullabilityRowModel.requiredText
    let _: Expr<Bool?> = NullabilityRowModel.nullableText == (NullabilityRowModel.nullableText ?? "fallback")
    let _: Expr<Bool?> = (NullabilityRowModel.nullableCount ?? 0) < NullabilityRowModel.nullableLimit
    let _: Expr<Bool> = NullabilityRowModel.requiredCount.isDistinct(from: NullabilityRowModel.nullableCount ?? 0)

    let nullableComparison: Expr<Bool?> = NullabilityRowModel.nullableText == NullabilityRowModel.requiredText
    let requiredComparison: Expr<Bool> = NullabilityRowModel.requiredText == NullabilityRowModel.requiredText
    let _: Expr<Bool?> = nullableComparison && requiredComparison
    let _: Expr<Bool?> = requiredComparison && nullableComparison
    let _: Expr<Bool?> = nullableComparison && (NullabilityRowModel.nullableText != NullabilityRowModel.requiredText)
    let _: Expr<Bool?> = nullableComparison || requiredComparison
    let _: Expr<Bool?> = requiredComparison || nullableComparison
    let _: Expr<Bool?> = nullableComparison || (NullabilityRowModel.nullableText != NullabilityRowModel.requiredText)
    let _: Expr<Bool?> = !nullableComparison

    _ = NullabilityRowModel.query()
        .filter(nullableComparison)
        .filter(nullableComparison && NullabilityRowModel.id > 0)
    _ = NullabilityRowModel.update().set(NullabilityRowModel.requiredText, to: "updated").filter(nullableComparison)
    _ = NullabilityRowModel.delete().filter(nullableComparison)
    // Waits for slice 15: `lowercased()` of a required column compared with a nullable one and the reverse, `Expr<Bool?>`.

    let nullableSum = NullabilityRowModel.nullableCount + NullabilityRowModel.requiredCount
    let _: Expr<Bool?> = nullableSum == NullabilityRowModel.requiredCount
    let _: Expr<Bool?> = nullableSum != NullabilityRowModel.requiredCount
    let _: Expr<Bool?> = nullableSum < NullabilityRowModel.requiredCount
    let _: Expr<Bool?> = nullableSum <= NullabilityRowModel.requiredCount
    let _: Expr<Bool?> = nullableSum > NullabilityRowModel.requiredCount
    let _: Expr<Bool?> = nullableSum >= NullabilityRowModel.requiredCount
}

private func fallbacksAreRequired() {
    let _: Expr<String> = NullabilityRowModel.nullableText ?? "fallback"
    let _: Expr<String> = NullabilityRowModel.nullableText ?? NullabilityRowModel.requiredText
    let _: Expr<String?> = NullabilityRowModel.nullableText ?? NullabilityRowModel.nullableText
    let _: Expr<Int32> = NullabilityRowModel.nullableCount ?? NullabilityRowModel.requiredCount
}

private func logicIsNullableWhenAnOperandIs() {
    let nullable: Expr<Bool?> = NullabilityRowModel.nullableText == "present"
    let required: Expr<Bool> = NullabilityRowModel.requiredText == "required"

    let _: Expr<Bool> = required && required
    let _: Expr<Bool?> = nullable && required
    let _: Expr<Bool?> = required && nullable
    let _: Expr<Bool?> = nullable && (NullabilityRowModel.nullableText != "other")
    let _: Expr<Bool> = required || required
    let _: Expr<Bool?> = nullable || required
    let _: Expr<Bool?> = required || nullable
    let _: Expr<Bool?> = nullable || (NullabilityRowModel.nullableText != "other")
    let _: Expr<Bool> = !required
    let _: Expr<Bool?> = !nullable
    let _: Expr<Bool> = NullabilityRowModel.nullableText.isNull && required

    _ = NullabilityRowModel.query()
        .filter(NullabilityRowModel.requiredText != "other")
        .filter(NullabilityRowModel.requiredText.like("req%"))
        .filter(NullabilityRowModel.requiredText.in(["required", "other"]))
        .filter(NullabilityRowModel.nullableText != nil)
        .filter(NullabilityRowModel.nullableCount.between(1, 10))
        .filter(nullable)
        .filter(nullable && NullabilityRowModel.id > 0)
    _ = NullabilityRowModel.update().set(NullabilityRowModel.requiredText, to: "updated").filter(nullable)
    _ = NullabilityRowModel.delete().filter(nullable)

    // Waits for slice 13: `Condition` is `Expr<Bool?>` once a nullable predicate is added.
    // Waits for slice 14: `having(nullable)` and `SQL.count(NullabilityRowModel.id).filter(nullable)`.
    // Waits for slice 18: `join(_:on: nullable)` and `leftJoin(_:on: nullable)`.
}

private func mutationsAcceptNilForNullableColumns() {
    let text: String? = "borrowed"
    let nullCount: Int32? = nil

    _ = NullabilityRowModel.insert(
        NullabilityRowModel.Insert(
            id: 1, requiredText: "required", nullableText: nil, requiredCount: 1, nullableCount: 2, nullableLimit: nil))
    _ = NullabilityRowModel.insert(
        NullabilityRowModel.Insert(id: 2, requiredText: "required", nullableText: text, requiredCount: 1, nullableCount: nullCount))

    _ = NullabilityRowModel.update()
        .set(NullabilityRowModel.requiredText, to: "updated")
        .set(NullabilityRowModel.nullableText, to: "present")
    _ = NullabilityRowModel.update()
        .set(NullabilityRowModel.nullableText, to: text)
        .set(NullabilityRowModel.nullableCount, to: nullCount)
    _ = NullabilityRowModel.update()
        .set(NullabilityRowModel.nullableText, to: nil)
        .set(NullabilityRowModel.nullableCount, to: nil)

    var active = ActiveModel<NullabilityRowModel>()
    active.requiredText = "required"
    active.nullableText = "present"
    active.nullableText = text
    active.nullableText = nil
    active.requiredCount = 1
    active.nullableCount = 2
    active.nullableCount = nullCount
    active.nullableCount = nil
    _ = active
}
