# AGENTS.md - Project Documentation

## 1. Project Overview

`scala-hints.nvim` is a Neovim plugin that provides opinionated diagnostics and quickfix code actions for effect-library Scala code (ZIO, Cats-Effect IO/Resource, and Cats tagless-final F[_]). It uses Treesitter for AST pattern matching, Metals LSP for type verification, and native Neovim diagnostics/code-action APIs.

## 2. Architecture

```text
  LspAttach (Metals)
    |
    v
      client.lua (in-process LSP)
    |                          |
    v                          v
  didOpen/didSave -> diagnostics.lua    textDocument/codeAction -> actions.lua
    \                                  /
     +------ query.run_query ---------+
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
| `init.lua` | Entry point; registers LspAttach autocommand and starts in-process client |
| `diagnostics.lua` | Orchestrates diagnostic collection by running Treesitter queries |
| `actions.lua` | Resolves code actions for a given range |
| `query.lua` | Generic Treesitter query execution engine |
| `libs/init.lua` | Library registry; merges queries with `lib/query` namespacing |
| `libs/zio/queries.lua` | All 35 ZIO query definitions and handlers |
| `libs/zio/init.lua` | ZIO library module (name + queries table) |
| `libs/cats-effect/queries.lua` | All 36 Cats-Effect query definitions and handlers |
| `libs/cats-effect/init.lua` | Cats-Effect library module (name + queries table) |
| `libs/cats/queries.lua` | All 15 Cats tagless-final query definitions and handlers |
| `libs/cats/init.lua` | Cats tagless-final library module (name + queries table) |
| `cats/evidence.lua` | Typeclass evidence detector for tagless-final F[_] patterns |
| `semantic.lua` | LSP type definition verification, caching, and `type_definition_predicate` |
| `client.lua` | In-process LSP client; publishes diagnostics and code actions |
| `utils.lua` | Async helpers, node inspection |
| `logger.lua` | File-based logging |
| `constants.lua` | Shared metadata (namespace name, filetype) |

### Query Handler Flow

1. **Trigger**: `LspAttach` for Metals starts the in-process client; diagnostics refresh on `textDocument/didOpen` and `textDocument/didSave`.
2. **Execution**: `diagnostics.collect_diagnostics` or `actions.resolve_actions` iterates over queries.
3. **Matching**: `query.run_query` executes the Treesitter query against the buffer's AST.
4. **Handling**: Each match invokes the handler from `libs/zio/queries.lua`, `libs/cats-effect/queries.lua`, or `libs/cats/queries.lua`.
5. **Verification**: ZIO and Cats-Effect handlers call `semantic.type_definition_predicate` to confirm types via Metals. Cats tagless-final handlers use `cats/evidence.lua` to verify typeclass evidence in the enclosing `def` signature.
6. **Result**: Diagnostics feed `vim.diagnostic.set()`; code actions flow through the wrapped LSP handler.

## 3. Pattern Catalog

35 ZIO patterns implemented in [libs/zio/queries.lua](lua/scala-hints/libs/zio/queries.lua):

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

### Cats-Effect Patterns (IO/Resource)

40 Cats-Effect patterns implemented in [libs/cats-effect/queries.lua](lua/scala-hints/libs/cats-effect/queries.lua).
Examples and motivation live in the tests under `tests/cats-effect/`.

| Pattern | Detection | Replacement |
| :--- | :--- | :--- |
| `println` | `IO(println(x))` | `IO.println(x)` |
| `println_apply` | `IO.apply(println(x))` | `IO.println(x)` |
| `print` | `IO(print(x))` | `IO.print(x)` |
| `print_apply` | `IO.apply(print(x))` | `IO.print(x)` |

### Cats Tagless-Final Patterns (F[_])

15 Cats tagless-final patterns implemented in [libs/cats/queries.lua](lua/scala-hints/libs/cats/queries.lua).
These patterns match generic `F[_]` code and are gated by typeclass evidence (context bounds, implicit/using params) in the enclosing `def`.

| Pattern | Detection | Replacement | Required Evidence |
| :--- | :--- | :--- | :--- |
| `map_unit` | `fa.map(_ => ())` | `fa.void` | Functor |
| `map_value` | `fa.map(_ => v)` | `fa.as(v)` | Functor |
| `flat_map_value` | `fa.flatMap(_ => fb)` | `fa *> fb` | Apply |
| `product_l` | `fa.flatMap(a => fb.as(a))` | `fa <* fb` | Apply |
| `flat_tap` | `fa.flatMap(a => effect.as(a))` | `fa.flatTap(a => effect)` | FlatMap |
| `when_a` | `if (cond) fa else F.unit` | `fa.whenA(cond)` | Applicative |
| `unless_a` | `if (!cond) fa else F.unit` | `fa.unlessA(cond)` | Applicative |
| `if_m` | `fb.flatMap(b => if (b) fa else fc)` | `fb.ifM(fa, fc)` | Monad |
| `handle_error` | `fa.attempt.flatMap { case Right(a) => F.pure(a); case Left(e) => F.pure(default) }` | `fa.handleError(_ => default)` | MonadError |
| `raise_when` | `if (cond) F.raiseError(err) else F.unit` | `F.raiseWhen(cond)(err)` | MonadError |
| `raise_unless` | `if (!cond) F.raiseError(err) else F.unit` | `F.raiseUnless(cond)(err)` | MonadError |
| `from_option` | `opt.fold(F.raiseError(err))(F.pure)` | `F.fromOption(opt, err)` | MonadError |
| `from_either` | `either.fold(F.raiseError, F.pure)` | `F.fromEither(either)` | MonadError |
| `redeem` | `.attempt.map { case Right/Left ... }` | `.redeem(...)` | MonadError |
| `redeem_with` | `.attempt.flatMap { case Right/Left ... }` | `.redeemWith(...)` | MonadError |

**Evidence Detection**: The `cats/evidence.lua` module parses the nearest enclosing `def` header for:
- Context bounds: `[F[_]: Sync]`
- Implicit parameters: `(implicit F: Monad[F])`
- Using clauses (Scala 3): `(using F: Monad[F])`

Capability lattice: Sync > MonadError > Monad > Applicative > Apply > Functor.
Evidence is cached per-buffer per-changedtick.

### Remaining IntelliJ Parity Gaps

| Pattern | Description | Complexity |
| :--- | :--- | :--- |
| Type Modes | `CanFail`, `NeedsEnv`, contravariance | High |
| If-Guard Detection | For-comprehension guard patterns | High |
| Wrap Conversions | Wrapping `Option/Future/Try/Either` | High |
| Yield Effect | Yielding a ZIO effect in for-comprehension | High |

### Cats-Effect Status

Cats-Effect (IO/Resource) patterns are implemented under `lua/scala-hints/libs/cats-effect/` and registered in the library registry.

## 4. Technical Details

- **Treesitter queries** use S-expressions with `#eq?` and `#any-of?` predicates.
- **Async**: All queries run via `plenary.async`; `semantic.type_definition_predicate` retries with configurable backoff (default 400/1000/2000 ms).
- **Metals readiness**: Diagnostics are published only when a Metals client is attached and initialized; the in-process client refreshes on `didOpen`/`didSave`.
- **Timeouts**: Diagnostics 30s, code actions 10s, Metals readiness 10s.
- **Type definition caching**: Results cached per buffer tick to avoid redundant LSP calls.
- **Type checking**: Type definition URIs matched against `is_zio_type`/`is_zlayer_type` or `is_cats_io_type` predicates.
- **Evidence checking (Cats tagless)**: `cats/evidence.lua` parses `def` signatures for typeclass evidence; no LSP calls needed.
- ZIO and Cats-Effect handlers verify types via Metals `textDocument/typeDefinition`; when Metals is unavailable, those hints are suppressed. Cats tagless-final hints use local evidence detection only.

