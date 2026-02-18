# Configuration

This page documents all configuration options for `scala-hints.nvim`.

## Quick Reference

```lua
require('scala-hints').setup({
  logging = {
    enabled = false,           -- Enable file logging
    level = 'INFO',            -- Log level: debug|info|warn|error
  },
  type_definition = {
    timeouts_ms = { 400, 1000, 2000 },  -- Retry schedule (ms)
    max_inflight = 4,                    -- Max concurrent LSP requests
  },
  diagnostics = {
    default_severity = 'HINT',  -- Default severity for all patterns
    overrides = {},             -- Per-pattern severity overrides
    excluded_libs = {},         -- Libraries to exclude from diagnostics
  },
  actions = {
    excluded_libs = {},         -- Libraries to exclude from code actions
  },
})
```

---

## Configuration Sections

### logging

Controls file-based logging for debugging.

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | boolean | `false` | Enable file logging to disk |
| `level` | string | `'INFO'` | Minimum log level: `debug`, `info`, `warn`, `error` (case-insensitive) |

**Example:**

```lua
logging = {
  enabled = true,
  level = 'DEBUG',  -- Most verbose
}
```

**When to use:**

- Enable `DEBUG` level when reporting issues or investigating why patterns aren't matching
- Use `INFO` level for general operation visibility
- Log files are written to Neovim's standard cache directory

---

### type_definition

Configures how the plugin queries Metals for type verification via `textDocument/typeDefinition`.

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `timeouts_ms` | number[] | `{ 400, 1000, 2000 }` | Retry schedule in milliseconds |
| `max_inflight` | number | `4` | Maximum concurrent requests per buffer |

**Example:**

```lua
type_definition = {
  timeouts_ms = { 800, 2000, 4000 },  -- More patient retry schedule
  max_inflight = 2,                   -- Fewer concurrent requests
}
```

**How retries work:**

The plugin attempts type definition lookups with exponential backoff. If the first attempt times out at 400ms, it retries with a 1000ms timeout, then 2000ms. Adjust these values if Metals is slow to respond on large codebases.

**When to adjust:**

- **Slow Metals**: Increase `timeouts_ms` values
- **Large codebases**: Reduce `max_inflight` to avoid overwhelming Metals
- **Fast machines**: Decrease `timeouts_ms` for quicker feedback

---

### diagnostics

Controls how patterns appear as Neovim diagnostics.

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `default_severity` | string | `'HINT'` | Default severity for all patterns |
| `overrides` | table | `{}` | Per-pattern severity overrides |
| `excluded_libs` | string[] | `{}` | Libraries to exclude from diagnostics |

**Example:**

```lua
diagnostics = {
  default_severity = 'INFO',
  overrides = {
    ['zio/zio_die'] = 'WARN',           -- Elevate severity
    ['zio/zip_left_value'] = 'OFF',     -- Disable pattern
    ['cats-effect/map_unit'] = 'ERROR', -- Make critical
  },
  excluded_libs = { 'cats' },           -- Exclude tagless-final patterns
}
```

#### Severity Levels

| Level | Description | Use Case |
| --- | --- | --- |
| `HINT` | Subtle suggestion | Minor style improvements (default) |
| `INFO` | Informational | Worth knowing about |
| `WARN` | Warning | Code that works but should be changed |
| `ERROR` | Error | Critical issues that need attention |
| `OFF` | Disabled | Completely disable a pattern |

---

### actions

Controls code action availability.

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `excluded_libs` | string[] | `{}` | Libraries to exclude from code actions |

**Example:**

```lua
actions = {
  excluded_libs = { 'cats', 'cats-effect' },  -- Only ZIO code actions
}
```

---

## Per-Pattern Severity Overrides

Each pattern can be individually configured using its fully-qualified name: `lib/pattern_name`.

### Pattern Naming Convention

| Library | Prefix | Example |
| --- | --- | --- |
| ZIO | `zio/` | `zio/succeed_unit`, `zio/map_value` |
| Cats-Effect | `cats-effect/` | `cats-effect/map_unit`, `cats-effect/from_option` |
| Cats Tagless-Final | `cats/` | `cats/map_unit`, `cats/flat_tap` |

### Common Override Patterns

**Disable noisy patterns:**

```lua
diagnostics = {
  overrides = {
    ['zio/zip_left_value'] = 'OFF',
    ['zio/zip_right_operator'] = 'OFF',
    ['cats/product_l'] = 'OFF',
  },
}
```

**Elevate critical patterns:**

```lua
diagnostics = {
  overrides = {
    ['zio/zio_die'] = 'WARN',
    ['zio/catch_all_unit'] = 'WARN',
    ['cats-effect/handle_error'] = 'WARN',
  },
}
```

**Type alias patterns as errors (enforce type aliases):**

```lua
diagnostics = {
  overrides = {
    ['zio/zio_type'] = 'ERROR',
    ['zio/zlayer_type'] = 'ERROR',
  },
}
```

