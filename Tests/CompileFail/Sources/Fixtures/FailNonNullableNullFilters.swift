import DBKit

// Filters on required columns reject `nil` and optional values. Outside a filter, `column == nil` is the standard
// library's comparison of an optional with `nil`, a plain `Bool`.

private func nullFiltersOnRequiredColumns() {
    let noText: String? = nil
    let someText: String? = "value"
    let noCount: Int32? = nil
    let someCount: Int32? = 5
    let query = NullabilityRowModel.query()

    _ = query.filter(NullabilityRowModel.requiredText == nil)  // error: 'nil'
    _ = query.filter(NullabilityRowModel.requiredText == noText)  // error: 'String?'
    _ = query.filter(NullabilityRowModel.requiredText == someText)  // error: 'String?'
    _ = query.filter(NullabilityRowModel.requiredText != nil)  // error: 'nil'
    _ = query.filter(NullabilityRowModel.requiredText != noText)  // error: 'String?'
    _ = query.filter(NullabilityRowModel.requiredText < noText)  // error: 'String?'
    _ = query.filter(NullabilityRowModel.requiredCount < someCount)  // error: 'Int32?'
    _ = query.filter(NullabilityRowModel.requiredCount <= noCount)  // error: 'Int32?'
    _ = query.filter(NullabilityRowModel.requiredCount > someCount)  // error: 'Int32?'
    _ = query.filter(NullabilityRowModel.requiredCount >= noCount)  // error: 'Int32?'
    _ = query.filter(NullabilityRowModel.requiredText.between("a", noText))  // error: 'String?'
    _ = query.filter(NullabilityRowModel.requiredText.like(noText))  // error: 'String?'
    _ = query.filter(NullabilityRowModel.requiredText.in([noText]))  // error: '[String?]'
    _ = query.filter(NullabilityRowModel.requiredText.notIn([noText]))  // error: '[String?]'
    _ = query.filter(NullabilityRowModel.requiredText.lowercased() == noText)  // error: 'String?'
}
