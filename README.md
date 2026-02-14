# scala-hints.nvim

Opinionated Neovim diagnostics + quickfix helpers for **ZIO**-based Scala code. It leans on Treesitter for precise AST matching, Metals for type insight, and native Neovim diagnostics / LSP hooks for delivering hints and code actions without extra ceremony.

## Snapshot

| Aspect | Details |
| --- | --- |
| **Status** | Sandbox/learning project—use at your own risk. |
| **Lines of Lua** | 1,557 total; `lua/scala-hints/query.lua` is the pattern-heavy core (~1,135 lines). |
| **Test Coverage** | 0% (no automated tests yet). |
| **Dependencies** | `plenary.nvim`, `nvim-treesitter`, `nvim-metals`. |
| **Primary Goal** | Detect common ZIO code smells and offer idiomatic replacements (e.g., `.map(_ => ())` → `.unit`). |

## Features

- **Native diagnostics & code actions**: Hooks Neovim autocommands and `vim.lsp.handlers` to reuse the same query list, pushing results through `vim.diagnostic.set()` and the native code-action plumbing.
- **Metals-aware validation**: `utils.hover_node_and_match` inspects the hover response to ensure replacements apply to actual ZIO nodes.
- **Async humble flow**: Every query runs via `plenary.async`; `run_or_timeout` and dedicated timeouts (10s for Metals readiness, 10s for actions, 30s for diagnostics) keep prompts responsive.
- **Pattern catalog**: 24 Treesitter patterns (20 implemented + 4 placeholders) target constructors, combinators, error handling, type aliases, and `Option`/`Either` helpers—full details live in `AGENTS.md`.

## Architecture Overview

```text
+------------------------------------------------------------------+
|                             Neovim                               |
|    (BufWritePost/BufEnter autocommands + LSP code-action hooks)  |
+------------------------+--------------------------+--------------+
           |                         |
           v                         v
diagnostics autocommand   intercepted LSP handler
           |                         |
           v                         v
diagnostics.collect_diagnostics   actions.resolve_actions
           |                         |
           +------------+------------+
                        |
                query.run_query (Treesitter)
                        |
               +--------+--------+
               |                 |
     Handler invocation   Handler invocation
               |                 |
               v                 v
vim.diagnostic.set(...)    vim.lsp.handlers['textDocument/codeAction']
```

### Module Responsibilities

| File | Responsibility |
| --- | --- |
| `lua/scala-hints/init.lua` | Registers the diagnostic namespace, Metals-gated autocommands, and the LSP code-action wrapper that injects scala-hints replacements into the native handler. |
| `lua/scala-hints/diagnostics.lua` | Iterates over the query list, joins all async results, and returns native diagnostics that `init.lua` feeds to `vim.diagnostic.set()`. |
| `lua/scala-hints/actions.lua` | Mirrors the diagnostics flow, building range/replacement payloads that `init.lua` exposes through the wrapped code-action handler. |
| `lua/scala-hints/query.lua` | Houses every Treesitter query and handler pair; categories include constructor simplifications, combinator optimizations, error-handling helpers, `ZIO`/`ZLayer` type rewrites, and `Option`/`Either` helpers. Placeholders (`exit_code*`, `zio_die`) note unfinished work. |
| `lua/scala-hints/utils.lua` | Utility functions for async racing, Metals readiness polling, node inspection, flattening arrays, hover verification, and traversal helpers. |
| `lua/scala-hints/constants.lua` | Shared metadata such as the diagnostic namespace name (`scala-hints`) and target filetype (`scala`). |

## Pattern Highlights

Implemented optimizations:
- Constructors & units: `succeed_unit`, `map_unit`, `as_unit`, `zip_right_unit`, `zip_right_value`
- Combinators: `zip_left_value`, `flat_map_value`, `map_value`, `zio_foreach`, `fold_cause_ignore`
- Error handling: `catch_all_unit`, `or_else_fail`, `or_else_fail2`, `or_else_fail3`
- Type shorthands: `zio_type`, `zlayer_type`
- Optional/either helpers: `zio_none`, `zio_some`, `zio_either`
- Placeholders waiting for implementation: `exit_code`, `exit_code2`, `exit_code3`, `zio_die`