### Finding Pattern Names

See [[Patterns]] for the complete pattern catalog. Pattern names are also visible in:

1. Diagnostic messages (hover over the diagnostic)
2. Code action titles (when applying fixes)
3. Log output (when logging is enabled at `DEBUG` level)

---

## Library Exclusion

Exclude entire libraries from diagnostics or code actions for performance or preference.

### Available Libraries

| Library | Name | Patterns | Type Verification |
| --- | --- | --- | --- |
| ZIO | `"zio"` | 35 | Metals LSP |
| Cats-Effect | `"cats-effect"` | 36 | Metals LSP |
| Cats Tagless-Final | `"cats"` | 15 | Local evidence detection |

### Exclusion Examples

**Only use ZIO patterns:**

```lua
require('scala-hints').setup({
  diagnostics = { excluded_libs = { 'cats', 'cats-effect' } },
  actions = { excluded_libs = { 'cats', 'cats-effect' } },
})
```

**Only use Cats-Effect patterns:**

```lua
require('scala-hints').setup({
  diagnostics = { excluded_libs = { 'zio', 'cats' } },
  actions = { excluded_libs = { 'zio', 'cats' } },
})
```

**Exclude tagless-final patterns (no F[_] code):**

```lua
require('scala-hints').setup({
  diagnostics = { excluded_libs = { 'cats' } },
  actions = { excluded_libs = { 'cats' } },
})
```

### Separate Diagnostics and Actions

You can exclude a library from diagnostics but keep its code actions:

```lua
require('scala-hints').setup({
  diagnostics = { excluded_libs = { 'cats' } },  -- No diagnostics for cats
  actions = { excluded_libs = {} },              -- But code actions still work
})
```

---

## Complete Configuration Examples

### Minimal Configuration

```lua
require('scala-hints').setup()
```

Uses all defaults: `HINT` severity, all libraries enabled, no logging.

### Recommended for ZIO Projects

```lua
require('scala-hints').setup({
  logging = {
    enabled = true,
    level = 'INFO',
  },
  diagnostics = {
    default_severity = 'HINT',
    overrides = {
      ['zio/zio_die'] = 'WARN',
      ['zio/zio_type'] = 'INFO',
      ['zio/zlayer_type'] = 'INFO',
    },
    excluded_libs = { 'cats', 'cats-effect' },
  },
  actions = {
    excluded_libs = { 'cats', 'cats-effect' },
  },
})
```

### Recommended for Cats-Effect Projects

```lua
require('scala-hints').setup({
  logging = {
    enabled = true,
    level = 'INFO',
  },
  diagnostics = {
    default_severity = 'HINT',
    excluded_libs = { 'zio', 'cats' },
  },
  actions = {
    excluded_libs = { 'zio', 'cats' },
  },
})
```

### Strict Mode (All Patterns as WARN)

```lua
require('scala-hints').setup({
  diagnostics = {
    default_severity = 'WARN',
    overrides = {
      ['zio/zip_left_value'] = 'OFF',      -- Subjective preference
      ['zio/zip_right_operator'] = 'OFF',  -- Subjective preference
    },
  },
})
```

### Debug Mode (Maximum Logging)

```lua
require('scala-hints').setup({
  logging = {
    enabled = true,
    level = 'DEBUG',
  },
  type_definition = {
    timeouts_ms = { 1000, 2000, 4000 },  -- Patient timeouts
    max_inflight = 2,
  },
})
```

---

## Troubleshooting Configuration

### Diagnostics Not Appearing

1. **Check severity**: Ensure `default_severity` isn't `OFF` and patterns aren't overridden to `OFF`
2. **Check library exclusion**: Verify your library isn't in `excluded_libs`
3. **Enable logging**: Set `logging.enabled = true` and `logging.level = 'DEBUG'`

### Too Many Diagnostics

1. **Lower default severity**: Set `default_severity = 'HINT'`
2. **Disable specific patterns**: Add to `overrides` with `'OFF'`
3. **Exclude unused libraries**: Add to `excluded_libs`

### Metals Timeout Errors

1. **Increase timeouts**:
   ```lua
   type_definition = {
     timeouts_ms = { 800, 2000, 4000 },
   }
   ```
2. **Reduce concurrency**:
   ```lua
   type_definition = {
     max_inflight = 2,
   }
   ```

### Performance Issues on Large Files

1. **Exclude unused libraries**:
   ```lua
   diagnostics = { excluded_libs = { 'cats' } },
   actions = { excluded_libs = { 'cats' } },
   ```
2. **Disable expensive patterns**:
   ```lua
   diagnostics = {
     overrides = {
       ['zio/zio_type'] = 'OFF',
       ['zio/zlayer_type'] = 'OFF',
     },
   }
   ```

---

## Related Pages

- [[Installation]] — Setup and installation instructions
- [[Patterns]] — Complete pattern catalog
- [[Troubleshooting]] — General troubleshooting guide
