--- Cats (tagless-final) library module for scala-hints
---
--- Provides Treesitter query definitions for detecting Cats typeclass-driven
--- patterns on F[_] when explicit evidence is available.

local queries = require('scala-hints.libs.cats.queries')

return {
  name = 'cats',
  queries = queries,
}
