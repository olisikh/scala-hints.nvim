## Neovim plugin that (hopefully) helps writing better ZIO code in Scala 

### DISCLAIMER
I'm not an expert in Treesitter, LSP, nor am I an expert in Lua; I'm just learning and 
trying to have fun while doing something useful for myself.

The goal of this project is to deliver some opinionated diagnostics and quickfix code actions 
for ZIO code written in Scala. Because I love working with ZIO and want to address code smells related to it, 
I decided to cover ZIO code smells first.

Treat this plugin as a sandbox for now; use it at your own risk.

### Usage

No configuration is required, relying on Metals LSP to help figure out information about the types here and there. 
You likely already have all the dependency plugins installed.

Lazy:
```lua
{
  'alisiikh/scala-hints.nvim', 
  opts = {},
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-treesitter/nvim-treesitter',
    'scalameta/nvim-metals',
    'nvimtools/none-ls.nvim' 
  }
}
```
