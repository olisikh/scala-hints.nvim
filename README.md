# scala-hints.nvim

Opinionated Neovim diagnostics + quickfix code actions for **ZIO**, **Cats-Effect (IO/Resource)**, and **Cats tagless-final (F[_])** Scala code.

## Demo

<video src="https://github.com/olisikh/scala-hints.nvim/raw/main/media/demo.mp4" controls="controls" style="max-width: 100%;"></video>

*The video shows diagnostics appearing and being applied via code actions.*

## Features

- **90 Treesitter patterns** detecting common effect code smells with idiomatic replacements
  - 35 ZIO patterns
  - 40 Cats-Effect patterns  
  - 15 Cats tagless-final patterns
- **Native diagnostics & code actions** via `vim.diagnostic.set()` and LSP handler
- **Metals-aware** — type verification ensures replacements only apply to actual effect types
- **Evidence-gated** — tagless-final patterns verify typeclass bounds in enclosing `def` signatures
- **Configurable severity** — set each pattern as `HINT`, `INFO`, `WARN`, `ERROR`, or `OFF`

## Requirements

- Neovim 0.11+
- [nvim-metals](https://github.com/scalameta/nvim-metals)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)

## Installation

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

## Usage

1. Open a Scala file with Metals running
2. Diagnostics appear automatically (default: `HINT` severity)
3. Apply fixes via `:lua vim.lsp.buf.code_action()` or your keymap

### Commands

| Command | Description |
| --- | --- |
| `:ScalaHintsApplyBuffer` | Apply all fixes in the current buffer |

## Configuration

```lua
require('scala-hints').setup({
  diagnostics = {
    default_severity = 'HINT',
    overrides = {
      ['zio/zip_left_value'] = 'OFF',
      ['zio/zio_die'] = 'WARN',
    },
  },
})
```

See [Configuration](https://github.com/olisikh/scala-hints.nvim/wiki/2.-Configuration) for all options.

## Documentation

Full documentation is available on the [Wiki](https://github.com/olisikh/scala-hints.nvim/wiki):

## Troubleshooting

- **No diagnostics?** Wait for Metals to initialize (`MetalsReady` / `MetalsInitialized`)
- **Diagnostics disappear after undo?** Reopen the buffer or save to refresh

## Contributing

See [AGENTS.md](AGENTS.md) for architecture details and the pattern addition guide.

## References

- [ZIO Documentation](https://zio.dev/)
- [Cats-Effect Documentation](https://typelevel.org/cats-effect/)
- [IntelliJ ZIO Plugin](https://plugins.jetbrains.com/plugin/13820-zio-for-intellij/features)
- [nvim-metals](https://github.com/scalameta/nvim-metals)
