--- Monix library module for scala-hints
---
--- Provides Treesitter query definitions for detecting Monix (Task and
--- Observable) code patterns and suggesting idiomatic replacements.

local queries = require('scala-hints.libs.monix.queries')

return {
  name = 'monix',
  queries = queries,
}