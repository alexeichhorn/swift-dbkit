import DBKit

// `TextSampleModel.width` is rust-dbkit's `integer` column `attempts`. Both the text and the searched text are text.
private func searchesTakeText() {
    _ = SQL.position(TextSampleModel.width, "1")  // error: 'position'
    _ = SQL.startsWith(TextSampleModel.title, TextSampleModel.width)  // error: 'startsWith'
}
