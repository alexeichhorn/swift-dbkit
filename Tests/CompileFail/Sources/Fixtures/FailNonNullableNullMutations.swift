import DBKit

// Inserts, updates and active models reject `nil` and optional values for required columns.

private func nullMutationsOnRequiredColumns() {
    let noText: String? = nil
    let someText: String? = "value"

    _ = NullabilityRowModel.Insert(id: 1, requiredText: nil, requiredCount: 1)  // error: 'nil'
    _ = NullabilityRowModel.Insert(id: 1, requiredText: someText, requiredCount: 1)  // error: 'String?'
    _ = NullabilityRowModel.update().set(NullabilityRowModel.requiredText, to: nil)  // error: 'nil'
    _ = NullabilityRowModel.update().set(NullabilityRowModel.requiredText, to: noText)  // error: 'String?'
    _ = NullabilityRowModel.update().set(NullabilityRowModel.requiredText, to: someText)  // error: 'String?'

    var active = ActiveModel<NullabilityRowModel>()
    active.requiredText = nil  // error: 'nil'
    active.requiredText = someText  // error: 'String?'
    _ = active
}
