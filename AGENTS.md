# AGENTS.md - Project Documentation

## 1. Project Overview
`scala-hints.nvim` is a Neovim plugin designed to provide opinionated diagnostics and quickfix code actions for ZIO-based Scala code. It leverages Treesitter for pattern matching and Metals LSP for type information, aiming to improve code quality by identifying common ZIO code smells and suggesting idiomatic replacements.

The project is currently in a "sandbox" state, serving as a learning project for Neovim plugin development and ZIO code optimization.

## 2. Technical Architecture
The plugin follows a modular architecture: `init.lua` registers Metals-gated autocommands and wraps the LSP code-action handler so both diagnostics and actions share the same query engine and feed Neovim's native APIs.

### ASCII Architecture Diagram
```text
+-------------------------------------------------------+
|                    Neovim (Lua)                       |
+-------------------------------------------------------+
          |                                 |
          v                                 v
+-------------------------+       +------------------------+
| diagnostics autocommand |       | LSP code-action wrapper |
+-------------------------+       +------------------------+
          |                                 |
          v                                 v
+-------------------------+       +------------------------+
|    diagnostics.lua      |       |      actions.lua       |
+-------------------------+       +------------------------+
          \                                 /
           +--------------+----------------+
                          |
                     [query.run_query]
                          |
             +------------+------------+
             |                         |
   vim.diagnostic.set(...)    vim.lsp.handlers['textDocument/codeAction']
```

### Dependency Graph
- `nvim-lua/plenary.nvim`: Async utilities and general helpers.
- `nvim-treesitter/nvim-treesitter`: AST parsing and query execution.
- `scalameta/nvim-metals`: Type information via LSP.

## 3. File Structure & Purpose
The codebase is organized into six primary Lua modules:

| Module | Purpose |
| :--- | :--- |
| `init.lua` | Entry point; registers the diagnostic namespace, Metals-gated autocommands, and the code-action wrapper that injects scala-hints replacements into the native handler. |
| `diagnostics.lua` | Orchestrates diagnostic collection by running Treesitter queries. |
| `actions.lua` | Resolves available code actions for a given range. |
| `query.lua` | Contains all Treesitter query definitions and their respective handlers. |
| `utils.lua` | Shared utilities for LSP interaction, async handling, and node manipulation. |
| `constants.lua` | Project-wide constants (e.g., source name, language). |

## 4. Query Handler Flow
The core logic resides in the interaction between `diagnostics`/`actions` and `query.lua`.

1. **Trigger**: The `User MetalsReady` / `MetalsInitialized` autocommands ensure the diagnostic autocommand and LSP code-action wrapper are registered once Metals is ready.
2. **Preparation**: `init.lua` gates execution on Metals readiness per buffer, resetting the namespace and collecting active clients before running the queries.
3. **Execution**: `diagnostics.collect_diagnostics` or `actions.resolve_actions` iterates over the query list for the requested range or file scope.
4. **Matching**: `query.run_query` executes the Treesitter query against the buffer's AST.
5. **Handling**: For each match, the specific handler in `query.lua` is invoked.
6. **Verification**: LSP-dependent handlers use `semantic.hover_predicate` to verify types via Metals hover.
7. **Result**: Diagnostics feed `vim.diagnostic.set()` while code-action payloads flow through the wrapped `vim.lsp.handlers['textDocument/codeAction']`.

### ASCII Query Handler Diagram
```text
[diagnostics autocommand]          [LSP code-action wrapper]
             |                                |
             v                                v
     [diagnostics.lua]                [actions.lua]
             |                                |
             +---------------+----------------+
                             |
                     [query.run_query]
                             |
            +----------------+----------------+
            |                                 |
vim.diagnostic.set(...)       vim.lsp.handlers['textDocument/codeAction']
```


## 5. Pattern Catalog & IntelliJ Parity

### 5.1 Core Implemented Patterns
The following 35 patterns are fully implemented in [lua/scala-hints/libs/zio/queries.lua](lua/scala-hints/libs/zio/queries.lua):

