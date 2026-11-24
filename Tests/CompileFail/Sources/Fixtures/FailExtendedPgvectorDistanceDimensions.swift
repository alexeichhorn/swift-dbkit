import DBKit

// A distance takes two vectors of one dimension, on either side and with a nullable column.

private func distancesToAnotherDimension() throws {
    let half = try HalfVector<4>([1, 1, 1, 1])
    let sparse = try SparseVector<4>([(0, 1)])
    let bits = try BitVector<4>([true, true, true, true])
    _ = VectorKindsModel.half.l2Distance(to: half)  // error: 'l2Distance
    _ = VectorKindsModel.optionalSparse.cosineDistance(to: sparse)  // error: 'cosineDistance
    _ = VectorKindsModel.optionalBits.hammingDistance(to: bits)  // error: 'hammingDistance
    _ = Expr.value(bits).jaccardDistance(to: VectorKindsModel.bits)  // error: 'jaccardDistance
}
