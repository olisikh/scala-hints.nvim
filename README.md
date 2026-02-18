# scala-hints.nvim

Opinionated Neovim diagnostics + quickfix code actions for **ZIO**, **Cats-Effect (IO/Resource)**, and **Cats tagless-final (F[_])** Scala code. Uses Treesitter for AST matching, Metals LSP for type verification, and native Neovim diagnostics / code-action hooks.

## Features

- **ZIO (35) + Cats-Effect (40) + Cats tagless-final (15) Treesitter patterns** detecting common effect code smells with idiomatic replacements (e.g. `.map(_ => ())` → `.unit`/`.void`)
- **Native diagnostics & code actions** — hooks `vim.diagnostic.set()` and the LSP code-action handler
- **Metals-aware** — type definition verification ensures replacements only apply to actual ZIO or Cats-Effect types
- **Evidence-gated** — Cats tagless-final patterns verify typeclass evidence (Functor/Monad/etc.) in the enclosing `def` signature
- **Per-query severity** — configure each pattern as `HINT`, `INFO`, `WARN`, `ERROR`, or `OFF`
- **Async** — all queries run via `plenary.async` with configurable timeouts

## Requirements

Neovim 0.11+

## Installation

```lua
{
  'olisikh/scala-hints.nvim',
  opts = {},
  dependencies = {
    'nvim-lua/plenary.nvim',
    'scalameta/nvim-metals',
  },
}
```

Call `require('scala-hints').setup()` to init the plugin.
The plugin listens on `LspAttach`, only runs on Scala buffers, and uses Metals type definition (`textDocument/typeDefinition`) for type checks.

### Configuration

```lua
require('scala-hints').setup({
  logging = {
    enabled = true, -- Enable file logging
    level = 'INFO', -- Log level: debug|info|warn|error, case-insensitive
  },
  type_definition = {
    timeouts_ms = { 400, 1000, 2000 }, -- Retry schedule for Metals textDocument/typeDefinition (ms)
    max_inflight = 4, -- Max concurrent requests per buffer
  },
  diagnostics = {
    default_severity = 'HINT', -- Default diagnostic severity
    overrides = {
      ['zio/zip_left_value'] = 'OFF', -- Disable a specific diagnostic
      ['zio/zip_right_operator'] = 'OFF',
      ['zio/zio_die'] = 'WARN', -- Elevate severity for a specific diagnostic
    },
    excluded_libs = {}, -- Exclude libraries from diagnostics (performance), e.g. { "zio", "cats-effect", "cats" }
  },
  actions = {
    excluded_libs = {}, -- Exclude libraries from code actions (performance), e.g. { "zio", "cats-effect", "cats" }
  },
})
```

## Usage

1. Open a Scala file where Metals is running.
2. Diagnostics appear automatically (default severity: `HINT`).
3. Apply fixes via `:lua vim.lsp.buf.code_action()` or your preferred keymap.

### Commands

| Command | Description |
| --- | --- |
| `:ScalaHintsApplyBuffer` | Apply all scala-hints fixes in the current buffer |

The `:ScalaHintsApplyBuffer` command applies all available fixes at once. If multiple fixes overlap (e.g., a `println` fix inside a `traverse_` fix), overlapping fixes are skipped to prevent broken code. Run the command again to apply remaining fixes after the buffer is re-analyzed.

## Pattern Catalog

### ZIO (35 patterns)

Patterns across constructors, combinators, error handling, type aliases, and helpers:

| Category | Patterns |
| --- | --- |
| **Constructors & units** | `succeed_unit`, `map_unit`, `as_unit`, `zip_right_unit`, `zip_right_value` |
| **Combinators** | `zip_left_value`, `zip_right_operator`, `flat_map_value`, `map_value`, `zio_foreach`, `foreach_par_n`, `fold_cause_ignore` |
| **Error handling** | `zio_die`, `zio_cond`, `catch_all_unit`, `or_else_fail`, `or_else_fail2`, `or_else_fail3` |
| **Type aliases** | `zio_type`, `zlayer_type` |
| **Option/Either** | `zio_none`, `zio_some`, `zio_either` |
| **Timing & layers** | `delay`, `to_layer`, `provide_layer` |
| **Service access** | `zio_service` |
| **Transform helpers** | `tap`, `tap_error`, `tap_both`, `when`, `unless` |
| **Exit codes** | `exit_code_map`, `exit_code_as`, `exit_code_fold` |

### Cats-Effect (IO/Resource, 40 patterns)

Cats-Effect hints cover common IO/Resource idioms and include:

