# Installation

This guide covers installing and configuring `scala-hints.nvim` for Neovim.

## Requirements

| Requirement | Version | Purpose |
|-------------|---------|---------|
| **Neovim** | 0.11+ | Core editor with LSP and diagnostic support |
| **Metals** | Latest | Scala LSP server for type verification |
| **nvim-treesitter** | Latest | Scala parser for AST matching |
| **plenary.nvim** | Latest | Async utilities |

### Verifying Requirements

```vim
" Check Neovim version
:version
" Should show v0.11.0 or higher

" Check if Treesitter Scala parser is installed
:TSInstallInfo
" Should show scala installed

" Check if Metals is running
:LspInfo
" Should show metals attached to Scala buffers
```

## Installation

### lazy.nvim (Recommended)

```lua
{
  'olisikh/scala-hints.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'scalameta/nvim-metals',
  },
  opts = {}, -- uses default configuration
}
```

With custom configuration:

```lua
{
  'olisikh/scala-hints.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'scalameta/nvim-metals',
  },
  opts = {
    logging = {
      enabled = true,
      level = 'INFO',
    },
    diagnostics = {
      default_severity = 'HINT',
      overrides = {
        ['zio/zio_die'] = 'WARN',
      },
    },
  },
}
```

### packer.nvim

```lua
use {
  'olisikh/scala-hints.nvim',
  requires = {
    'nvim-lua/plenary.nvim',
    'scalameta/nvim-metals',
  },
  config = function()
    require('scala-hints').setup({
      logging = {
        enabled = true,
        level = 'INFO',
      },
    })
  end,
}
```

### vim-plug

```vim
" Required dependencies
Plug 'nvim-lua/plenary.nvim'
Plug 'scalameta/nvim-metals'

" scala-hints.nvim
Plug 'olisikh/scala-hints.nvim'
```

Then add to your `init.vim` or a separate Lua config file:

```lua
" In init.vim (if using Vimscript)
lua require('scala-hints').setup()

" Or in lua/config/scala-hints.lua
require('scala-hints').setup({
  logging = { enabled = true, level = 'INFO' },
})
```

## Post-Install Setup

### 1. Install Treesitter Scala Parser

```vim
:TSInstall scala
```

### 2. Configure Metals

`scala-hints.nvim` requires Metals to be running and attached to your Scala buffers. If you're using `nvim-metals`, ensure it's properly configured:

```lua
local metals_config = require('metals').bare_config()

metals_config.settings = {
  showImplicitArguments = true,
  showImplicitConversionsAndClasses = true,
  showInferredType = true,
}

-- Autocommand to start Metals
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "scala", "sbt" },
  callback = function()
    require("metals").initialize_or_attach(metals_config)
  end,
  group = vim.api.nvim_create_augroup("nvim-metals", { clear = true }),
})
```

### 3. Verify Installation

1. Open a Scala file in a project with Metals configured
2. Wait for Metals to initialize (check `:LspInfo`)
3. Write some code that matches a pattern, e.g.:

```scala
// This should trigger a hint:
ZIO.succeed(())
```

4. Check for diagnostics with `:lua vim.diagnostic.get(0)`

## Configuration Options

```lua
require('scala-hints').setup({
  -- Logging configuration
  logging = {
    enabled = false,        -- Enable file logging for debugging
    level = 'INFO',         -- Log level: debug|info|warn|error
  },

  -- Type definition LSP settings
  type_definition = {
    timeouts_ms = { 400, 1000, 2000 },  -- Retry schedule (ms)
    max_inflight = 4,                    -- Max concurrent requests per buffer
  },

  -- Diagnostic settings
  diagnostics = {
    default_severity = 'HINT',  -- Default: HINT, INFO, WARN, ERROR, OFF
    overrides = {
      -- Disable specific patterns
      ['zio/zip_left_value'] = 'OFF',
      ['zio/zip_right_operator'] = 'OFF',
      -- Elevate severity for important patterns
      ['zio/zio_die'] = 'WARN',
    },
    excluded_libs = {},  -- Exclude libraries: { "zio", "cats-effect", "cats" }
  },

  -- Code action settings
  actions = {
    excluded_libs = {},  -- Exclude libraries from code actions
  },
})
```

## Troubleshooting

### No Diagnostics Appear

**Symptoms**: No hints shown even on matching patterns.

**Solutions**:

1. **Metals not ready**: Wait for `MetalsReady` or `MetalsInitialized` event
   ```vim
   :echo g:metals_status
   ```

2. **Treesitter parser missing**:
   ```vim
   :TSInstall scala
   :TSInstallInfo
   ```

3. **Check if plugin is loaded**:
   ```lua
   :lua print(vim.inspect(package.loaded['scala-hints']))
   ```

4. **Enable logging** to see what's happening:
   ```lua
   require('scala-hints').setup({
     logging = { enabled = true, level = 'DEBUG' },
   })
   ```

### Diagnostics Disappear After Undo

**Cause**: Neovim's undo doesn't trigger a diagnostic refresh.

**Solution**: Reopen the buffer or save the file to force a refresh.

### False Positives

**Symptoms**: Hints appear on non-ZIO/Cats-Effect code.

**Cause**: Some patterns skip Metals type verification for performance.

**Solution**: Check [AGENTS.md](../AGENTS.md) for LSP-dependent patterns. Report issues with a minimal reproduction.

### Metals Timeout Errors

**Symptoms**: Errors about `textDocument/typeDefinition` timing out.

**Solutions**:

1. Increase timeout values:
   ```lua
   require('scala-hints').setup({
     type_definition = {
       timeouts_ms = { 800, 2000, 4000 },
     },
   })
   ```

2. Reduce concurrent requests:
   ```lua
   require('scala-hints').setup({
     type_definition = {
       max_inflight = 2,
     },
   })
   ```

### Performance Issues on Large Files

**Solutions**:

1. Exclude libraries you don't use:
   ```lua
   require('scala-hints').setup({
     diagnostics = { excluded_libs = { "cats" } },
     actions = { excluded_libs = { "cats" } },
   })
   ```

2. Disable specific patterns:
   ```lua
   require('scala-hints').setup({
     diagnostics = {
       overrides = {
         ['zio/zio_type'] = 'OFF',
         ['zio/zlayer_type'] = 'OFF',
       },
     },
   })
   ```

### Plugin Not Loading with lazy.nvim

**Cause**: lazy.nvim lazy-loads plugins by default.

**Solution**: Ensure dependencies are explicitly declared:
```lua
{
  'olisikh/scala-hints.nvim',
  lazy = false,  -- Load immediately (optional)
  dependencies = {
    'nvim-lua/plenary.nvim',
    'scalameta/nvim-metals',
  },
  opts = {},
}
```

## Getting Help

- **Issues**: [GitHub Issues](https://github.com/olisikh/scala-hints.nvim/issues)
- **Architecture**: See [AGENTS.md](../AGENTS.md) for technical details
- **Pattern Catalog**: See [README.md](../README.md) for all supported patterns