## 5. Known Limitations

- Patterns match literal names only (`ZIO`); type aliases and renamed imports are not recognized.
- Some queries are whitespace-sensitive (e.g., `ZIO\n.unit` may not match).
- ZIO and Cats-Effect handlers verify types via Metals `textDocument/typeDefinition`; when Metals is unavailable, those hints are suppressed. Cats tagless-final hints use local evidence detection only.
- Diagnostics may not refresh after undo operations.
- Performance may degrade on very large files due to lack of incremental parsing.

## 6. Adding a New Pattern

1. Use `:InspectTree` in Neovim to see the AST for the code you want to match.
2. Add a new entry to the queries table in the appropriate library:
  - ZIO: `lua/scala-hints/libs/zio/queries.lua`
  - Cats-Effect: `lua/scala-hints/libs/cats-effect/queries.lua`
  - Cats (tagless): `lua/scala-hints/libs/cats/queries.lua`
   - Write the Treesitter S-expression query.
   - Implement the `handler` function to extract ranges and suggest replacements.
   - Optionally set `diagnostic_severity` (`HINT`/`INFO`/`WARN`/`ERROR`/`OFF`).
3. Register the query name in the library module (`lua/scala-hints/libs/zio/init.lua`, `lua/scala-hints/libs/cats-effect/init.lua`, or `lua/scala-hints/libs/cats/init.lua`). For a new library, add a module and register it in `lua/scala-hints/libs/init.lua`.
4. Use `semantic.type_definition_predicate` for type verification (ZIO/Cats-Effect), or `cats/evidence.has_capability` for tagless-final patterns.
5. Add tests in `tests/zio/queries_spec.lua`, `tests/cats_effect/queries_spec.lua`, or `tests/cats/queries_spec.lua` (mock with `H.mock_type_definition_predicate(true)` for LSP-dependent handlers). For new libraries, add `tests/<lib>/queries_spec.lua` and update `tests/libs_registry_spec.lua`.
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

