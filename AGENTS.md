# AGENTS.md - Project Documentation

## 1. Project Overview
`scala-hints.nvim` is a Neovim plugin designed to provide opinionated diagnostics and quickfix code actions for ZIO-based Scala code. It leverages Treesitter for pattern matching and Metals LSP for type information, aiming to improve code quality by identifying common ZIO code smells and suggesting idiomatic replacements.

The project is currently in a "sandbox" state, serving as a learning project for Neovim plugin development and ZIO code optimization.

## 2. Technical Architecture
The plugin follows a modular architecture, integrating with `none-ls` (formerly `null-ls`) to provide diagnostics and code actions.

### ASCII Architecture Diagram
```text
+-------------------------------------------------------+
|                    Neovim (Lua)                       |
+-------------------------------------------------------+
           |                                 ^
           v                                 |
+-----------------------+         +---------------------+
|       none-ls         | <-----> |  scala-hints.nvim   |
+-----------------------+         +---------------------+
           |                         |         |
           |                         v         v
           |               +------------+   +------------+
           |               | Treesitter |   | Metals LSP |
           |               +------------+   +------------+
           |                         |         |
           +-------------------------+---------+
```

### Dependency Graph
- `nvim-lua/plenary.nvim`: Async utilities and general helpers.
- `nvim-treesitter/nvim-treesitter`: AST parsing and query execution.
- `scalameta/nvim-metals`: Type information via LSP.
- `nvimtools/none-ls.nvim`: Integration for diagnostics and code actions.

## 3. File Structure & Purpose
The codebase is organized into six primary Lua modules:

| Module | Purpose |
| :--- | :--- |
| `init.lua` | Entry point; registers diagnostics and code action sources with `none-ls`. |
| `diagnostics.lua` | Orchestrates diagnostic collection by running Treesitter queries. |
| `actions.lua` | Resolves available code actions for a given range. |
| `query.lua` | Contains all Treesitter query definitions and their respective handlers. |
| `utils.lua` | Shared utilities for LSP interaction, async handling, and node manipulation. |
| `constants.lua` | Project-wide constants (e.g., source name, language). |

## 4. Query Handler Flow
The core logic resides in the interaction between `diagnostics`/`actions` and `query.lua`.

1. **Trigger**: `none-ls` calls the registered generator.
2. **Preparation**: `init.lua` waits for Metals to signal readiness (via the `User MetalsReady` / `MetalsInitialized` autocommands) before registering the generators.
3. **Execution**: `diagnostics.collect_diagnostics` or `actions.resolve_actions` iterates over a list of query names.
4. **Matching**: `query.run_query` executes the Treesitter query against the buffer's AST.
5. **Handling**: For each match, the specific `handler` in `query.lua` is invoked.
6. **Verification**: Handlers may use `utils.hover_node_and_match` to verify types via Metals LSP.
7. **Result**: Diagnostics or code actions are returned to `none-ls`.

### ASCII Query Handler Diagram
```text
[none-ls] -> [init.lua] -> [diagnostics.lua]
                                 |
                                 v
                          [query.run_query]
                                 |
                +----------------+----------------+
                |                                 |
        [Treesitter Match]                [Handler Invocation]
                |                                 |
                v                                 v
        (AST Nodes)                      [utils.hover_node] -> [Metals LSP]
                                                 |
                                                 v
                                         (Diagnostic/Action)
```

## 5. Pattern Catalog
The following table lists the patterns currently defined in `query.lua`.

