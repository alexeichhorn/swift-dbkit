import DBKit

// `halfvec`, `sparsevec` and `bit` columns, required and nullable, in distances, filters, inserts, updates and active
// models. rust-dbkit also checks that its error types implement `Error`; every one here throws `DBKitError`.

/// rust-dbkit's `Embedding` of `pass_extended_pgvector.rs`.
@Model(table: "embeddings")
class ExtendedEmbeddingModel {
    @Key var id: Int64
    var half: HalfVector<3>
    var sparse: SparseVector<1000>
    var bits: BitVector<9>
    var optionalHalf: HalfVector<3>?
    var optionalSparse: SparseVector<1000>?
    var optionalBits: BitVector<9>?
}

private func extendedVectorColumnsInQueriesAndMutations() throws {
    typealias M = ExtendedEmbeddingModel
    let half = try HalfVector<3>([1, 0, 0])
    let sparse = try SparseVector<1000>([(0, 1)])
    let bits = try BitVector<9>([true, false, false, false, false, false, false, false, true])
    let _: Expr<Double> = M.half.cosineDistance(to: half)
    let _: Expr<Double?> = M.optionalSparse.l2Distance(to: sparse)
    let _: Expr<Double> = M.bits.hammingDistance(to: bits)
    let _: Expr<Double?> = Expr.value(bits).jaccardDistance(to: M.optionalBits)

    _ = M.insert(
        M.Insert(id: 1, half: half, sparse: sparse, bits: bits, optionalHalf: half, optionalSparse: sparse, optionalBits: bits)
    )
    .returningAll()

    _ = M.query()
        .filter(M.half == half)
        .filter(M.sparse == sparse)
        .filter(M.bits == bits)
        .filter(M.optionalHalf == nil)
        .filter(M.optionalSparse == nil)
        .filter(M.optionalBits == nil)

    _ = M.update()
        .set(M.half, to: half)
        .set(M.sparse, to: sparse)
        .set(M.bits, to: bits)
        .set(M.optionalHalf, to: nil)
        .set(M.optionalSparse, to: nil)
        .set(M.optionalBits, to: nil)

    var active = ActiveModel<M>()
    active.id = 1
    active.half = half
    active.sparse = sparse
    active.bits = bits
    active.optionalHalf = half
    active.optionalSparse = sparse
    active.optionalBits = bits
    _ = active
}