## 7. Test Project

A minimal Scala 3 SBT project is available at `test-project/` for manual verification of all patterns. It contains intentional code smells that trigger each pattern.

### Structure

```
test-project/
├── build.sbt                    # Scala 3 + ZIO + Cats-Effect dependencies
├── project/build.properties     # sbt version
├── README.md                    # Setup and usage instructions
└── src/main/scala/smells/
    ├── ZioSmells.scala          # 35 ZIO patterns
    ├── CatsEffectSmells.scala   # 40 Cats-Effect patterns
    └── CatsTaglessSmells.scala  # 15 Cats tagless-final patterns
```

### Usage

1. Open a smells file in Neovim with Metals running
2. Wait for diagnostics to appear
3. Use `:lua vim.lsp.buf.code_action()` to see suggested fixes

### Adding New Smells

When implementing a new pattern, add a corresponding smell to the test project:

1. **Identify the target file**:
   - ZIO → `test-project/src/main/scala/smells/ZioSmells.scala`
   - Cats-Effect → `test-project/src/main/scala/smells/CatsEffectSmells.scala`
   - Cats tagless-final → `test-project/src/main/scala/smells/CatsTaglessSmells.scala`

2. **Add the smell** following the existing format:
   ```scala
   // pattern_name: detection code -> replacement
   def smellN = /* code that triggers the pattern */
   ```

3. **For Cats tagless-final**, include the required typeclass evidence:
   ```scala
   def smellN[F[_]: Monad](fa: F[Int]): F[String] =
     fa.flatMap(b => if (b) F.pure("yes") else F.pure("no"))
   ```

4. **Verify** by opening the file in Neovim and checking that the diagnostic appears.

## 8. References

- [ZIO Documentation](https://zio.dev/)
- [IntelliJ ZIO Plugin](https://github.com/zio/zio-intellij)
- [Treesitter Query Language](https://tree-sitter.github.io/tree-sitter/using-parsers#query-syntax)