| Pattern Name | Detection Summary | Suggested Replacement | Status |
| :--- | :--- | :--- | :--- |
| `succeed_unit` | `ZIO.succeed(())` | `ZIO.unit` | Implemented |
| `fail_exception_or_die` | `ZIO.fail(ex).orDie` | `ZIO.die(ex)` | Implemented |
| `map_unit` | `.map(_ => ())` | `.unit` | Implemented |
| `as_unit` | `.as(())` | `.unit` | Implemented |
| `zip_right_unit` | `*> ZIO.unit` | `.unit` | Implemented |
| `zip_right_value` | `*> ZIO.succeed(v)` | `.as(v)` | Implemented |
| `zip_left_value` | `.tap(_ => v)` | `<* v` or `.zipLeft(v)` | Implemented |
| `flat_map_value` | `.flatMap(_ => v)` | `*> v` or `.zipRight(v)` | Implemented |
| `map_value` | `.map(_ => v)` | `.as(v)` | Implemented |
| `catch_all_unit` | `.catchAll(_ => ZIO.unit)` | `.ignore` | Implemented |
| `zio_foreach` | `ZIO.collectAll(coll.map(f))` | `ZIO.foreach(coll)(f)` | Implemented |
| `fold_cause_ignore` | `.foldCause(_ => (), _ => ())` | `.ignore` | Implemented |
| `or_else_fail` | `.mapError(_ => v)` | `.orElseFail(v)` | Implemented |
| `or_else_fail2` | `.orElse(ZIO.fail(v))` | `.orElseFail(v)` | Implemented |
| `or_else_fail3` | `.flatMapError(_ => ZIO.succeed(v))` | `.orElseFail(v)` | Implemented |
| `zio_type` | `ZIO[Any, Nothing, A]` | `UIO[A]` (and others) | Implemented |
| `zlayer_type` | `ZLayer[Any, Nothing, A]` | `ULayer[A]` (and others) | Implemented |
| `zio_none` | `ZIO.succeed(None)` | `ZIO.none` | Implemented |
| `zio_some` | `ZIO.succeed(Some(v))` | `ZIO.some(v)` | Implemented |
| `zio_either` | `ZIO.succeed(Left(v))` | `ZIO.left(v)` | Implemented |
| `exit_code` | `.map(_ => ExitCode.success)` | `.exitCode` | **Placeholder** |
| `exit_code2` | `.as(ExitCode.success)` | `.exitCode` | **Placeholder** |
| `exit_code3` | `.fold(...)` | `.exitCode` | **Placeholder** |
| `zio_die` | `ZIO.fail(new Exception).orDie` | `ZIO.die(...)` | **Placeholder** |

## 6. Technical Details
- **Treesitter Query Syntax**: Uses S-expressions for AST matching. Handlers often use `#eq?` and `#any-of?` predicates.
- **Async Handling**: Utilizes `plenary.async` for non-blocking LSP requests and query execution.
- **Metals Readiness**: The plugin waits for Metals to emit the `User MetalsReady` / `MetalsInitialized` events before registering diagnostics/code actions.
- **Timeouts**:
    - Diagnostics collection: 30 seconds.
    - Metals readiness check: 10 seconds.
    - Code action resolution: 10 seconds.
- **Type Checking**: `utils.hover_node_and_match` performs a `textDocument/hover` request to Metals and matches the returned type string against a predicate (e.g., checking for "ZIO").

## 7. Current Issues & Limitations
- **Metals Initialization**: Reliably waiting for Metals to be fully ready (including indexing) is still a challenge.
- **Diagnostics Refresh**: Diagnostics sometimes fail to rebuild after an "undo" operation or certain code actions.
- **Whitespace Sensitivity**: Some Treesitter queries are sensitive to specific formatting (e.g., newlines between `ZIO` and `.unit`).
- **No Alias Support**: Patterns only match literal names (e.g., `ZIO`); they do not recognize type aliases or renamed imports.
- **No Caching**: Every diagnostic request re-runs all queries, which may impact performance on very large files.
- **Inconsistent Type Checking**: Not all patterns currently verify the underlying type via Metals, leading to potential false positives on non-ZIO code.
- **Test Coverage**: There are currently **zero** automated tests.

