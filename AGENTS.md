# AGENTS.md - Project Documentation

## 1. Project Overview

`scala-hints.nvim` is a Neovim plugin that provides opinionated diagnostics and quickfix code actions for ZIO-based Scala code. It uses Treesitter for AST pattern matching, Metals LSP for type verification, and native Neovim diagnostics/code-action APIs.

## 2. Architecture

```text
  BufWritePost / BufEnter            vim.lsp.buf.code_action()
         |                                  |
         v                                  v
  diagnostics.lua                     actions.lua
         \                                /
          +------ query.run_query -------+
                        |
                handler(bufnr, matches)
                        |
           +------------+------------+
           |                         |
  vim.diagnostic.set()     LSP code-action response
```

**Dependencies**: `plenary.nvim` (async), `nvim-treesitter` (AST parsing), `nvim-metals` (type info via LSP).

### Modules

| Module | Purpose |
| :--- | :--- |
| `init.lua` | Entry point; registers namespace, Metals-gated autocommands, code-action wrapper |
| `diagnostics.lua` | Orchestrates diagnostic collection by running Treesitter queries |
| `actions.lua` | Resolves code actions for a given range |
| `query.lua` | Generic Treesitter query execution engine |
| `libs/zio/queries.lua` | All 35 ZIO query definitions and handlers |
| `libs/zio/init.lua` | ZIO query registry |
| `semantic.lua` | LSP hover verification, caching, and `hover_predicate` |
| `client.lua` | LSP client management |
| `utils.lua` | Async helpers, node inspection, Metals readiness polling |
| `logger.lua` | File-based logging |
| `constants.lua` | Shared metadata (namespace name, filetype) |

### Query Handler Flow

1. **Trigger**: `MetalsReady` / `MetalsInitialized` autocommands register the diagnostic autocommand and code-action wrapper.
2. **Execution**: `diagnostics.collect_diagnostics` or `actions.resolve_actions` iterates over queries.
3. **Matching**: `query.run_query` executes the Treesitter query against the buffer's AST.
4. **Handling**: Each match invokes the handler from `libs/zio/queries.lua`.
5. **Verification**: All handlers call `semantic.hover_predicate` to confirm ZIO/ZLayer types via Metals hover (with `fallback = true` so hints are still emitted when hover is unavailable).
6. **Result**: Diagnostics feed `vim.diagnostic.set()`; code actions flow through the wrapped LSP handler.

## 3. Pattern Catalog

35 patterns implemented in [libs/zio/queries.lua](lua/scala-hints/libs/zio/queries.lua):

| Pattern | Detection | Replacement |
| :--- | :--- | :--- |
| `succeed_unit` | `ZIO.succeed(())` | `ZIO.unit` |
| `zio_die` | `ZIO.fail(ex).orDie` | `ZIO.die(ex)` |
| `map_unit` | `.map(_ => ...)` | `.unit` |
| `as_unit` | `.as(())` | `.unit` |
| `zip_right_unit` | `*> ZIO.unit` | `.unit` |
| `zip_right_value` | `*> ZIO.succeed(v)` | `.as(v)` |
| `zip_right_operator` | `.zipRight(v)` | `*> v` |
| `zip_left_value` | `.tap(_ => v)` (unused param) | `.zipLeft(v)` |
| `flat_map_value` | `.flatMap(_ => v)` | `.zipRight(v)` |
| `map_value` | `.map(_ => v)` | `.as(v)` |
| `catch_all_unit` | `.catchAll(_ => ZIO.unit)` | `.ignore` |
| `zio_cond` | `ZIO.cond(cond, (), err)` | `ZIO.fail(err).unless(cond)` |
| `zio_foreach` | `ZIO.collectAll(coll.map(f))` | `ZIO.foreach(coll)(f)` |
| `foreach_par_n` | `ZIO.foreachPar(coll)(f)` | `ZIO.foreachParN(n)(coll)(f)` |
| `fold_cause_ignore` | `.foldCause(_ => (), _ => ())` | `.ignore` |
| `or_else_fail` | `.mapError(_ => v)` | `.orElseFail(v)` |
| `or_else_fail2` | `.orElse(ZIO.fail(v))` | `.orElseFail(v)` |
| `or_else_fail3` | `.flatMapError(_ => ZIO.succeed(v))` | `.orElseFail(v)` |
| `zio_type` | `ZIO[Any, Nothing, A]` etc. | `UIO[A]`, `Task[A]`, etc. |
| `zlayer_type` | `ZLayer[Any, Nothing, A]` etc. | `ULayer[A]`, `TaskLayer[A]`, etc. |
| `zio_none` | `ZIO.succeed(None)` | `ZIO.none` |
| `zio_some` | `ZIO.succeed(Some(v))` | `ZIO.some(v)` |
| `zio_either` | `ZIO.succeed(Left/Right(v))` | `ZIO.left/right(v)` |
| `delay` | `ZIO.sleep(d) *> effect` | `effect.delay(d)` |
| `to_layer` | `ZLayer.fromEffect(eff)` | `eff.toLayer` |
| `provide_layer` | `layer.build.use(effect.provide)` | `effect.provideLayer(layer)` |
| `zio_service` | `ZIO.access(identity)` | `ZIO.service[A]` |
| `tap` | `.map(v => { sideEffect(v); v })` | `.tap(sideEffect)` |
| `tap_error` | `.mapError(e => { sideEffect(e); e })` | `.tapError(sideEffect)` |
| `tap_both` | chained `map`/`mapError` side-effects | `.tapBoth(...)` |
| `when` | `if (cond) eff else ZIO.unit` | `eff.when(cond)` |
| `unless` | `if (!cond) eff else ZIO.unit` | `eff.unless(cond)` |
| `exit_code_map` | `.map(_ => ExitCode.success)` | `.exitCode` |
| `exit_code_as` | `.as(ExitCode.success)` | `.exitCode` |
| `exit_code_fold` | `.fold(...ExitCode...)` | `.exitCode` |

