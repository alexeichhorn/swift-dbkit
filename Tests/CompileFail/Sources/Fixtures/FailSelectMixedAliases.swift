import DBKit

// One `select` takes either aliased or unaliased expressions, never both.

private func selectTakesAllAliasedOrAllUnaliasedExpressions() {
    _ = UserModel.query().select(UserModel.id, UserModel.name.as("name"))  // error: conform to 'SQLExpression'
    _ = UserModel.query().select(UserModel.id.as("id"), UserModel.name)  // error: conform to 'SQLExpression'
}
