--- ZIO library module for scala-hints
---
--- Provides Treesitter query definitions for detecting ZIO code patterns
--- and suggesting idiomatic replacements.

local queries = require('scala-hints.libs.zio.queries')

return {
  name = 'zio',
  queries = queries,
}
