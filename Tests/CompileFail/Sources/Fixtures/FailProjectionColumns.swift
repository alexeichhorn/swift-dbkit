import DBKit

/// `columns(…)` takes one expression per stored property, each of the property's exact type.
@Projection
struct TextPair {
    let text: String
    let note: String?
}

private typealias N = NullabilityRowModel

private func projectionColumnsMatchTheStruct() {
    let query = N.query()
    _ = query.select(TextPair.columns(text: N.requiredText))  // error: missing argument for parameter 'note'
    _ = query.select(TextPair.columns(text: N.requiredText, nott: N.nullableText))  // error: incorrect argument label
    _ = query.select(TextPair.columns(text: N.requiredCount, note: N.nullableText))  // error: 'Int32' and 'String' be equivalent
    _ = query.select(TextPair.columns(text: N.nullableText, note: N.nullableText))  // error: 'String?' and 'String' be equivalent
    _ = query.select(TextPair.columns(text: N.requiredText, note: N.requiredText))  // error: 'String' and 'String?' be equivalent
}
