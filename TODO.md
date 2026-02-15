# TODO: IntelliJ ZIO Plugin Parity Roadmap

## Completed (35 patterns)

All low- and medium-complexity patterns are implemented. See `AGENTS.md` §5.1 for the full pattern catalog.

## Future Work

### Type Mode Detection (CanFail, NeedsEnv) 🔴
- `CanFail`: warn when using failable operations on infallible ZIO
- `NeedsEnv`: warn when using `.provide*` on effects that don't require an environment
- LSP-dependent (needs type inference from Metals)

### If-Guard Detection in For-Comprehension 🔴
- Detect patterns that throw in for-comprehension guards
- Suggest `filter` or checked operations instead

### Wrapping Option/Future/Try/Either in ZIO 🔴
- Detect manual pattern matching or method calls that convert types
- Suggest `ZIO.from*` equivalents

### Yield Effect in For-Comprehension 🔴
- Detect yielding a ZIO effect without flatMapping
- Suggest `flatten` or appropriate combinator

### Cats-Effect Tagless-Final TODOs 🔴
- Add evidence-based patterns for `F[_]` where typeclass support must be proven via Metals `textDocument/typeDefinition`.
- Candidate patterns: `void`, `as`, `*>` / `>>`, `whenA` / `unlessA`, `ifM`, `raiseWhen` / `raiseUnless`,
  `fromOption` / `fromEither` / `fromTry`, `handleError` / `handleErrorWith`, `redeem` / `redeemWith`,
  `flatTap`, `delayBy`, `timeout` / `timeoutTo`, `tupled` / `parTupled`, `parTraverse`, `replicateA_`, `foreverM`.
- Requires confirming `Functor`/`Apply`/`Monad`/`MonadError`/`Temporal`/`Parallel` evidence before emitting hints.

## Known Limitations

1. **Metals Indexing** — Diagnostics only appear after Metals finishes indexing. Editing another file can trigger re-indexing.
2. **Diagnostics Refresh** — Diagnostics sometimes don't refresh after undo.
3. **Whitespace Sensitivity** — Some queries don't match across newlines (e.g., `ZIO\n.unit`).
4. **No Alias Support** — Patterns match literal names only; renamed imports or type aliases are not recognized.

## References
- [IntelliJ ZIO Plugin](https://plugins.jetbrains.com/plugin/13820-zio-for-intellij/features)
- [ZIO Documentation](https://zio.dev/)
- [Treesitter Query Language](https://tree-sitter.github.io/tree-sitter/using-parsers#query-syntax)
