extension Model where Self == Base {
    /// Loads a relation afterwards with one select-in query: `let user = try await user.load(\.todos, on: db)`.
    public func load<L: RelationLoad>(_ relation: KeyPath<Relations.Type, L>, on executor: some DatabaseExecutor) async throws -> L.Output
    where L.Source == Self {
        try await selectIn(Relations.self[keyPath: relation], for: [self], on: executor)[0]
    }

    /// Loads a relation afterwards, with nested loads for its rows.
    public func load<L: RelationLoad, Nested: RelationLoad>(
        _ relation: KeyPath<Relations.Type, L>,
        on executor: some DatabaseExecutor,
        _ nested: (L) -> Nested
    ) async throws -> Nested.Output where Nested.Source == Self {
        try await selectIn(nested(Relations.self[keyPath: relation]), for: [self], on: executor)[0]
    }
}

extension LoadedModel {
    /// Loads another relation afterwards, keeping the ones already loaded.
    public func load<L: RelationLoad>(_ relation: KeyPath<LoadedRelations.Type, L>, on executor: some DatabaseExecutor) async throws
        -> L.Output where L.Source == Self
    {
        try await selectIn(LoadedRelations.self[keyPath: relation], for: [self], on: executor)[0]
    }
}

extension Array where Element: Model, Element == Element.Base {
    /// Loads a relation for every row with one select-in query.
    public func load<L: RelationLoad>(_ relation: KeyPath<Element.Relations.Type, L>, on executor: some DatabaseExecutor) async throws -> [L
        .Output]
    where L.Source == Element {
        try await selectIn(Element.Relations.self[keyPath: relation], for: self, on: executor)
    }

    public func load<L: RelationLoad, Nested: RelationLoad>(
        _ relation: KeyPath<Element.Relations.Type, L>,
        on executor: some DatabaseExecutor,
        _ nested: (L) -> Nested
    ) async throws -> [Nested.Output] where Nested.Source == Element {
        try await selectIn(nested(Element.Relations.self[keyPath: relation]), for: self, on: executor)
    }
}
