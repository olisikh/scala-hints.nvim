# scala-hints.nvim

Opinionated Neovim diagnostics + quickfix code actions for **ZIO**-based Scala code. Uses Treesitter for AST matching, Metals LSP for type verification, and native Neovim diagnostics / code-action hooks.

## Features

- **35 Treesitter patterns** detecting common ZIO code smells with idiomatic replacements (e.g. `.map(_ => ())` → `.unit`)
- **Native diagnostics & code actions** — hooks `vim.diagnostic.set()` and the LSP code-action handler
- **Metals-aware** — hover verification ensures replacements only apply to actual ZIO types
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
    'nvim-treesitter/nvim-treesitter',
    'scalameta/nvim-metals',
  },
}
```

Call `require('scala-hints').setup()` after Metals is configured and attaching to Scala buffers.

### Configuration

```lua
require('scala-hints').setup({
  hover = {
    timeouts_ms = { 400, 1000, 2000 },
    log_misses = true,
  },
  diagnostics = {
    default_severity = 'HINT',
    overrides = {
      ['zio/zip_left_value'] = 'OFF',
      ['zio/zip_right_operator'] = 'OFF',
      ['zio/zio_die'] = 'WARN',
    },
  },
})
```

| Option | Description |
| --- | --- |
| `hover.timeouts_ms` | Retry timeouts (ms) for Metals hover requests |
| `hover.log_misses` | Log final hover misses to `/tmp/scala-hints/log` |
| `diagnostics.default_severity` | Default severity: `HINT`, `INFO`, `WARN`, `ERROR`, or `OFF` |
| `diagnostics.overrides` | Per-query overrides keyed by `zio/<query>`. `OFF` suppresses diagnostics but still emits code actions |

## Usage

1. Open a Scala file where Metals is running.
2. Diagnostics appear automatically (default severity: `HINT`).
3. Apply fixes via `:lua vim.lsp.buf.code_action()` or your preferred keymap.

## Pattern Catalog

35 patterns across constructors, combinators, error handling, type aliases, and helpers:

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

Full details and handler descriptions are in [AGENTS.md](AGENTS.md).

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
| `semantic.lua` | LSP hover verification and caching |
| `utils.lua` | Async helpers, node inspection, Metals readiness polling |
| `client.lua` | LSP client management |
| `constants.lua` | Shared metadata (namespace name, filetype) |

## Troubleshooting

- **No diagnostics?** Metals must signal readiness (`MetalsReady` / `MetalsInitialized`) before hints appear.
- **Diagnostics disappear after undo?** Reopen the buffer or trigger a save to force a refresh.
- **False positives?** Some handlers skip Metals hover verification. Check [AGENTS.md](AGENTS.md) for details on which patterns are LSP-dependent.

## Contributing

1. Read [AGENTS.md](AGENTS.md) for the pattern catalog, architecture details, and addition guide.
2. Use `:InspectTree` to understand the AST shape you want to target.
3. Add your handler to `libs/zio/queries.lua`, register it in the libs registry, and add tests.
4. See [TODO.md](TODO.md) for remaining roadmap items.

## References

- [ZIO Documentation](https://zio.dev/)
- [IntelliJ ZIO Plugin](https://plugins.jetbrains.com/plugin/13820-zio-for-intellij/features)
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- [nvim-metals](https://github.com/scalameta/nvim-metals)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
