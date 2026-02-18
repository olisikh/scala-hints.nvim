# scala-hints.nvim

Opinionated Neovim diagnostics + quickfix code actions for **ZIO**, **Cats-Effect**, and **Cats tagless-final** Scala code.

## Overview

This plugin detects common effect code smells in Scala and suggests idiomatic replacements. It uses Treesitter for AST pattern matching, Metals LSP for type verification, and integrates natively with Neovim's diagnostics and code-action systems.

Example transformations:

- `ZIO.succeed(())` → `ZIO.unit`
- `.map(_ => ())` → `.unit` / `.void`
- `.flatMap(_ => effect)` → `.zipRight(effect)` / `*> effect`

## Features

- **90 Treesitter patterns** across three effect libraries:
  - **35 ZIO patterns** — constructors, combinators, error handling, type aliases, timing, service access
  - **40 Cats-Effect patterns** — IO/Resource idioms, parallelism, error recovery, resource safety, console output
  - **15 Cats tagless-final patterns** — evidence-gated `F[_]` patterns (Functor, Apply, Monad, MonadError)
- **Native diagnostics** via `vim.diagnostic.set()`
- **Code actions** integrated with LSP handler
- **Metals-aware** — type definition verification ensures hints only apply to actual effect types
- **Evidence-gated** — tagless-final patterns verify typeclass bounds in enclosing `def` signatures
- **Per-query severity** — configure each pattern as `HINT`, `INFO`, `WARN`, `ERROR`, or `OFF`
- **Async** — all queries run via `plenary.async` with configurable timeouts

## Quick Start

### Requirements

- Neovim 0.11+
- Metals LSP (via nvim-metals)

### Installation

**lazy.nvim:**

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

### Minimal Setup

```lua
require('scala-hints').setup()
```

### Usage

1. Open a Scala file with Metals running
2. Diagnostics appear automatically (default: `HINT` severity)
3. Apply fixes via `:lua vim.lsp.buf.code_action()` or your keymap

### Commands

| Command | Description |
| --- | --- |
| `:ScalaHintsApplyBuffer` | Apply all scala-hints fixes in the current buffer |

The `:ScalaHintsApplyBuffer` command applies all available fixes at once. If multiple fixes overlap (e.g., a `println` fix inside a `traverse_` fix), overlapping fixes are skipped to prevent broken code. Run the command again to apply remaining fixes.

## Documentation

| Page | Description |
| --- | --- |
| [[Installation]] | Detailed installation instructions for various plugin managers |
| [[Configuration]] | Full configuration options and per-query customization |
| [[Patterns]] | Complete pattern catalog with detection rules and replacements |
| [[ZIO]] | Deep dive into ZIO 2.x patterns (35 patterns) |
| [[Cats-Effect]] | Deep dive into Cats-Effect 3.x patterns (40 patterns) |
| [[Cats-Tagless-Final]] | Deep dive into evidence-gated `F[_]` patterns (15 patterns) |
| [[Contributing]] | How to add new patterns and contribute |

## Links

- [GitHub Repository](https://github.com/olisikh/scala-hints.nvim)
- [ZIO Documentation](https://zio.dev/)
- [IntelliJ ZIO Plugin](https://plugins.jetbrains.com/plugin/13820-zio-for-intellij/features)
- [nvim-metals](https://github.com/scalameta/nvim-metals)