| Pattern Name | Detection Summary | Replacement | IntelliJ | Status |
| :--- | :--- | :--- | :--- | :--- |
| `succeed_unit` | `ZIO.succeed(())` | `ZIO.unit` | ✓ | ✅ |
| `zio_die` | `ZIO.fail(ex).orDie` | `ZIO.die(ex)` | ✓ | ✅ |
| `map_unit` | `.map(_ => ...)` (any param) | `.unit` | ✓ | ✅ |
| `as_unit` | `.as(())` | `.unit` | ✓ | ✅ |
| `zip_right_unit` | `*> ZIO.unit` | `.unit` | ✓ | ✅ |
| `zip_right_value` | `*> ZIO.succeed(v)` | `.as(v)` | ✓ | ✅ |
| `zip_right_operator` | `.zipRight(v)` | `*> v` | ✓ | ✅ |
| `zip_left_value` | `.tap(...) not used` | `.zipLeft` | ✓ | ✅ |
| `flat_map_value` | `.flatMap(_ => v)` | `.zipRight` | ✓ | ✅ |
| `map_value` | `.map(_ => v)` | `.as(v)` | ✓ | ✅ |
| `catch_all_unit` | `.catchAll(_ => ZIO.unit)` | `.ignore` | ✓ | ✅ |
| `zio_foreach` | `ZIO.collectAll(coll.map(f))` | `ZIO.foreach` | ✓ | ✅ |
| `foreach_par_n` | `ZIO.foreachPar(coll)(f)` | `ZIO.foreachParN(n)(coll)(f)` | ✓ | ✅ |
| `fold_cause_ignore` | `.foldCause(_ => (), _ => ())` | `.ignore` | ✓ | ✅ |
| `or_else_fail` | `.mapError(_ => v)` | `.orElseFail(v)` | ✓ | ✅ |
| `or_else_fail2` | `.orElse(ZIO.fail(v))` | `.orElseFail(v)` | ✓ | ✅ |
| `or_else_fail3` | `.flatMapError(_ => ZIO.succeed(v))` | `.orElseFail(v)` | ✓ | ✅ |
| `zio_type` | `ZIO[Any, Nothing, A]` | `UIO[A]` or other aliases | ✓ | ✅ |
| `zlayer_type` | `ZLayer[Any, Nothing, A]` | `ULayer[A]` or other aliases | ✓ | ✅ |
| `zio_none` | `ZIO.succeed(None)` etc | `ZIO.none` | ✓ | ✅ |
| `zio_some` | `ZIO.succeed(Some(v))` etc | `ZIO.some(v)` | ✓ | ✅ |
| `zio_either` | `ZIO.succeed(Left/Right(v))` | `ZIO.left/right(v)` | ✓ | ✅ |
| `delay` | `ZIO.sleep(d) *> effect` | `effect.delay(d)` | ✓ | ✅ |
| `to_layer` | `ZLayer.fromEffect(eff)` | `eff.toLayer` | ✓ | ✅ |
| `provide_layer` | `layer.build.use(effect.provide)` | `effect.provideLayer(layer)` | ✓ | ✅ |
| `zio_service` | `ZIO.access(identity)` | `ZIO.service[A]` | ✓ | ✅ |
| `tap` | `effect.map(v => { sideEffect(v); v })` | `.tap(...)` | ✓ | ✅ |
| `tap_error` | `effect.mapError(e => { sideEffect(e); e })` | `.tapError(...)` | ✓ | ✅ |
| `tap_both` | `map/mapError` side-effects | `.tapBoth(...)` | ✓ | ✅ |
| `when` | `if (cond) eff else ZIO.unit` | `eff.when(cond)` | ✓ | ✅ |
| `unless` | `if (!cond) eff else ZIO.unit` | `eff.unless(cond)` | ✓ | ✅ |
| `exit_code_map` | `.map(_ => ExitCode.success)` | `.exitCode` | ✓ | ✅ |
| `exit_code_as` | `.as(ExitCode.success)` | `.exitCode` | ✓ | ✅ |
| `exit_code_fold` | `.fold(...ExitCode...)` | `.exitCode` | ✓ | ✅ |

### 5.2 Placeholder Patterns (Stub Implementations)
All placeholder patterns are now implemented.

### 5.3 Missing Patterns (IntelliJ Parity Gaps)
The following patterns from the IntelliJ ZIO plugin are not yet implemented:

| Pattern | Detection | Replacement | Complexity | Status |
| :--- | :--- | :--- | :--- | :--- |
| Type Modes | `CanFail`, `NeedsEnv`, contravariance | Mode-specific suggestions | High | ⭕ |
| Advanced | Wrapping `Option/Future/Try`, yield in for | Type-specific wrapping | High | ⭕ |

## 6. Technical Details
- **Treesitter Query Syntax**: Uses S-expressions for AST matching. Handlers often use `#eq?` and `#any-of?` predicates.
- **Async Handling**: Utilizes `plenary.async` for non-blocking query execution; LSP hover checks run through `semantic.hover_predicate`.
- **Metals Readiness**: The plugin waits for Metals to emit the `User MetalsReady` / `MetalsInitialized` events before registering diagnostics/code actions.
- **Timeouts**:
    - Diagnostics collection: 30 seconds.
    - Metals readiness check: 10 seconds.
    - Code action resolution: 10 seconds.