| Category | Examples |
| --- | --- |
| **Discard/replace value** | `map_unit`, `map_value`, `pure_unit`, `as_unit` |
| **Sequencing & control flow** | `zip_right_unit`, `zip_right_value`, `when_a`, `unless_a`, `if_m` |
| **Error handling** | `handle_error`, `redeem`, `recover_with`, `adapt_error` |
| **Lifting values** | `from_option`, `from_either`, `from_try`, match-based variants |
| **Parallelism & traversal** | `par_tupled`, `par_sequence`, `par_sequence_`, `traverse`, `traverse_` |
| **Timing & resources** | `delay_by`, `timeout`, `bracket` |
| **Console output** | `println`, `println_apply`, `print`, `print_apply` |

Full details and handler descriptions are in [AGENTS.md](AGENTS.md).

### Cats Tagless-Final (F[_], 15 patterns)

Evidence-gated patterns for generic `F[_]` code, requiring typeclass evidence (context bounds / implicit / using) in the enclosing `def`:

| Pattern | Detection | Replacement | Evidence |
| --- | --- | --- | --- |
| `map_unit` | `fa.map(_ => ())` | `fa.void` | Functor |
| `map_value` | `fa.map(_ => v)` | `fa.as(v)` | Functor |
| `flat_map_value` | `fa.flatMap(_ => fb)` | `fa *> fb` | Apply |
| `product_l` | `fa.flatMap(a => fb.as(a))` | `fa <* fb` | Apply |
| `flat_tap` | `fa.flatMap(a => effect.as(a))` | `fa.flatTap(a => effect)` | FlatMap |
| `when_a` | `if (cond) fa else F.unit` | `fa.whenA(cond)` | Applicative |
| `unless_a` | `if (!cond) fa else F.unit` | `fa.unlessA(cond)` | Applicative |
| `if_m` | `fb.flatMap(b => if (b) fa else fc)` | `fb.ifM(fa, fc)` | Monad |
| `handle_error` | `.attempt.flatMap { case Right/Left ... }` | `.handleError` | MonadError |
| `raise_when` | `if (cond) F.raiseError(err) else F.unit` | `F.raiseWhen(cond)(err)` | MonadError |
| `raise_unless` | `if (!cond) F.raiseError(err) else F.unit` | `F.raiseUnless(cond)(err)` | MonadError |
| `from_option` | `opt.fold(F.raiseError(err))(F.pure)` | `F.fromOption(opt, err)` | MonadError |
| `from_either` | `either.fold(F.raiseError, F.pure)` | `F.fromEither(either)` | MonadError |
| `redeem` | `.attempt.map { case Right/Left ... }` | `.redeem(...)` | MonadError |
| `redeem_with` | `.attempt.flatMap { case Right/Left ... }` | `.redeemWith(...)` | MonadError |

## Architecture

```text
  BufWritePost / BufEnter          vim.lsp.buf.code_action()
         |                                |
         v                                v
  diagnostics.lua                   actions.lua
         \                              /
          +---- query.run_query -------+
                      |
              handler(bufnr, matches)
                      |
         +------------+------------+
         |                         |
  vim.diagnostic.set()    LSP code-action response
```

| Module | Responsibility |
| --- | --- |
| `init.lua` | Registers namespace, Metals-gated autocommands, and code-action wrapper |
| `diagnostics.lua` | Collects diagnostics by running Treesitter queries |
| `actions.lua` | Resolves code actions for a given range |
| `query.lua` | Generic query execution engine |
| `libs/zio/queries.lua` | All 35 ZIO Treesitter query definitions and handlers |
| `libs/cats-effect/init.lua` | Cats-Effect library registry module |
| `libs/cats-effect/queries.lua` | All 36 Cats-Effect Treesitter query definitions and handlers |
| `libs/cats/init.lua` | Cats tagless-final library registry module |
| `libs/cats/queries.lua` | All 15 Cats tagless-final Treesitter query definitions and handlers |
| `cats/evidence.lua` | Typeclass evidence detector for F[_] patterns |
| `semantic.lua` | LSP type definition verification and caching |
| `utils.lua` | Async helpers, node inspection, Metals readiness polling |
| `client.lua` | LSP client management |
| `constants.lua` | Shared metadata (namespace name, filetype) |

## Troubleshooting

- **No diagnostics?** Metals must signal readiness (`MetalsReady` / `MetalsInitialized`) before diagnostics appear.
- **Diagnostics disappear after undo?** Reopen the buffer or trigger a save to force a refresh.
- **False positives?** Some handlers skip Metals type definition verification. Check [AGENTS.md](AGENTS.md) for details on which patterns are LSP-dependent.

## Contributing

1. Read [AGENTS.md](AGENTS.md) for the pattern catalog, architecture details, and addition guide.
2. Use `:InspectTree` to understand the AST shape you want to target.
3. Add your handler to the appropriate `libs/*/queries.lua`, register it in the libs registry, and add tests.
4. See [TODO.md](TODO.md) for remaining roadmap items.

## References

- [ZIO Documentation](https://zio.dev/)
- [IntelliJ ZIO Plugin](https://plugins.jetbrains.com/plugin/13820-zio-for-intellij/features)
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- [nvim-metals](https://github.com/scalameta/nvim-metals)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
