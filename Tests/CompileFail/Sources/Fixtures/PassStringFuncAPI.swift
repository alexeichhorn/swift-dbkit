import DBKit

// rust-dbkit's `pass_string_func_api.rs`. The annotations fail to compile when a result type changes. A nullable
// argument of any kind makes the result nullable, except for `concat`, the values of `concatWithSeparator` and the
// delimiter of `split`.

private typealias T = TextSampleModel

private func trimmingKeepsTheNullabilityOfEveryArgument() {
    let _: Expr<String> = SQL.lower(T.title)
    let _: Expr<String?> = SQL.lower(T.body)
    let _: Expr<String> = SQL.trimChars(T.title, "xy")
    let _: Expr<String> = SQL.trimChars(T.title, T.pattern)
    let _: Expr<String?> = SQL.trimChars(T.body, "xy")
    let _: Expr<String?> = SQL.trimChars(T.title, T.body)
    let _: Expr<String?> = SQL.trimChars(T.body, T.body)
    let _: Expr<String> = SQL.trimStart(T.title)
    let _: Expr<String?> = SQL.trimStart(T.body)
    let _: Expr<String> = SQL.trimStartChars(T.title, "xy")
    let _: Expr<String> = SQL.trimStartChars(T.title, T.pattern)
    let _: Expr<String?> = SQL.trimStartChars(T.body, "xy")
    let _: Expr<String?> = SQL.trimStartChars(T.title, T.body)
    let _: Expr<String?> = SQL.trimStartChars(T.body, T.body)
    let _: Expr<String> = SQL.trimEnd(T.title)
    let _: Expr<String?> = SQL.trimEnd(T.body)
    let _: Expr<String> = SQL.trimEndChars(T.title, "xy")
    let _: Expr<String> = SQL.trimEndChars(T.title, T.pattern)
    let _: Expr<String?> = SQL.trimEndChars(T.body, "xy")
    let _: Expr<String?> = SQL.trimEndChars(T.title, T.body)
    let _: Expr<String?> = SQL.trimEndChars(T.body, T.body)
}

// Counts take an `Int32` value or expression.
private func extractionAndSizingKeepTheNullabilityOfEveryArgument() {
    let _: Expr<String> = SQL.left(T.title, 2)
    let _: Expr<String?> = SQL.left(T.body, 2)
    let _: Expr<String?> = SQL.left(T.title, T.optionalWidth)
    let _: Expr<String?> = SQL.left(T.body, T.optionalWidth)
    let _: Expr<String> = SQL.right(T.title, 2)
    let _: Expr<String?> = SQL.right(T.body, 2)
    let _: Expr<String?> = SQL.right(T.title, T.optionalWidth)
    let _: Expr<String> = SQL.substring(T.title, 2, 3)
    let _: Expr<String?> = SQL.substring(T.body, 2, 3)
    let _: Expr<String?> = SQL.substring(T.title, T.optionalWidth, T.width)
    let _: Expr<String?> = SQL.substring(T.title, T.width, T.optionalWidth)
    let _: Expr<String?> = SQL.substring(T.body, T.optionalWidth, T.optionalWidth)
    let _: Expr<String> = SQL.repeat(T.title, SQL.charLength(T.title))
    let _: Expr<String?> = SQL.repeat(T.body, 2)
    let _: Expr<String?> = SQL.repeat(T.title, T.optionalWidth)
    let _: Expr<String> = SQL.padStart(T.title, SQL.charLength(T.title), "xy")
    let _: Expr<String> = SQL.padStart(T.title, T.width, T.pattern)
    let _: Expr<String?> = SQL.padStart(T.body, 8, "xy")
    let _: Expr<String?> = SQL.padStart(T.title, T.optionalWidth, "xy")
    let _: Expr<String?> = SQL.padStart(T.title, 8, T.body)
    let _: Expr<String?> = SQL.padStart(T.body, 8, T.body)
    let _: Expr<String?> = SQL.padStart(T.title, T.optionalWidth, T.body)
    let _: Expr<String?> = SQL.padStart(T.body, T.optionalWidth, T.body)
    let _: Expr<String> = SQL.padEnd(T.title, 8, "xy")
    let _: Expr<String> = SQL.padEnd(T.title, T.width, T.pattern)
    let _: Expr<String?> = SQL.padEnd(T.body, 8, "xy")
    let _: Expr<String?> = SQL.padEnd(T.body, T.optionalWidth, "xy")
    let _: Expr<String?> = SQL.padEnd(T.title, 8, T.body)
    let _: Expr<String?> = SQL.padEnd(T.body, 8, T.body)
    let _: Expr<String?> = SQL.padEnd(T.title, T.optionalWidth, T.body)
    let _: Expr<String?> = SQL.padEnd(T.body, T.optionalWidth, T.body)
    let _: Expr<String> = SQL.left(T.title, SQL.coalesce(T.optionalWidth, 0))
}

