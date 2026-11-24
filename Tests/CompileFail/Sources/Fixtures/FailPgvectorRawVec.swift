import DBKit

// A vector column takes a `Vector`, not a plain array of its values.

private func plainArrayOfValues() {
    let raw: [Float] = [1, 0, 0]
    _ = EmbeddingRowModel.query().filter(EmbeddingRowModel.embedding == raw)  // error: cannot convert value of type '[Float]'
}
