import DBKit

// Bit strings take the Hamming and Jaccard distances only, and vectors only the other five.

private func distancesOfTheOtherFamily() throws {
    let bits = try BitVector<3>([true, true, true])
    _ = VectorKindsModel.bits.l2Distance(to: bits)  // error: 'l2Distance
    _ = VectorKindsModel.bits.cosineDistance(to: bits)  // error: 'cosineDistance
    _ = VectorKindsModel.bits.l1Distance(to: bits)  // error: 'l1Distance
    _ = VectorKindsModel.bits.innerProduct(with: bits)  // error: 'innerProduct
    _ = VectorKindsModel.bits.innerProductDistance(to: bits)  // error: 'innerProductDistance
    _ = VectorKindsModel.dense.hammingDistance(to: VectorKindsModel.dense)  // error: 'hammingDistance
    _ = VectorKindsModel.dense.jaccardDistance(to: VectorKindsModel.dense)  // error: 'jaccardDistance
    _ = VectorKindsModel.half.hammingDistance(to: VectorKindsModel.half)  // error: 'hammingDistance
    _ = VectorKindsModel.half.jaccardDistance(to: VectorKindsModel.half)  // error: 'jaccardDistance
    _ = VectorKindsModel.optionalSparse.hammingDistance(to: VectorKindsModel.sparse)  // error: 'hammingDistance
    _ = VectorKindsModel.optionalSparse.jaccardDistance(to: VectorKindsModel.sparse)  // error: 'jaccardDistance
}