private func lengthsAndSearchesKeepTheNullabilityOfEveryArgument() {
    let _: Expr<Int32> = SQL.byteLength(T.title)
    let _: Expr<Int32?> = SQL.byteLength(T.body)
    let _: Expr<Int32> = SQL.bitLength("UTF-8")
    let _: Expr<Int32?> = SQL.bitLength(SQL.trim(T.body))
    let _: Expr<Int32> = SQL.position(T.title, "needle")
    let _: Expr<Int32?> = SQL.position(T.body, T.title)
    let _: Expr<Int32?> = SQL.position(T.title, T.body)
    let _: Expr<Int32?> = SQL.position(T.body, T.body)
    let _: Expr<Bool> = SQL.startsWith(T.title, "prefix")
    let _: Expr<Bool?> = SQL.startsWith(T.body, T.title)
    let _: Expr<Bool?> = SQL.startsWith(T.title, T.body)
    let _: Expr<Bool?> = SQL.startsWith(T.body, T.body)
}

private func transformationsKeepTheNullabilityOfEveryArgument() {
    let _: Expr<String> = SQL.titleCase(T.title)
    let _: Expr<String?> = SQL.titleCase(T.body)
    let _: Expr<String> = SQL.reverse(T.title)
    let _: Expr<String?> = SQL.reverse(T.body)
    let _: Expr<String> = SQL.replace(T.title, "from", "to")
    let _: Expr<String?> = SQL.replace(T.body, "from", "to")
    let _: Expr<String?> = SQL.replace(T.title, T.body, "to")
    let _: Expr<String?> = SQL.replace(T.title, "from", T.body)
    let _: Expr<String> = SQL.replaceRange(T.title, "replacement", 1, 2)
    let _: Expr<String?> = SQL.replaceRange(T.body, "replacement", 1, 2)
    let _: Expr<String?> = SQL.replaceRange(T.title, T.body, 1, 2)
    let _: Expr<String?> = SQL.replaceRange(T.title, "replacement", T.optionalWidth, T.width)
    let _: Expr<String?> = SQL.replaceRange(T.title, "replacement", T.width, T.optionalWidth)
    let _: Expr<String> = SQL.translateChars(T.title, "from", "to")
    let _: Expr<String?> = SQL.translateChars(T.body, "from", "to")
    let _: Expr<String?> = SQL.translateChars(T.title, T.body, "to")
    let _: Expr<String?> = SQL.translateChars(T.title, "from", T.body)
}

// rust-dbkit passes the values to concatenate as an array; here they are arguments.
private func compositionAndSplitting() {
    let _: Expr<String> = SQL.concat(T.title, SQL.lower("SUFFIX"))
    let _: Expr<String> = SQL.concat(T.body, SQL.trim(T.body))
    let _: Expr<String> = SQL.concat(T.title, T.body)
    let _: Expr<String> = SQL.concat(T.body, "SUFFIX")
    let _: Expr<String> = SQL.concatWithSeparator("::", T.title, SQL.lower("SUFFIX"))
    let _: Expr<String> = SQL.concatWithSeparator("::", T.title, T.body)
    let _: Expr<String?> = SQL.concatWithSeparator(T.body, T.body, SQL.trim(T.body))
    let _: Expr<String> = SQL.concat()
    let _: Expr<String> = SQL.concatWithSeparator("")
    let _: Expr<[String]> = SQL.split(T.title, "::")
    let _: Expr<[String]?> = SQL.split(T.body, "::")
    let _: Expr<[String]> = SQL.split(T.title, T.body)
    let _: Expr<String> = SQL.splitPart(T.title, "::", 1)
    let _: Expr<String?> = SQL.splitPart(T.body, "::", 1)
    let _: Expr<String?> = SQL.splitPart(T.title, T.body, 1)
    let _: Expr<String?> = SQL.splitPart(T.title, "::", T.optionalWidth)

    let nullableWidthExpression = T.optionalWidth + T.width
    let _: Expr<String?> = SQL.left(T.title, nullableWidthExpression)
    let _: Expr<String?> = SQL.splitPart(T.title, "::", nullableWidthExpression)
}

