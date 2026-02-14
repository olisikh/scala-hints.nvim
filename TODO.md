# TODO: IntelliJ ZIO Plugin Parity Roadmap

## Completed (20 patterns - ✅)
- ✅ `.unit` (from `.succeed(())`, `.map(_ => ())`, `.as(())`)
- ✅ `.ignore` (from `.catchAll(_ => ZIO.unit)`, `.foldCause(...)`)
- ✅ `.as` / `.zipRight` (from `*> ZIO.succeed(v)`, `.flatMap(_ => v)`, `.map(_ => v)`)
- ✅ `.zipLeft` (from `.tap(...) not used`)
- ✅ `ZIO.none` / `ZIO.some` / `ZIO.left` / `ZIO.right`
- ✅ `ZIO.foreach` (from `ZIO.collectAll(coll.map(f))`)
- ✅ `ZIO.die` (from `ZIO.fail(ex).orDie`)
- ✅ `.orElseFail` (from `.mapError(...)`, `.orElse(ZIO.fail(...))`, `.flatMapError(...)`)
- ✅ `ZIO.succeed(())` → `ZIO.unit`
- ✅ Type aliases: `ZIO[Any, Nothing, A]` → `UIO[A]`, `ZLayer[Any, Nothing, A]` → `ULayer[A]`

## High Priority - Missing Low-Complexity Patterns

### 1. `.delay` Pattern
```scala
// Detect:
ZIO.sleep(d) *> effect
effect.flatMap(_ => otherEffect) where one is sleep

// Suggest:
effect.delay(d)
```
- **Complexity**: Low 🟢
- **Testing**: Pure pattern matching (no LSP required)
- **Files to update**: `queries.lua`, `pure_queries_spec.lua`
- **Status**: ⭕ Not Started

### 2. `.provideLayer` Pattern
```scala
// Detect:
layer.build.use(effect.provide(...))
effect.provideLayer(layer)

// Suggest:
effect.provideLayer(layer)
```
- **Complexity**: Low 🟢
- **Testing**: Pure pattern matching
- **Files to update**: `queries.lua`, `pure_queries_spec.lua`
- **Status**: ⭕ Not Started

### 3. `.toLayer` Pattern
```scala
// Detect:
ZLayer.fromEffect(effect)  // deprecated

// Suggest:
effect.toLayer
```
- **Complexity**: Low 🟢
- **Testing**: Pure pattern matching
- **Files to update**: `queries.lua`, `pure_queries_spec.lua`
- **Status**: ⭕ Not Started

### 4. `ZIO.service[A]` Pattern
```scala
// Detect:
ZIO.access(_.get)
ZIO.access(identity)

// Suggest:
ZIO.service[A]
```
- **Complexity**: Low-Medium 🟡
- **Testing**: LSP-dependent (needs type from Metals hover)
- **Files to update**: `queries.lua`, `lsp_queries_spec.lua`
- **Status**: ⭕ Not Started

## Medium Priority - Missing Medium-Complexity Patterns

### 5. `.bimap` Pattern
```scala
// Detect:
effect.map(okFn).mapError(errFn)
effect.mapError(errFn).map(okFn)

// Suggest:
effect.bimap(errFn, okFn)
```
- **Complexity**: Medium 🟡
- **Testing**: Pure pattern matching
- **Files to update**: `queries.lua`, `pure_queries_spec.lua`
- **Status**: ⭕ Not Started

### 6. `.tap` / `.tapError` / `.tapBoth` Patterns
```scala
// Detect:
effect.map(v => { doSideEffect(v); v })
effect.mapError(e => { doSideEffect(e); e })

// Suggest:
effect.tap(doSideEffect)
effect.tapError(doSideEffect)
effect.tapBoth(doSideEffect, doSideEffect)
```
- **Complexity**: Medium 🟡
- **Testing**: Pure pattern matching
- **Files to update**: `queries.lua`, `pure_queries_spec.lua`
- **Status**: ⭕ Not Started

### 7. `.when` / `.unless` Patterns
```scala
// Detect:
if (condition) effect else ZIO.unit
if (!condition) effect else ZIO.unit

// Suggest:
effect.when(condition)
effect.unless(condition)
```
- **Complexity**: Medium 🟡
- **Testing**: Pure pattern matching
- **Files to update**: `queries.lua`, `pure_queries_spec.lua`
- **Status**: ⭕ Not Started

