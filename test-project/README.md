# scala-hints Test Project

A minimal Scala 3 SBT project containing intentional code smells to test the scala-hints.nvim plugin.

## Purpose

This project provides real Scala code that triggers all 90 patterns implemented in scala-hints.nvim:
- **35 ZIO patterns** in `ZioSmells.scala`
- **40 Cats-Effect patterns** in `CatsEffectSmells.scala`
- **15 Cats tagless-final patterns** in `CatsTaglessSmells.scala`

## Setup

### Prerequisites

- sbt 1.10+
- Scala 3.3+
- Neovim 0.11+
- nvim-metals plugin

### Running

1. Open the project in Neovim:
   ```bash
   cd test-project
   nvim src/main/scala/smells/ZioSmells.scala
   ```

2. Wait for Metals to initialize (check `:LspInfo`)

3. Diagnostics should appear on each smell pattern

4. Use `:lua vim.lsp.buf.code_action()` to see suggested fixes

## Files

| File | Patterns | Description |
|------|----------|-------------|
| `ZioSmells.scala` | 35 | ZIO 2.x effect patterns |
| `CatsEffectSmells.scala` | 40 | Cats-Effect 3 IO/Resource patterns |
| `CatsTaglessSmells.scala` | 15 | Tagless-final F[_] patterns with typeclass evidence |

## Adding New Smells

When implementing a new pattern in scala-hints.nvim:

1. Add the smell to the appropriate file:
   - ZIO → `ZioSmells.scala`
   - Cats-Effect → `CatsEffectSmells.scala`
   - Cats tagless-final → `CatsTaglessSmells.scala`

2. Follow the existing format:
   ```scala
   // pattern_name: detection code -> replacement
   def smellN = /* code that triggers the pattern */
   ```

3. For Cats tagless-final patterns, include the required typeclass evidence:
   ```scala
   def smellN[F[_]: Monad](fa: F[Int]): F[String] =
     /* code that triggers the pattern */
   ```

## Verifying Patterns

To verify all patterns work:

1. Open each smells file in Neovim
2. Check that diagnostics appear on each smell
3. Verify code actions suggest the correct replacement
4. Apply the fix and confirm it compiles
