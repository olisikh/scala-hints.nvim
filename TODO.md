# TODO: IntelliJ ZIO Plugin Parity Roadmap

## Completed

- ZIO: 35 patterns (low/medium parity). See `AGENTS.md` for the pattern catalog.
- Cats-Effect (IO/Resource): 36 patterns implemented. See `AGENTS.md`.
- Cats tagless-final (F[_]): 15 evidence-gated patterns (void, as, *>, <* , flatTap, whenA, unlessA, ifM, handleError, raiseWhen, raiseUnless, fromOption, fromEither, redeem, redeemWith). See `AGENTS.md`.

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

### Cats Tagless-Final — Additional Patterns 🟡
- 15 patterns implemented (`void`, `as`, `*>`, `<*`, `flatTap`, `whenA`, `unlessA`, `ifM`, `handleError`, `raiseWhen`, `raiseUnless`, `fromOption`, `fromEither`, `redeem`, `redeemWith`).
- Remaining candidate patterns: `delayBy`, `timeout` / `timeoutTo`, `tupled` / `parTupled`, `parTraverse`, `replicateA_`, `foreverM`.
- May require expanding the capability lattice with `Temporal`, `Parallel`, etc.

## Known Limitations

1. **Metals Indexing** — Diagnostics only appear after Metals finishes indexing. Editing another file can trigger re-indexing.
2. **Diagnostics Refresh** — Diagnostics sometimes don't refresh after undo.
3. **Whitespace Sensitivity** — Some queries don't match across newlines (e.g., `ZIO\n.unit`).
4. **No Alias Support** — Patterns match literal names only; renamed imports or type aliases are not recognized.

## References
- [IntelliJ ZIO Plugin](https://plugins.jetbrains.com/plugin/13820-zio-for-intellij/features)
- [ZIO Documentation](https://zio.dev/)
- [Treesitter Query Language](https://tree-sitter.github.io/tree-sitter/using-parsers#query-syntax)
