# scala-hints.nvim

Opinionated Neovim diagnostics + quickfix code actions for **ZIO**-based Scala code. Uses Treesitter for AST matching, Metals LSP for type verification, and native Neovim diagnostics / code-action hooks.

## Features

- **35 Treesitter patterns** detecting common ZIO code smells with idiomatic replacements (e.g. `.map(_ => ())` → `.unit`)
- **Native diagnostics & code actions** — hooks `vim.diagnostic.set()` and the LSP code-action handler
- **Metals-aware** — type definition verification ensures replacements only apply to actual ZIO types
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
    excluded_libs = {}, -- Exclude libraries from diagnostics (performance), e.g. { "zio", "cats-effect", "yaes", "kyo" }
  actions = {
    excluded_libs = {}, -- Exclude libraries from code actions (performance), e.g. { "zio", "cats-effect", "yaes", "kyo" }
  },
})
```

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
3. Add your handler to `libs/zio/queries.lua`, register it in the libs registry, and add tests.
4. See [TODO.md](TODO.md) for remaining roadmap items.

## References

- [ZIO Documentation](https://zio.dev/)
- [IntelliJ ZIO Plugin](https://plugins.jetbrains.com/plugin/13820-zio-for-intellij/features)
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- [nvim-metals](https://github.com/scalameta/nvim-metals)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
