import DBKit

// A distance takes two vectors of one kind: `vector`, `halfvec` and `sparsevec` don't mix.

private func distancesBetweenVectorKinds() throws {
    let dense = try Vector<3>([1, 1, 1])
    let half = try HalfVector<3>([1, 1, 1])
    let sparse = try SparseVector<3>([(0, 1)])
    _ = VectorKindsModel.dense.l2Distance(to: half)  // error: 'l2Distance
    _ = VectorKindsModel.half.l2Distance(to: dense)  // error: 'l2Distance
    _ = VectorKindsModel.half.cosineDistance(to: sparse)  // error: 'cosineDistance
    _ = VectorKindsModel.optionalSparse.cosineDistance(to: half)  // error: 'cosineDistance
    _ = VectorKindsModel.dense.innerProductDistance(to: sparse)  // error: 'innerProductDistance
    _ = VectorKindsModel.optionalSparse.innerProductDistance(to: dense)  // error: 'innerProductDistance
}