private func nestedFunctionsComposeInQueries() {
    let normalizedTitle: Expr<String> = SQL.lower(SQL.trim(SQL.trimStartChars(SQL.trim(T.title), "@")))
    let normalizedBody: Expr<String?> = SQL.lower(SQL.trimEnd(SQL.trimStart(T.body)))
    let customTrimmed: Expr<String> = SQL.trimChars(T.title, SQL.lower("XY"))
    let normalizedBodyLength: Expr<Int32?> = SQL.charLength(normalizedBody)
    let nestedSizing: Expr<String> = SQL.padEnd(
        SQL.substring(SQL.lower(SQL.trim(T.title)), SQL.charLength("x"), SQL.charLength(T.title)),
        SQL.charLength(T.title),
        SQL.lower("XY")
    )
    let repeatedSuffix: Expr<String?> = SQL.repeat(SQL.right(T.body, SQL.charLength(T.title)), 2)
    let nestedPosition: Expr<Int32?> = SQL.position(normalizedBody, SQL.lower("needle"))
    let nestedPrefix: Expr<Bool?> = SQL.startsWith(normalizedBody, SQL.lower(T.title))
    let transformedTitle: Expr<String> = SQL.reverse(
        SQL.translateChars(
            SQL.replace(SQL.titleCase(T.title), SQL.lower("FROM"), SQL.upper("to")),
            SQL.lower("ABC"),
            SQL.upper("xyz")
        ))
    let transformedBody: Expr<String?> = SQL.replaceRange(
        SQL.titleCase(T.body), SQL.reverse(T.title), SQL.charLength("x"), SQL.charLength(T.title))
    let nestedPart: Expr<String> = SQL.splitPart(SQL.concat(normalizedTitle, SQL.lower("SUFFIX")), "::", SQL.charLength(T.title))
    let nestedParts: Expr<[String]?> = SQL.split(normalizedBody, SQL.lower("::"))

    // Separate statements keep the type checker fast.
    var query = T.query()
        .select(
            normalizedTitle.as("normalized_title"),
            normalizedBody.as("normalized_body"),
            customTrimmed.as("custom_trimmed"),
            normalizedBodyLength.as("normalized_body_len"),
            nestedSizing.as("nested_sizing"),
            repeatedSuffix.as("repeated_suffix"),
            SQL.byteLength(normalizedBody).as("normalized_body_bytes"),
            SQL.bitLength(normalizedBody).as("normalized_body_bits"),
            nestedPosition.as("nested_position"),
            nestedPrefix.as("nested_prefix"),
            transformedTitle.as("transformed_title"),
            transformedBody.as("transformed_body"),
            nestedPart.as("nested_part"),
            nestedParts.as("nested_parts")
        )
    query = query.filter(T.body.isNotNull)
    query = query.filter(normalizedTitle == "alice")
    query = query.filter(SQL.startsWith(T.title, "prefix") == true)
    query = query.filter(SQL.position(T.title, "needle") > 0)
    query = query.filter(SQL.trimEndChars(T.body, "!?") != "")
    query = query.filter(SQL.replace(T.title, "old", "new") == "expected")
    query = query.filter(SQL.left(T.title, T.optionalWidth) == "prefix")
    query = query.filter(SQL.splitPart(T.title, "::", 1) == "prefix")
    query = query.orderBy(SQL.repeat(T.title, T.optionalWidth).asc)
    query = query.orderBy(normalizedBody.asc, normalizedBodyLength.asc, nestedPosition.asc, transformedTitle.asc, nestedPart.asc)
    _ = query
}
