# scala-hints.nvim Wiki

Welcome to the scala-hints.nvim documentation.

## Quick Links

- [[Installation]] — Setup with lazy.nvim, packer, or manual
- [[Configuration]] — All options and per-pattern customization
- [[Patterns]] — Complete pattern catalog (90 patterns)
- [[ZIO]] — ZIO 2.x patterns (35 patterns)
- [[Cats-Effect]] — IO/Resource patterns (40 patterns)
- [[Cats-Tagless-Final]] — Evidence-gated F[_] patterns (15 patterns)
- [[Contributing]] — How to add new patterns

## What This Plugin Does

Provides Neovim diagnostics and quickfix code actions for Scala effect libraries:

```scala
// ZIO examples
ZIO.succeed(())         →  ZIO.unit
.map(_ => ())           →  .unit
.catchAll(_ => ZIO.unit) →  .ignore

// Cats-Effect examples
IO(println(x))          →  IO.println(x)
io.map(_ => ())         →  io.void
```

See the [GitHub repo](https://github.com/olisikh/scala-hints.nvim) for more details.
