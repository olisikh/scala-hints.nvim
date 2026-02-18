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

### Full Pattern List

| Pattern | Detection | Replacement |
| :--- | :--- | :--- |
| `succeed_unit` | `ZIO.succeed(())` | `ZIO.unit` |
| `zio_die` | `ZIO.fail(ex).orDie` | `ZIO.die(ex)` |
| `map_unit` | `.map(_ => ())` | `.unit` |
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
| `zio_type` | `ZIO[Any, Nothing, A]` | `UIO[A]` |
| `zio_type` | `ZIO[Any, Throwable, A]` | `Task[A]` |
| `zlayer_type` | `ZLayer[Any, Nothing, A]` | `ULayer[A]` |
| `zlayer_type` | `ZLayer[Any, Throwable, A]` | `TaskLayer[A]` |
| `zio_none` | `ZIO.succeed(None)` | `ZIO.none` |
| `zio_some` | `ZIO.succeed(Some(v))` | `ZIO.some(v)` |
| `zio_either` | `ZIO.succeed(Left(v))` | `ZIO.left(v)` |
| `zio_either` | `ZIO.succeed(Right(v))` | `ZIO.right(v)` |
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

### Full Pattern List

| Pattern | Detection | Replacement |
| :--- | :--- | :--- |
| `map_unit` | `.map(_ => ())` | `.void` |
| `map_value` | `.map(_ => v)` | `.as(v)` |
| `pure_unit` | `IO.pure(())` | `IO.unit` |
| `as_unit` | `.as(())` | `.void` |
| `zip_right_unit` | `*> IO.unit` | `.void` |
| `zip_right_value` | `*> IO.pure(v)` | `.as(v)` |
| `flat_map_value` | `.flatMap(_ => v)` | `>> v` |
| `flat_tap` | `.flatMap(a => effect.as(a))` | `.flatTap(a => effect)` |
| `when_a` | `if (cond) fa else IO.unit` | `fa.whenA(cond)` |
| `unless_a` | `if (!cond) fa else IO.unit` | `fa.unlessA(cond)` |
| `if_m` | `.flatMap(b => if (b) fa else fb)` | `.ifM(fa, fb)` |
| `forever_m` | `def loop = effect.flatMap(_ => loop)` | `effect.foreverM` |
| `handle_error` | `.attempt.flatMap { Right/Left ... }` | `.handleError(...)` |
| `raise_when` | `if (cond) IO.raiseError(err) else IO.unit` | `IO.raiseWhen(cond)(err)` |
| `raise_unless` | `if (cond) IO.unit else IO.raiseError(err)` | `IO.raiseUnless(cond)(err)` |
| `from_option` | `opt.fold(IO.raiseError(err))(IO.pure)` | `IO.fromOption(opt)(err)` |
| `from_option_match` | `opt match { Some/None => ... }` | `IO.fromOption(opt)(err)` |
| `from_either` | `either.fold(IO.raiseError, IO.pure)` | `IO.fromEither(either)` |
| `from_either_match` | `either match { Right/Left => ... }` | `IO.fromEither(either)` |
| `from_try` | `Try(x).fold(IO.raiseError, IO.pure)` | `IO.fromTry(Try(x))` |
| `redeem` | `.attempt.map { Right/Left ... }` | `.redeem(...)` |
| `redeem_with` | `.attempt.flatMap { Right/Left ... }` | `.redeemWith(...)` |
| `recover_with` | `.attempt.flatMap { typed Left ... }` | `.recoverWith { case ... }` |
| `adapt_error` | `.handleErrorWith(e => IO.raiseError(wrap(e)))` | `.adaptError { case e => wrap(e) }` |
| `traverse` | `.map(f).sequence` | `.traverse(f)` |
| `traverse_` | `.map(f).sequence_` | `.traverse_(f)` |
| `par_tupled` | `fa.flatMap(a => fb.map(b => (a, b)))` | `(fa, fb).tupled` |
| `par_sequence` | `.map(f).parSequence` | `.parTraverse(f)` |
| `par_sequence_` | `.map(f).parSequence_` | `.parTraverse_(f)` |
| `par_tupled_fibers` | `for { .start; .joinWithNever } yield (...)` | `(fa, fb).parTupled` |
| `option_traverse` | `opt match { Some => f(a); None => IO.unit }` | `opt.traverse_(f)` |
| `replicate_a_` | `(1 to n).toList.traverse(_ => effect)` | `effect.replicateA_(n)` |
| `map_n` | `for { a <- fa; b <- fb } yield C(a, b)` | `(fa, fb).mapN(C.apply)` |
| `delay_by` | `Temporal[IO].sleep(d) *> effect` | `effect.delayBy(d)` |
| `timeout` | `IO.race(effect, sleep(d)).flatMap { ... }` | `effect.timeout(d)` |
| `bracket` | `acquire.flatMap(a => use(a).guarantee(release))` | `acquire.bracket(use)(release)` |
| `println` | `IO(println(x))` | `IO.println(x)` |
| `println_apply` | `IO.apply(println(x))` | `IO.println(x)` |
| `print` | `IO(print(x))` | `IO.print(x)` |
| `print_apply` | `IO.apply(print(x))` | `IO.print(x)` |

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
| `from_option` | `opt.fold(F.raiseError(err))(F.pure)` | `F.fromOption(opt, err)` | MonadError |
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