- **Hover Retries**: `semantic.hover_predicate` retries hover with backoff (default 400/1000/2000 ms) and logs final misses.
- **Setup Configuration**: `setup({ hover = { timeouts_ms = {...}, log_misses = true } })` controls hover retries and logging.
- **Type Checking**: Hover results are matched against `is_zio_type` predicates.

## 7. Current Issues & Limitations
- **Metals Initialization**: Reliably waiting for Metals to be fully ready (including indexing) is still a challenge.
- **Diagnostics Refresh**: Diagnostics sometimes fail to rebuild after an "undo" operation or certain code actions.
- **Whitespace Sensitivity**: Some Treesitter queries are sensitive to specific formatting (e.g., newlines between `ZIO` and `.unit`).
- **No Alias Support**: Patterns only match literal names (e.g., `ZIO`); they do not recognize type aliases or renamed imports.
- **Partial Caching**: Hover results are cached per buffer tick, but diagnostics still re-run all queries.
- **Inconsistent Type Checking**: Not all patterns currently verify the underlying type via Metals, leading to potential false positives on non-ZIO code.
- **Reliability**: Hover timeouts can still cause missed hints when Metals is under heavy load, even with retries.
- **Tests**: Automated test suites exist for the query engine, registry, pure queries, LSP queries, and integration flows.

## 8. TODOs from User
The following items are tracked for future implementation (from `TODO.md`):
- **Reliable Metals Wait**: Improve the logic for waiting until Metals indexing is complete.
- **Undo Trigger**: Fix diagnostic refresh after undo.
- **New Hints**:
    - `.when` / `.unless`
    - `.exitCode` (implementing placeholders)
    - `.delay`
    - `.foreach` / `.foreachPar`
    - `.tap` / `.tapError` / `.tapBoth`
- **Inspiration**: Reference the [IntelliJ ZIO plugin](https://plugins.jetbrains.com/plugin/13820-zio-for-intellij/features) for additional feature ideas.

## 9. Future Enhancement Ideas
| Category | Immediate | Medium-Term | Long-Term | Documentation/UX |
| :--- | :--- | :--- | :--- | :--- |
| **Feature** | Implement `exitCode` | Support for `ZPure` | Type mode hints | Pattern Catalog UI |
| **Stability** | Fix Undo refresh | Improve Metals polling | Add caching layer | Troubleshooting guide |
| **Quality** | Add basic unit tests | Expand type checking | Support type aliases | Contributor guide |
| **Performance** | Optimize TS queries | Async query batching | Incremental parsing | Metrics dashboard |

## 10. Pattern Addition Guide
To add a new pattern to the plugin:

1. **Identify the Pattern**: Use `:InspectTree` in Neovim to see the AST for the code you want to match.
2. **Define the Query**: Add a new entry to the `queries` table in `lua/scala-hints/query.lua`.
    - Write the Treesitter S-expression.
    - Implement the `handler` function to extract ranges and suggest replacements.
  - (Optional) Set `diagnostic_severity` to `INFO`, `WARN`, `ERROR`, `HINT`, or `OFF` to control per-query diagnostics.
3. **Register the Query**: Add the query name to the `query_names` list in both `lua/scala-hints/diagnostics.lua` and `lua/scala-hints/actions.lua`.
4. **Implement Type Verification (Optional)**: Use `semantic.hover_predicate` if the pattern should only apply to specific types (e.g., `ZIO`).
5. **Manual Verification**: Open a Scala file and verify that the diagnostic appears and the code action works as expected.
6. **Update Documentation**: Add the new pattern to the Pattern Catalog in `AGENTS.md`.

## 11. Metrics & Statistics
- **Total Lines of Code**: 1557
- **Core Logic (`query.lua`)**: 1135 lines
- **Number of Modules**: 6
- **Total Patterns**: 24 (20 implemented, 4 placeholders)
- **Test Coverage**: Present (see `tests/` for query engine, registry, and ZIO integration/LSP specs).

## 12. Known Limitations
- Relies on Metals and Neovim APIs; changes to either stack may require adjustments.
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
The plugin uses `vim.lsp.buf_request` with the `textDocument/hover` method via `semantic.hover_predicate`. Hover requests are retried with backoff, and the response is parsed to find type information matched against predicates defined in `query.lua`.

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
- [ ] Monitor Metals and Neovim LSP/diagnostic APIs for breaking changes.
- [ ] Update Pattern Catalog when new handlers are added.
