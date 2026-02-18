# Contributing

Thank you for your interest in contributing to `scala-hints.nvim`! This guide covers everything you need to get started.

## Development Setup

### Prerequisites

- **Neovim 0.11+**
- **Git**
- A Scala project with Metals LSP configured (for integration testing)

### Clone and Setup

```bash
git clone https://github.com/olisikh/scala-hints.nvim.git
cd scala-hints.nvim
```

### Running Tests

Tests use `plenary.nvim`'s busted-compatible test framework. Run the full test suite:

```bash
make test
```

Run specific test categories:

```bash
# ZIO query tests
make test-zio

# Cats-Effect query tests
make test-cats-effect

# Cats tagless-final query tests
make test-cats

# All library query tests
make test-libs

# Query engine tests
make test-engine
```

Or run individual test files:

```bash
nvim --headless --clean -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/zio/queries_spec.lua {minimal_init = 'tests/minimal_init.lua'}"
```

### Project Structure

```
scala-hints.nvim/
├── lua/scala-hints/
│   ├── init.lua              # Entry point
│   ├── diagnostics.lua       # Diagnostic collection
│   ├── actions.lua           # Code action resolution
│   ├── query.lua             # Treesitter query engine
│   ├── semantic.lua          # LSP type verification
│   ├── client.lua            # In-process LSP client
│   ├── libs/
│   │   ├── init.lua          # Library registry
│   │   ├── zio/              # ZIO patterns
│   │   ├── cats-effect/      # Cats-Effect patterns
│   │   └── cats/             # Cats tagless-final patterns
│   └── cats/
│       └── evidence.lua      # Typeclass evidence detection
└── tests/
    ├── helpers/              # Test utilities
    ├── zio/                  # ZIO pattern tests
    ├── cats-effect/          # Cats-Effect pattern tests
    └── cats/                 # Cats tagless-final tests
```

## Adding a New Pattern

### Step 1: Understand the AST

Use Neovim's built-in Treesitter inspector to see the AST structure for the code you want to match:

```vim
:InspectTree
```

This opens a split showing the parsed syntax tree. Navigate to the code pattern you want to detect and note the node types and structure.

### Step 2: Choose the Target Library

Add your pattern to the appropriate queries file:

| Library | File |
|---------|------|
| ZIO | `lua/scala-hints/libs/zio/queries.lua` |
| Cats-Effect (IO/Resource) | `lua/scala-hints/libs/cats-effect/queries.lua` |
| Cats tagless-final (F[_]) | `lua/scala-hints/libs/cats/queries.lua` |

### Step 3: Write the Treesitter Query

Add a new entry to the queries table with:

- **`query`**: The Treesitter S-expression pattern
- **`handler`**: Function to extract ranges and suggest replacements
- **`diagnostic_severity`** (optional): `HINT`, `INFO`, `WARN`, `ERROR`, or `OFF`

Example query for `ZIO.succeed(())` → `ZIO.unit`:

```lua
succeed_unit = {
  query = [[
    (call_expression
      function: (field_expression
        value: (_) @_zio (#eq? @_zio "ZIO")
        field: (identifier) @_succeed (#eq? @_succeed "succeed")
      )
      arguments: (arguments (unit))
    )
  ]],
  handler = function(bufnr, root, match)
    local node = match.node
    local range = { node:range() }
    return {
      {
        bufnr = bufnr,
        lnum = range[1],
        col = range[2],
        end_lnum = range[3],
        end_col = range[4],
        replacement = "ZIO.unit",
        title = "ZIO: replace ZIO.succeed(()) with ZIO.unit",
      },
    }
  end,
  diagnostic_severity = "HINT",
}
```

### Step 4: Register the Query

Add the query name to the library's init file:

- ZIO: `lua/scala-hints/libs/zio/init.lua`
- Cats-Effect: `lua/scala-hints/libs/cats-effect/init.lua`
- Cats: `lua/scala-hints/libs/cats/init.lua`

For a new library, create a module and register it in `lua/scala-hints/libs/init.lua`.

### Step 5: Add Type Verification (ZIO/Cats-Effect)

For ZIO and Cats-Effect patterns, use `semantic.type_definition_predicate` to verify the matched expression is actually a ZIO or IO type:

