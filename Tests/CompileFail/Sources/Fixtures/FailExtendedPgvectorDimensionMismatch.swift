import DBKit

// A `halfvec`, `sparsevec` or `bit` column takes values of its own dimension only.

private func valuesOfAnotherDimension() throws {
    let half = try HalfVector<4>([1, 1, 1, 1])
    let sparse = try SparseVector<4>([(0, 1)])
    let bits = try BitVector<4>([true, true, true, true])
    _ = VectorKindsModel.query().filter(VectorKindsModel.half == half)  // error: cannot convert value of type 'HalfVector<4>'
    _ = VectorKindsModel.query().filter(VectorKindsModel.sparse == sparse)  // error: cannot convert value of type 'SparseVector<4>'
    _ = VectorKindsModel.query().filter(VectorKindsModel.bits == bits)  // error: cannot convert value of type 'BitVector<4>'
}
