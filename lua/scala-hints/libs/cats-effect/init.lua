--- Cats-Effect library module for scala-hints
---
--- Provides Treesitter query definitions for detecting Cats-Effect code patterns
--- and suggesting idiomatic replacements.

local queries = require('scala-hints.libs.cats-effect.queries')

return {
  name = 'cats-effect',
  queries = queries,
}
