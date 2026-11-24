import DBKit

// A column, and a comparison on it, keeps its nullability: neither converts to the other kind.
// rust-dbkit also rejects `Option<&str>` values for `Option<String>` columns; Swift has one string type.

private func columnsDoNotChangeNullability() {
    let _: Column<NullabilityRowModel, String> = NullabilityRowModel.nullableText  // error: cannot assign value of type
    let _: Column<NullabilityRowModel, String?> = NullabilityRowModel.requiredText  // error: cannot assign value of type
    // Waits for slice 15: `lowercased()` of a nullable column is not `Expr<String>`, of a required one not `Expr<String?>`.
}

private func comparisonsDoNotChangeNullability() {
    let present: String? = "present"
    let _: Expr<Bool> = NullabilityRowModel.nullableText == "present"  // error: 'Expr<Bool>'
    let _: Expr<Bool> = NullabilityRowModel.nullableText == present  // error: 'Expr<Bool>'
    let _: Expr<Bool> = NullabilityRowModel.nullableText == nil  // error: 'Expr<Bool>'
    let _: Expr<Bool> = NullabilityRowModel.nullableCount < 5  // error: 'Expr<Bool>'
    let _: Expr<Bool> = NullabilityRowModel.nullableCount.between(1, 10)  // error: 'Expr<Bool>'
    let _: Expr<Bool> = NullabilityRowModel.nullableText.like("pre%")  // error: 'Expr<Bool>'
    let _: Expr<Bool> = NullabilityRowModel.nullableText.in(["present"])  // error: 'Expr<Bool>'
    let _: Expr<Bool> = (NullabilityRowModel.nullableText == "present") && NullabilityRowModel.id > 0  // error: 'Expr<Bool>'
    let _: Expr<Bool> = !(NullabilityRowModel.nullableText == "present")  // error: 'Expr<Bool>'
    let _: Expr<Bool?> = NullabilityRowModel.requiredText == "required"  // error: 'Expr<Bool?>'
}