### Remaining IntelliJ Parity Gaps

| Pattern | Description | Complexity |
| :--- | :--- | :--- |
| Type Modes | `CanFail`, `NeedsEnv`, contravariance | High |
| Advanced | Wrapping `Option/Future/Try`, yield in for-comprehension | High |

## 4. Technical Details

- **Treesitter queries** use S-expressions with `#eq?` and `#any-of?` predicates.
- **Async**: All queries run via `plenary.async`; `semantic.hover_predicate` retries hover with configurable backoff (default 400/1000/2000 ms).
- **Metals readiness**: Waits for `MetalsReady` / `MetalsInitialized` autocommands before registering diagnostics.
- **Timeouts**: Diagnostics 30s, code actions 10s, Metals readiness 10s.
- **Hover caching**: Results cached per buffer tick to avoid redundant LSP calls.
- **Type checking**: Hover results matched against `is_zio_type` predicate (checks for `ZIO[`, `UIO[`, `IO[`, `Task[`, etc.) or `is_zlayer_type` (checks for `ZLayer[`, `ULayer[`, `TaskLayer[`, etc.).
- **Fallback**: All 35 handlers use `hover_predicate` with `fallback = true` — when Metals confirms "not ZIO" the hint is suppressed; when hover is unavailable, hints are emitted anyway.

## 5. Known Limitations

- Patterns match literal names only (`ZIO`); type aliases and renamed imports are not recognized.
- Some queries are whitespace-sensitive (e.g., `ZIO\n.unit` may not match).
- All handlers verify types via Metals when available; without Metals, hints are emitted optimistically (may cause false positives on non-ZIO code).
- Diagnostics may not refresh after undo operations.
- Performance may degrade on very large files due to lack of incremental parsing.

## 6. Adding a New Pattern

1. Use `:InspectTree` in Neovim to see the AST for the code you want to match.
2. Add a new entry to the queries table in `lua/scala-hints/libs/zio/queries.lua`:
   - Write the Treesitter S-expression query.
   - Implement the `handler` function to extract ranges and suggest replacements.
   - Optionally set `diagnostic_severity` (`HINT`/`INFO`/`WARN`/`ERROR`/`OFF`).
3. Register the query name in `lua/scala-hints/libs/zio/init.lua`.
4. Use `semantic.hover_predicate` with `{ fallback = true }` for type verification.
5. Add tests in `tests/zio/pure_queries_spec.lua` (mock hover with `H.mock_hover_predicate(true)`).
6. Update the pattern catalog above.

### Treesitter Query Example

```query
(call_expression
  function: (field_expression
    value: (_) @_1 (#eq? @_1 "ZIO")
    field: (identifier) @_2 (#eq? @_2 "succeed")
  )
  arguments: (arguments (unit)) @_3
)
```

## 7. References

- [ZIO Documentation](https://zio.dev/)
- [IntelliJ ZIO Plugin](https://github.com/zio/zio-intellij)
- [Treesitter Query Language](https://tree-sitter.github.io/tree-sitter/using-parsers#query-syntax)
