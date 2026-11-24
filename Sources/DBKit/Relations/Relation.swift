import Foundation
import PostgresNIO

/// Runtime description of a relation, built by the code `@Model` generates.
public struct Relation: Sendable {
    enum Kind: Sendable {
        case belongsTo
        case hasMany
        case manyToMany(Through)
    }

    struct Through: Sendable {
        let table: String
        /// Join-table column referencing the source.
        let sourceColumn: String
        /// Join-table column referencing the target.
        let targetColumn: String
    }

    let name: String
    let kind: Kind
    let target: any Model.Type
    /// Source-table column of the join condition (the foreign key for belongs-to, the referenced key otherwise).
    let sourceColumn: String
    /// Target-table column of the join condition.
    let targetColumn: String
    /// Relations walked before this one in a relation path like `TodoModel.user.organization`.
    var parents: [Relation] = []

    /// Reads the join key from a source row.
    let sourceKey: @Sendable (any Model) -> KeyValue?
    /// Reads the join key of a target row, the selected `__dbkit_parent` column for many-to-many.
    let targetKey: @Sendable (any Model, RowReader) throws -> KeyValue?
    /// Binds a list of source keys as one array parameter.
    let keyArray: @Sendable ([KeyValue]) -> Bind

    var path: [Relation] { parents + [self] }

    static let parentKeyColumn = "__dbkit_parent"

    public static func belongsTo<Source: Model, Target: Model, Key: SQLType, Referenced: SQLType>(
        _ name: String,
        key: Column<Source, Key>,
        references: Column<Target, Referenced>
    ) -> Relation where Key.NonNull == Referenced.NonNull, Key.NonNull: RelationKey {
        Relation(
            name: name,
            kind: .belongsTo,
            target: Target.self,
            sourceColumn: key.name,
            targetColumn: references.name,
            sourceKey: { relationKey(key.read($0 as! Source)) },
            targetKey: { row, _ in relationKey(references.read(row as! Target)) },
            keyArray: { Bind($0.map { $0.value as! Key.NonNull }) }
        )
    }

    public static func hasMany<Source: Model, Target: Model, Key: SQLType, Referenced: SQLType>(
        _ name: String,
        key: Column<Target, Key>,
        references: Column<Source, Referenced>
    ) -> Relation where Key.NonNull == Referenced.NonNull, Key.NonNull: RelationKey {
        Relation(
            name: name,
            kind: .hasMany,
            target: Target.self,
            sourceColumn: references.name,
            targetColumn: key.name,
            sourceKey: { relationKey(references.read($0 as! Source)) },
            targetKey: { row, _ in relationKey(key.read(row as! Target)) },
            keyArray: { Bind($0.map { $0.value as! Key.NonNull }) }
        )
    }

    public static func manyToMany<Source: Model, Target: Model, Through: Model, SourceKey: SQLValue & RelationKey, TargetKey: SQLValue>(
        _ name: String,
        from: Column<Through, SourceKey>,
        to: Column<Through, TargetKey>,
        sourceKey: Column<Source, SourceKey>,
        targetKey: Column<Target, TargetKey>
    ) -> Relation {
        Relation(
            name: name,
            kind: .manyToMany(Relation.Through(table: Through.schema.table, sourceColumn: from.name, targetColumn: to.name)),
            target: Target.self,
            sourceColumn: sourceKey.name,
            targetColumn: targetKey.name,
            sourceKey: { KeyValue(sourceKey.read($0 as! Source)) },
            targetKey: { _, reader in KeyValue(try reader.decode(SourceKey.self, Relation.parentKeyColumn)) },
            keyArray: { Bind($0.map { $0.value as! SourceKey }) }
        )
    }
}

/// Key types usable in relations: hashable for in-memory matching and bindable as a PostgreSQL array.
public protocol RelationKey: SQLValue, Hashable, PostgresArrayEncodable, PostgresArrayDecodable where _DecodableType == Self {}
extension Int16: RelationKey {}
extension Int32: RelationKey {}
extension Int64: RelationKey {}
extension Int: RelationKey {}
extension String: RelationKey {}
extension UUID: RelationKey {}

private func relationKey<Key: SQLType>(_ value: Key) -> KeyValue? where Key.NonNull: RelationKey {
    value.nonNull.map(KeyValue.init)
}

/// A type-erased, sendable relation key for matching rows in memory.
struct KeyValue: Hashable, Sendable {
    let value: any RelationKey

    init(_ value: some RelationKey) {
        self.value = value
    }

    static func == (lhs: KeyValue, rhs: KeyValue) -> Bool { AnyHashable(lhs.value) == AnyHashable(rhs.value) }
    func hash(into hasher: inout Hasher) { AnyHashable(value).hash(into: &hasher) }
}
