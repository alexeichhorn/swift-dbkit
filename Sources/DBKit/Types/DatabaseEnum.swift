import NIOCore
import PostgresNIO

/// A Swift enum stored as a PostgreSQL enum type. Raw values are the database labels.
///
/// ```swift
/// enum TaskState: String, DatabaseEnum {
///     static let typeName = "task_state"
///     case pendingReview = "pending_review"
///     case inProgress = "in_progress"
/// }
/// ```
///
/// When every label is the snake_case case name, as here, ``DatabaseEnum(_:)`` generates the conformance.
public protocol DatabaseEnum: SQLValue, RawRepresentable where RawValue == String {
    /// The PostgreSQL enum type name, optionally schema-qualified.
    static var typeName: String { get }
}

extension DatabaseEnum {
    public static var sqlTypeName: String { typeName }
    public static var needsPlaceholderCast: Bool { true }
    // The OID of a user-defined enum is unknown; the placeholder cast tells PostgreSQL the type.
    public static var psqlType: PostgresDataType { PostgresDataType(0) }
    public static var psqlFormat: PostgresFormat { .binary }

    public func encode<JSONEncoder: PostgresJSONEncoder>(into byteBuffer: inout ByteBuffer, context: PostgresEncodingContext<JSONEncoder>) {
        byteBuffer.writeString(rawValue)
    }

    public init<JSONDecoder: PostgresJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: PostgresDataType,
        format: PostgresFormat,
        context: PostgresDecodingContext<JSONDecoder>
    ) throws {
        guard let label = buffer.readString(length: buffer.readableBytes), let value = Self(rawValue: label) else {
            throw PostgresDecodingError.Code.failure
        }
        self = value
    }
}

/// Conforms a plain enum to ``DatabaseEnum`` for the PostgreSQL enum type `typeName`. The label of each case is its
/// snake_case name, like the column names of `@Model`.
///
/// ```swift
/// @DatabaseEnum("task_state")
/// enum TaskState { case pendingReview, inProgress }     // labels: pending_review, in_progress
/// ```
@attached(extension, conformances: DatabaseEnum, names: named(typeName), named(rawValue), named(init))
public macro DatabaseEnum(_ typeName: String) = #externalMacro(module: "DBKitMacros", type: "DatabaseEnumMacro")
