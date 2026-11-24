import DBKit

// A vector column, required and nullable, in distances, filters, ordering, inserts, updates and active models. Each
// distance is `Double`, and `Double?` when either side is nullable.

private func vectorColumnsInQueriesAndMutations() throws {
    let query = try Vector<3>([1, 0, 0])
    let replacement = try Vector<3>([0, 1, 0])
    let (embedding, optional) = (EmbeddingRowModel.embedding, EmbeddingRowModel.embeddingOptional)

    let _: Expr<Double> = embedding.l2Distance(to: query)
    let _: Expr<Double> = embedding.cosineDistance(to: query)
    let _: Expr<Double> = embedding.innerProduct(with: query)
    let _: Expr<Double> = embedding.l1Distance(to: query)
    let _: Expr<Double> = embedding.innerProductDistance(to: query)
    let _: Expr<Double?> = optional.l2Distance(to: query)
    let _: Expr<Double?> = optional.cosineDistance(to: query)
    let _: Expr<Double?> = optional.innerProduct(with: query)
    let _: Expr<Double?> = optional.l1Distance(to: query)
    let _: Expr<Double?> = optional.innerProductDistance(to: query)
    let _: Expr<Double?> = Expr.value(query).l2Distance(to: optional)
    let _: Expr<Double?> = optional.cosineDistance(to: optional)

    _ = EmbeddingRowModel.query()
        .filter(embedding == query)
        .filter(optional == nil)
        .filter(embedding.l2Distance(to: query) < 0.5)
        .filter(embedding.cosineDistance(to: query) < 0.2)
        .filter(embedding.innerProduct(with: query) > 0.8)
        .orderBy(embedding.l1Distance(to: query).asc)

    _ = EmbeddingRowModel.insert(EmbeddingRowModel.Insert(id: 1, label: "hello", embedding: replacement, embeddingOptional: replacement))

    _ = EmbeddingRowModel.update()
        .set(embedding, to: replacement)
        .set(optional, to: replacement)

    var active = ActiveModel<EmbeddingRowModel>()
    active.id = 1
    active.label = "active"
    active.embedding = replacement
    active.embeddingOptional = nil
    _ = active
}
