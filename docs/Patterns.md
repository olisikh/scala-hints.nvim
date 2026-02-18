# Pattern Catalog

## Overview

**90 total patterns** across 3 effect libraries, detecting common code smells and suggesting idiomatic replacements.

| Library | Patterns | Type Verification |
| --- | --- | --- |
| [ZIO](#zio-patterns-35) | 35 | Metals LSP `textDocument/typeDefinition` |
| [Cats-Effect](#cats-effect-patterns-40) | 40 | Metals LSP `textDocument/typeDefinition` |
| [Cats Tagless-Final](#cats-tagless-final-patterns-15) | 15 | Local evidence detection |

---

## ZIO Patterns (35)

Patterns for ZIO 2.x effect types, covering constructors, combinators, error handling, and type aliases.

### Key Patterns

| Category | Patterns | Example |
| --- | --- | --- |
| **Constructors & units** | `succeed_unit`, `map_unit`, `as_unit`, `zip_right_unit`, `zip_right_value` | `ZIO.succeed(())` → `ZIO.unit` |
| **Combinators** | `zip_left_value`, `zip_right_operator`, `flat_map_value`, `map_value` | `.map(_ => v)` → `.as(v)` |
| **Error handling** | `zio_die`, `zio_cond`, `catch_all_unit`, `or_else_fail` variants | `.catchAll(_ => ZIO.unit)` → `.ignore` |
| **Type aliases** | `zio_type`, `zlayer_type` | `ZIO[Any, Nothing, A]` → `UIO[A]` |
| **Option/Either** | `zio_none`, `zio_some`, `zio_either` | `ZIO.succeed(None)` → `ZIO.none` |
| **Timing & layers** | `delay`, `to_layer`, `provide_layer` | `ZIO.sleep(d) *> effect` → `effect.delay(d)` |
| **Service access** | `zio_service` | `ZIO.access(identity)` → `ZIO.service[A]` |
| **Transform helpers** | `tap`, `tap_error`, `tap_both`, `when`, `unless` | `if (cond) eff else ZIO.unit` → `eff.when(cond)` |
| **Exit codes** | `exit_code_map`, `exit_code_as`, `exit_code_fold` | `.map(_ => ExitCode.success)` → `.exitCode` |

### Full Pattern List

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

**See also**: [ZIO Documentation](https://zio.dev/)

---

## Cats-Effect Patterns (40)

Patterns for Cats-Effect 3.x `IO` and `Resource` types.

### Key Patterns

| Category | Examples |
| --- | --- |
| **Discard/replace value** | `map_unit`, `map_value`, `pure_unit`, `as_unit` |
| **Sequencing & control flow** | `zip_right_unit`, `zip_right_value`, `when_a`, `unless_a`, `if_m` |
| **Error handling** | `handle_error`, `redeem`, `recover_with`, `adapt_error` |
| **Lifting values** | `from_option`, `from_either`, `from_try`, match-based variants |
| **Parallelism & traversal** | `par_tupled`, `par_sequence`, `par_sequence_`, `traverse`, `traverse_` |
| **Timing & resources** | `delay_by`, `timeout`, `bracket` |
| **Console output** | `println`, `println_apply`, `print`, `print_apply` |

### Example Transformations

```scala
// map_unit
io.map(_ => ())  →  io.void

// map_value  
io.map(_ => x)   →  io.as(x)

// from_option
opt.fold(IO.raiseError(e))(IO.pure)  →  IO.fromOption(opt)(e)

// when_a
if (cond) io else IO.unit  →  io.whenA(cond)

// println
IO(println("hello"))  →  IO.println("hello")
```

**See also**: [Cats-Effect Documentation](https://typelevel.org/cats-effect/)

---

## Cats Tagless-Final Patterns (15)

Patterns for generic `F[_]` code using tagless-final style. These patterns are **evidence-gated** — they only apply when the required typeclass evidence is present in the enclosing `def` signature.

### Evidence Detection

The plugin parses `def` signatures for:

- **Context bounds**: `[F[_]: Sync]`
- **Implicit parameters**: `(implicit F: Monad[F])`
- **Using clauses (Scala 3)**: `(using F: Monad[F])`

### Capability Lattice

```
Sync > MonadError > Monad > Applicative > Apply > Functor
```

Higher capabilities imply lower ones. For example, `Sync[F]` provides all capabilities.

### Full Pattern List

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
| `from_option` | `opt.fold(F.raiseError(err))(F.pure)` | `F.fromOption(opt)(err)` | MonadError |
| `from_either` | `either.fold(F.raiseError, F.pure)` | `F.fromEither(either)` | MonadError |
| `redeem` | `.attempt.map { case Right/Left ... }` | `.redeem(...)` | MonadError |
| `redeem_with` | `.attempt.flatMap { case Right/Left ... }` | `.redeemWith(...)` | MonadError |

**See also**: [Cats Documentation](https://typelevel.org/cats/)

---

## How Patterns Work

### Detection

1. **Treesitter AST matching** — Each pattern is defined as an S-expression query that matches the AST structure of the code.
2. **Predicate filtering** — Queries use `#eq?` and `#any-of?` predicates to match specific identifiers and values.

### Verification

| Library | Verification Method |
| --- | --- |
| ZIO | Metals `textDocument/typeDefinition` confirms the expression has a ZIO type |
| Cats-Effect | Metals `textDocument/typeDefinition` confirms the expression has an IO/Resource type |
| Cats Tagless-Final | Local parsing of `def` signature for typeclass evidence |

When Metals is unavailable, ZIO and Cats-Effect hints are suppressed. Cats tagless-final hints work without LSP.

### Replacement

Each pattern includes a handler that:
1. Extracts the source range from the matched AST nodes
2. Constructs the replacement code
3. Returns a diagnostic (with severity) and/or a code action

### Example: `succeed_unit`

**Query**:
```query
(call_expression
  function: (field_expression
    value: (_) @_1 (#eq? @_1 "ZIO")
    field: (identifier) @_2 (#eq? @_2 "succeed")
  )
  arguments: (arguments (unit)) @_3
)
```

**Handler**:
- Detects `ZIO.succeed(())`
- Suggests replacement: `ZIO.unit`
- Severity: `HINT` (configurable)

---

## Adding New Patterns

See [AGENTS.md](../AGENTS.md#6-adding-a-new-pattern) for the complete guide on adding new patterns.

Quick steps:
1. Use `:InspectTree` in Neovim to understand the AST
2. Add query and handler to the appropriate `libs/*/queries.lua`
3. Register in the library module
4. Add tests
5. Update documentation