### 8. `.foreachParN` Pattern
```scala
// Detect:
ZIO.foreachPar(collection)(f)

// Suggest:
ZIO.foreachParN(n)(collection)(f)
// with note: specify desired degree of parallelism
```
- **Complexity**: Medium 🟡
- **Testing**: Pure pattern matching
- **Files to update**: `queries.lua`, `pure_queries_spec.lua`
- **Status**: ⭕ Not Started

## Low Priority - Complete Placeholder Implementations

### 9. `.exitCode` Variants (Placeholder)
```scala
// Variants:
exit_code: .map(_ => ExitCode.success)
exit_code2: .as(ExitCode.success)
exit_code3: .fold(_, _) returning ExitCode

// Suggest:
.exitCode
```
- **Complexity**: Low 🟢
- **Testing**: Pure pattern matching
- **Files to update**: `queries.lua`, `pure_queries_spec.lua`
- **Status**: 🔄 Placeholder (needs implementation)

## Lower Priority - Advanced/High-Complexity Patterns

### 10. Type Mode Detection (CanFail, NeedsEnv)
```scala
// CanFail: Using failable operations on infallible ZIO
// Detect: uio.flatMap(UIO.catchAll(...))

// NeedsEnv: Using `.provide*` on effects not requiring environment
// Detect: zio.provideSomeLayer(...) where zio doesn't use Env
```
- **Complexity**: High 🔴
- **Testing**: LSP-dependent (needs type inference from Metals)
- **Status**: ⭕ Not Started (defer to phase 2)

### 11. If-Guard Detection in For-Comprehension
```scala
// Detect: patterns that throw in for-comprehension guards
// Suggest: Use filter or checked operations instead
```
- **Complexity**: High 🔴
- **Status**: ⭕ Not Started (defer to phase 2)

### 12. Wrapping Option/Future/Try/Either in ZIO
```scala
// Detect: pattern matching or method calls that convert types
// Suggest: ZIO.from* equivalents
```
- **Complexity**: High 🔴
- **Status**: ⭕ Not Started (defer to phase 2)

### 13. Yield Effect in For-Comprehension
```scala
// Detect: yielding a ZIO effect without flatMapping
// Suggest: flatten or appropriate combinator
```
- **Complexity**: High 🔴
- **Status**: ⭕ Not Started (defer to phase 2)

## Known Limitations & Issues

1. **Metals Indexing**: Diagnostics only appear after Metals finishes indexing a file. Workaround: edit another file to trigger re-indexing. (Not a plugin issue.)
2. **Diagnostics Refresh**: Diagnostics sometimes don't refresh after undo. (Tracked; causes investigation needed.)
3. **Whitespace Sensitivity**: Some queries don't match across newlines (e.g., `ZIO\n.unit`). (Known limitation; would benefit from query refactoring.)
4. **No Alias Support**: Patterns match literal names only (e.g., `ZIO`); not recognized when aliased or renamed imports. (Potential future enhancement.)

## Implementation Checklist

- [ ] High Priority Phase 1 (Low-complexity patterns)
  - [ ] `.delay`
  - [ ] `.provideLayer`
  - [ ] `.toLayer`
  - [ ] `ZIO.service`
  
- [ ] High Priority Phase 2 (Medium-complexity patterns)
  - [ ] `.bimap`
  - [ ] `.tap` / `.tapError` / `.tapBoth`
  - [ ] `.when` / `.unless`
  - [ ] `.foreachParN`
  
- [ ] Medium Priority (Complete placeholders)
  - [ ] `.exitCode` variants
  
- [ ] Lower Priority (Defer to later phases)
  - [ ] CanFail / NeedsEnv type modes
  - [ ] If-guard detection
  - [ ] Type wrapping (Option/Future/Try/Either)
  - [ ] Yield in for-comprehension

## References
- IntelliJ ZIO Plugin: https://plugins.jetbrains.com/plugin/13820-zio-for-intellij/features
- ZIO Documentation: https://zio.dev/
- Treesitter Query Language: https://tree-sitter.github.io/tree-sitter/using-parsers#query-syntax