Every handler returns a payload that populates both diagnostics and code actions, making it easy to surface the hint or apply the replacement automatically.

## Installation

```lua
{
  'alisiikh/scala-hints.nvim',
  opts = {},
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-treesitter/nvim-treesitter',
    'scalameta/nvim-metals',
  },
}
```

Call `require('scala-hints').setup()` after loading dependencies. Ensure Metals is configured and attaches to your Scala buffers so the hover requests succeed.

### Configuration

```lua
require('scala-hints').setup({
  hover = {
    timeouts_ms = { 400, 1000, 2000 },
    log_misses = true,
  },
})
```

- `hover.timeouts_ms`: List of retry timeouts (ms) for Metals hover; each timeout triggers a retry.
- `hover.log_misses`: When `true`, logs final hover misses to `/tmp/scala-hints/log`.

## Usage

- Open a Scala file where Metals is ready.
- Diagnostics appear as hints (`Hint` severity) summarizing the code smell plus the suggested replacement.
- Use `:lua vim.lsp.buf.code_action()` or bind it to a key to see scala-hints code actions:
  ```lua
  vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, { noremap = true })
  ```
- View diagnostics with `:copen` or your diagnostic picker.
- If hints disappear after undoing, rerun diagnostics (or reopen the buffer) until the rebuild is addressed upstream.

## Roadmap & TODOs

Per [`TODO.md`](TODO.md) and the `AGENTS.md` plan:

1. **Metals resilience**: Improve the Metals wait loop and guarantee diagnostics reappear after undo.
2. **New hints**: Add `.bimap`, `.when`, `.unless`, `.exitCode`, `.delay`, `.foreach` / `.foreachPar`, `.tap`, `.tapError`, `.tapBoth`, and a dedicated `*>` (zipRight) hint.
3. **Placeholder completion**: Replace the `exit_code*` and `zio_die` entries with fully verified implementations.
4. **Inspiration**: Look to the IntelliJ ZIO plugin for new diagnostics and best practices (https://plugins.jetbrains.com/plugin/13820-zio-for-intellij/features).

## Metrics & Limitations

- **Total LOC**: 1,557 lines across six Lua modules.
- **Query core**: `lua/scala-hints/query.lua` carries ~1,135 lines focused on Treesitter logic.
- **Patterns**: 24 total, 20 active hints, 4 placeholders pending implementation.
- **Tests**: None yet—manual verification required via Neovim and Metals.
- **Limitations**: Strict reliance on literal `ZIO` identifiers, no caching, possible false positives where handlers skip Metals validation, and the entire plugin is still a learning sandbox.

## Troubleshooting

- Ensure Metals attaches quickly—the plugin waits for the `User MetalsReady` (and `MetalsInitialized`) autocommands before registering its hints, so Metals must signal readiness for diagnostics/actions to appear.
- Large files rerun all queries per invocation; consider future caching to reduce CPU pressure.
- When false positives surface, inspect `AGENTS.md` to understand whether the handler consults Metals (`utils.hover_node_and_match`) or not.

## Contributing

1. Read `AGENTS.md` for the full pattern catalog, architecture narrative, and pattern addition checklist.
2. Use Treesitter's `:InspectTree` to understand the AST shape you want to target.
3. Add your handler to `lua/scala-hints/query.lua`, register it in `diagnostics.lua` and `actions.lua`, and document it in `AGENTS.md`.
4. Validate manually by opening a Scala buffer, triggering the hint, and applying its code action.
5. File issues/PRs describing the diagnostic, type expectations, and any Metals hover requirements.

## References

- [ZIO Documentation](https://zio.dev/)
- [IntelliJ ZIO Plugin (Igal Tabachnik)](https://plugins.jetbrains.com/plugin/13820-zio-for-intellij/features)
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- [nvim-metals](https://github.com/scalameta/nvim-metals)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)

For a deeper dive into pattern internals, query flow, and future roadmap, see `AGENTS.md` and the ongoing TODO list.