```lua
local semantic = require("scala-hints.semantic")

handler = function(bufnr, root, match)
  local node = match.node
  local is_zio = semantic.type_definition_predicate(bufnr, node, "is_zio_type")
  
  if not is_zio then
    return {} -- Skip if not a ZIO type
  end
  
  -- ... return diagnostics/actions
end
```

### Step 6: Add Evidence Checking (Cats tagless-final)

For Cats tagless-final patterns, use `cats/evidence.has_capability` to verify typeclass evidence:

```lua
local evidence = require("scala-hints.cats.evidence")

handler = function(bufnr, root, match)
  local node = match.node
  local has_monad = evidence.has_capability(bufnr, node, "Monad")
  
  if not has_monad then
    return {} -- Skip if no Monad evidence
  end
  
  -- ... return diagnostics/actions
end
```

### Step 7: Write Tests

Add tests to the appropriate test file:

- ZIO: `tests/zio/queries_spec.lua`
- Cats-Effect: `tests/cats-effect/queries_spec.lua`
- Cats: `tests/cats/queries_spec.lua`

For LSP-dependent handlers, mock the type definition predicate:

```lua
local H = require("tests.helpers")

describe("my_new_pattern", function()
  before_each(function()
    H.mock_type_definition_predicate(true) -- Mock LSP to return true
  end)

  after_each(function()
    H.restore_mocks()
  end)

  it("matches the pattern and suggests replacement", function()
    local source = [[val x = ZIO.succeed(())]]
    local bufnr, root = H.parse_scala(source)

    local ready, pending = H.run_handler(bufnr, root, queries.my_new_pattern)
    local results = H.resolve_pending(pending)

    assert.are.equal(1, #results)
    H.assert_result(results[1], {
      replacement = "ZIO.unit",
    })
  end)
end)
```

### Step 8: Update Documentation

Update the pattern catalog in `AGENTS.md` with your new pattern.

## Testing Guidelines

### Test Structure

Each pattern should have tests covering:

1. **Positive cases**: Code that should match and trigger the diagnostic/action
2. **Negative cases**: Similar code that should NOT match
3. **Edge cases**: Whitespace variations, nested expressions, etc.

### Test Helpers

The `tests/helpers` module provides utilities:

```lua
local H = require("tests.helpers")

-- Parse Scala source and return buffer + root node
local bufnr, root = H.parse_scala("val x = ZIO.succeed(())")

-- Run a handler and get ready/pending results
local ready, pending = H.run_handler(bufnr, root, queries.my_pattern)

-- Resolve pending async results
local results = H.resolve_pending(pending)

-- Assert a result matches expected fields
H.assert_result(results[1], {
  replacement = "ZIO.unit",
  title = "ZIO: replace ZIO.succeed(()) with ZIO.unit",
})

-- Cleanup
H.cleanup_buf(bufnr)
```

### Mocking LSP

For handlers that require Metals type verification:

```lua
before_each(function()
  H.mock_type_definition_predicate(true)  -- Always return true
  -- or
  H.mock_type_definition_predicate(false) -- Always return false
end)

after_each(function()
  H.restore_mocks()
end)
```

## Pull Request Process

### Before Submitting

1. **Run all tests**: `make test`
2. **Test manually**: Open a Scala file with Metals and verify your pattern works
3. **Check edge cases**: Ensure your pattern doesn't produce false positives
4. **Update documentation**: Add your pattern to `AGENTS.md`

### PR Guidelines

- **One pattern per PR**: Keep changes focused and reviewable
- **Clear description**: Explain what pattern you're adding and why it's useful
- **Link issues**: Reference any related issues
- **Include tests**: All new patterns must have test coverage

### PR Template

```markdown
## Description
[What pattern does this add/fix?]

## Pattern Details
- **Detection**: [Code that triggers the hint]
- **Replacement**: [Suggested replacement]
- **Library**: [ZIO / Cats-Effect / Cats]

## Testing
- [ ] Unit tests added/updated
- [ ] Manual testing with Metals
- [ ] Documentation updated

## Example

Before:
```scala
ZIO.succeed(())
```

After:
```scala
ZIO.unit
```
```

## Getting Help

- Open an issue for bugs or feature requests
- Check existing patterns in `libs/*/queries.lua` for examples
- Refer to [AGENTS.md](../AGENTS.md) for architecture details