## 8. TODOs from User
The following items are tracked for future implementation (from `TODO.md`):
- **Reliable Metals Wait**: Improve the logic for waiting until Metals indexing is complete.
- **Undo Trigger**: Fix diagnostic refresh after undo.
- **New Hints**:
    - `.bimap`
    - `.when` / `.unless`
    - `.exitCode` (implementing placeholders)
    - `.delay`
    - `.foreach` / `.foreachPar`
    - `.tap` / `.tapError` / `.tapBoth`
- **Missing Combinators**: Add a hint for forgotten `*>` (zipRight) usage.
- **Inspiration**: Reference the [IntelliJ ZIO plugin](https://plugins.jetbrains.com/plugin/13820-zio-for-intellij/features) for additional feature ideas.

## 9. Future Enhancement Ideas
| Category | Immediate | Medium-Term | Long-Term | Documentation/UX |
| :--- | :--- | :--- | :--- | :--- |
| **Feature** | Implement `exitCode` | Add `.bimap` support | Support for `ZPure` | Pattern Catalog UI |
| **Stability** | Fix Undo refresh | Improve Metals polling | Add caching layer | Troubleshooting guide |
| **Quality** | Add basic unit tests | Expand type checking | Support type aliases | Contributor guide |
| **Performance** | Optimize TS queries | Async query batching | Incremental parsing | Metrics dashboard |

## 10. Pattern Addition Guide
To add a new pattern to the plugin:

1. **Identify the Pattern**: Use `:InspectTree` in Neovim to see the AST for the code you want to match.
2. **Define the Query**: Add a new entry to the `queries` table in `lua/scala-hints/query.lua`.
    - Write the Treesitter S-expression.
    - Implement the `handler` function to extract ranges and suggest replacements.
3. **Register the Query**: Add the query name to the `query_names` list in both `lua/scala-hints/diagnostics.lua` and `lua/scala-hints/actions.lua`.
4. **Implement Type Verification (Optional)**: Use `utils.hover_node_and_match` if the pattern should only apply to specific types (e.g., `ZIO`).
5. **Manual Verification**: Open a Scala file and verify that the diagnostic appears and the code action works as expected.
6. **Update Documentation**: Add the new pattern to the Pattern Catalog in `AGENTS.md`.

## 11. Metrics & Statistics
- **Total Lines of Code**: 1557
- **Core Logic (`query.lua`)**: 1135 lines
- **Number of Modules**: 6
- **Total Patterns**: 24 (20 implemented, 4 placeholders)
- **Test Coverage**: 0%

## 12. Known Limitations
- Relies heavily on `none-ls`, which is in maintenance mode.
- Performance may degrade on files with thousands of lines due to lack of caching.
- Limited to Scala language and ZIO framework.

## 13. Appendix A: Treesitter Query Examples
Example of a simple match for `ZIO.succeed(())`:
```query
(call_expression
  function: (field_expression
    value: (_) @_1 (#eq? @_1 "ZIO")
    field: (identifier) @_2 (#eq? @_2 "succeed")
  )
  arguments: (arguments (unit)) @_3
)
```

## 14. Appendix B: LSP Interaction Details
The plugin uses `vim.lsp.buf_request` with the `textDocument/hover` method. The response is parsed to find type information, which is then matched against predicates defined in `query.lua`.

## 15. Appendix C: External References
- [ZIO Documentation](https://zio.dev/)
- [IntelliJ ZIO Plugin](https://github.com/zio/zio-intellij)
- [Treesitter Query Language](https://tree-sitter.github.io/tree-sitter/using-parsers#query-syntax)

## 16. Acknowledgments
- Inspired by the work of Igal Tabachnik on the IntelliJ ZIO plugin.
- Built using the Neovim Lua ecosystem.

## 17. Maintenance Checklist
- [ ] Verify Metals compatibility after Metals updates.
- [ ] Check for Treesitter grammar changes in `tree-sitter-scala`.
- [ ] Monitor `none-ls` for breaking changes.
- [ ] Update Pattern Catalog when new handlers are added.
