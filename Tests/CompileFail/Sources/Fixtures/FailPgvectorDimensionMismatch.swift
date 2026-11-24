import DBKit

// The dimension is part of a vector's type, so a vector column takes vectors of its own dimension only.

private func vectorOfAnotherDimension() throws {
    let wrong = try Vector<4>([1, 0, 0, 0])
    _ = EmbeddingRowModel.query().filter(EmbeddingRowModel.embedding == wrong)  // error: cannot convert value of type 'Vector<4>'
}
