import DBKit

/// The binds of `rendered` as rust-dbkit's `Value` lists them: an enum as `<type name>:<label>`, any other value as its
/// description.
func bindValues(_ rendered: RenderedSQL) -> [String] {
    rendered.binds.map { bind in
        guard let value = bind.value as? any DatabaseEnum else { return bind.description }
        return "\(type(of: value).typeName):\(value.rawValue)"
    }
}
