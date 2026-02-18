# Cats Tagless-Final Patterns

## Overview

Tagless-final is a pattern for writing polymorphic effectful code in Scala using higher-kinded types (`F[_]`). Unlike ZIO or Cats-Effect IO patterns which work with concrete effect types, tagless-final code abstracts over the effect type using typeclasses like `Functor`, `Monad`, or `Sync`.

**What makes tagless-final different:**

- **Polymorphic**: Code works with any effect type that satisfies the required typeclass constraints
- **Evidence-based**: Typeclass instances provide the required operations
- **No LSP verification needed**: Unlike ZIO/Cats-Effect patterns, evidence is detected locally from `def` signatures
- **Deferred interpretation**: The actual effect type is chosen at the edge of your application

```scala
// Tagless-final style - works with any F[_]: Sync
def program[F[_]: Sync]: F[Unit] =
  Sync[F].delay(println("Hello"))

// Can be instantiated with IO, ZIO, or any Sync
program[IO]
```

## Evidence Detection

scala-hints.nvim detects typeclass evidence from the enclosing `def` signature. Evidence can be provided in three ways:

### Context Bounds (Scala 2 & 3)

```scala
def program[F[_]: Monad]: F[Unit] = ...
def process[F[_]: Sync]: F[Result] = ...
```

### Implicit Parameters (Scala 2)

```scala
def program[F[_]](implicit F: Monad[F]): F[Unit] = ...
def process[F[_]](implicit ev: Sync[F]): F[Result] = ...
```

### Using Clauses (Scala 3)

```scala
def program[F[_]](using F: Monad[F]): F[Unit] = ...
def process[F[_]: Sync](using F: Sync[F]): F[Result] = ...
```

### How Evidence is Detected

The `cats/evidence.lua` module:

1. **Finds the enclosing `def`**: Walks up the AST from the matched pattern to find the nearest function definition
2. **Extracts the def header**: Parses everything before the first `=` or `{`
3. **Scans for context bounds**: Matches patterns like `[F[_]: TypeClass]`
4. **Scans for implicit/using params**: Matches `implicit F: TypeClass[F]` or `using F: TypeClass[F]`
5. **Caches results**: Evidence is cached per-buffer per-changedtick for performance

## Capability Lattice

Typeclasses form a hierarchy where higher typeclasses imply all lower ones:

```
Sync (7)          -- Suspending side effects, catching exceptions
    ↑
MonadError (6)    -- Raising and handling errors
    ↑
Monad (5)         -- Sequential composition (flatMap)
    ↑
Applicative (4)   -- Independent computation combination
    ↑
FlatMap (3)       -- Sequential composition without pure
    ↑
Apply (2)         -- Combining effects (map2, product)
    ↑
Functor (1)       -- Mapping over values (map)
```

**Implication rules:**

- `Sync` implies `MonadError`, `Monad`, `Applicative`, `FlatMap`, `Apply`, and `Functor`
- `MonadError` implies `Monad`, `Applicative`, `FlatMap`, `Apply`, and `Functor`
- And so on...

**Example:**

```scala
// With Sync[F], all patterns requiring Functor, Apply, Monad, or MonadError work
def program[F[_]: Sync]: F[Unit] =
  fa.map(_ => ())    // Functor pattern: detected
  fb.flatMap(_ => fc) // Apply pattern: detected
```

## Patterns

### Functor Patterns

#### `map_unit` — Discard result with void

**Detection:** `fa.map(_ => ())`

**Replacement:** `fa.void`

**Required Evidence:** Functor

```scala
// Before
def program[F[_]: Functor]: F[Unit] =
  users.map(_ => ())

// After
def program[F[_]: Functor]: F[Unit] =
  users.void
```

---

#### `map_value` — Replace result with constant

**Detection:** `fa.map(_ => value)`

**Replacement:** `fa.as(value)`

**Required Evidence:** Functor

```scala
// Before
def program[F[_]: Functor]: F[Boolean] =
  fetchUser.map(_ => true)

// After
def program[F[_]: Functor]: F[Boolean] =
  fetchUser.as(true)
```

---

### Apply Patterns

#### `flat_map_value` — Sequence and discard

**Detection:** `fa.flatMap(_ => fb)`

**Replacement:** `fa *> fb`

**Required Evidence:** Apply

```scala
// Before
def program[F[_]: Apply]: F[B] =
  logEvent.flatMap(_ => computeResult)

// After
def program[F[_]: Apply]: F[B] =
  logEvent *> computeResult
```

---

#### `product_l` — Keep left result, sequence right

**Detection:** `fa.flatMap(a => fb.as(a))` or `fa.flatMap(a => fb.map(_ => a))`

**Replacement:** `fa <* fb`

**Required Evidence:** Apply

```scala
// Before
def program[F[_]: Apply]: F[A] =
  computeValue.flatMap(a => logEvent.as(a))

// After
def program[F[_]: Apply]: F[A] =
  computeValue <* logEvent
```

---

### FlatMap Patterns

#### `flat_tap` — Side-effect and continue

**Detection:** `fa.flatMap(a => effect.as(a))`

**Replacement:** `fa.flatTap(a => effect)`

**Required Evidence:** FlatMap

```scala
// Before
def program[F[_]: FlatMap]: F[User] =
  fetchUser.flatMap(user => audit(user).as(user))

// After
def program[F[_]: FlatMap]: F[User] =
  fetchUser.flatTap(user => audit(user))
```

---

### Applicative Patterns

#### `when_a` — Conditional execution

**Detection:** `if (cond) fa else F.unit`

**Replacement:** `fa.whenA(cond)`

**Required Evidence:** Applicative

```scala
// Before
def program[F[_]: Applicative](shouldLog: Boolean): F[Unit] =
  if (shouldLog) logEvent else Applicative[F].unit

// After
def program[F[_]: Applicative](shouldLog: Boolean): F[Unit] =
  logEvent.whenA(shouldLog)
```

---

#### `unless_a` — Conditional execution (negated)

**Detection:** `if (!cond) fa else F.unit` or `if (cond) F.unit else fa`

**Replacement:** `fa.unlessA(cond)`

**Required Evidence:** Applicative

```scala
// Before
def program[F[_]: Applicative](skipValidation: Boolean): F[Unit] =
  if (!skipValidation) validate else Applicative[F].unit

// After
def program[F[_]: Applicative](skipValidation: Boolean): F[Unit] =
  validate.unlessA(skipValidation)
```

---

### Monad Patterns

#### `if_m` — Monadic conditional

**Detection:** `fb.flatMap(b => if (b) fa else fc)`

**Replacement:** `fb.ifM(fa, fc)`

**Required Evidence:** Monad

```scala
// Before
def program[F[_]: Monad]: F[Result] =
  isEnabled.flatMap(enabled =>
    if (enabled) runComputation else F.pure(defaultResult)
  )

// After
def program[F[_]: Monad]: F[Result] =
  isEnabled.ifM(runComputation, F.pure(defaultResult))
```

---

### MonadError Patterns

#### `handle_error` — Recover with fallback

**Detection:** `fa.attempt.flatMap { case Right(a) => F.pure(a); case Left(e) => F.pure(default) }`

**Replacement:** `fa.handleError(_ => default)` or `fa.handleErrorWith(e => F.pure(default(e)))`

**Required Evidence:** MonadError

```scala
// Before
def program[F[_]: MonadError[*[_], Throwable]]: F[User] =
  fetchUser.attempt.flatMap {
    case Right(user) => F.pure(user)
    case Left(_) => F.pure(User.default)
  }

// After
def program[F[_]: MonadError[*[_], Throwable]]: F[User] =
  fetchUser.handleError(_ => User.default)
```

---

#### `raise_when` — Conditional error

**Detection:** `if (cond) F.raiseError(err) else F.unit`

**Replacement:** `F.raiseWhen(cond)(err)`

**Required Evidence:** MonadError

```scala
// Before
def program[F[_]: MonadError[*[_], Error]](invalid: Boolean): F[Unit] =
  if (invalid) F.raiseError(ValidationError) else F.unit

// After
def program[F[_]: MonadError[*[_], Error]](invalid: Boolean): F[Unit] =
  F.raiseWhen(invalid)(ValidationError)
```

---

#### `raise_unless` — Guard with error

**Detection:** `if (cond) F.unit else F.raiseError(err)`

**Replacement:** `F.raiseUnless(cond)(err)`

**Required Evidence:** MonadError

```scala
// Before
def program[F[_]: MonadError[*[_], Error]](valid: Boolean): F[Unit] =
  if (valid) F.unit else F.raiseError(ValidationError)

// After
def program[F[_]: MonadError[*[_], Error]](valid: Boolean): F[Unit] =
  F.raiseUnless(valid)(ValidationError)
```

---

#### `from_option` — Lift Option to F

**Detection:** `opt.fold(F.raiseError(err))(F.pure)`

**Replacement:** `F.fromOption(opt)(err)`

**Required Evidence:** MonadError

```scala
// Before
def program[F[_]: MonadError[*[_], Error]]: F[User] =
  findUser.fold(F.raiseError(UserNotFound))(F.pure)

// After
def program[F[_]: MonadError[*[_], Error]]: F[User] =
  F.fromOption(findUser)(UserNotFound)
```

---

#### `from_either` — Lift Either to F

**Detection:** `either.fold(F.raiseError, F.pure)`

**Replacement:** `F.fromEither(either)`

**Required Evidence:** MonadError

```scala
// Before
def program[F[_]: MonadError[*[_], Throwable]]: F[Result] =
  validateInput.fold(F.raiseError, F.pure)

// After
def program[F[_]: MonadError[*[_], Throwable]]: F[Result] =
  F.fromEither(validateInput)
```

---

#### `redeem` — Handle both success and failure

**Detection:** `fa.attempt.map { case Right(a) => f(a); case Left(e) => g(e) }`

**Replacement:** `fa.redeem(g, a => f(a))`

**Required Evidence:** MonadError

```scala
// Before
def program[F[_]: MonadError[*[_], Throwable]]: F[String] =
  fetchUser.attempt.map {
    case Right(user) => s"Found: ${user.name}"
    case Left(err) => s"Error: ${err.getMessage}"
  }

// After
def program[F[_]: MonadError[*[_], Throwable]]: F[String] =
  fetchUser.redeem(
    err => s"Error: ${err.getMessage}",
    user => s"Found: ${user.name}"
  )
```

---

#### `redeem_with` — Handle both with effectful recovery

**Detection:** `fa.attempt.flatMap { case Right(a) => fb; case Left(e) => fc(e) }`

**Replacement:** `fa.redeemWith(fc, a => fb)`

**Required Evidence:** MonadError

```scala
// Before
def program[F[_]: MonadError[*[_], Throwable]]: F[User] =
  fetchFromCache.attempt.flatMap {
    case Right(user) => F.pure(user)
    case Left(_) => fetchFromDatabase
  }

// After
def program[F[_]: MonadError[*[_], Throwable]]: F[User] =
  fetchFromCache.redeemWith(
    _ => fetchFromDatabase,
    user => F.pure(user)
  )
```

---

## Full Examples

### Service Layer

```scala
trait UserService[F[_]] {
  def findById(id: UserId): F[Option[User]]
  def create(user: User): F[Unit]
  def delete(id: UserId): F[Unit]
}

object UserService {
  def impl[F[_]: Sync](repo: UserRepository[F]): UserService[F] = new UserService[F] {
    
    def findById(id: UserId): F[Option[User]] =
      repo.find(id)
        .flatTap(user => Sync[F].delay(println(s"Found: $user")))
        
    def create(user: User): F[Unit] =
      validateUser(user)
        .flatMap(repo.save)
        .handleError(_ => ())
        
    def delete(id: UserId): F[Unit] =
      repo.delete(id).void.whenA(id.value.nonEmpty)
  }
}
```

### Repository with Error Handling

```scala
class UserRepository[F[_]: MonadError[*[_], Throwable]](
  db: Database
) {
  def find(id: UserId): F[Option[User]] =
    db.query[User]("SELECT * FROM users WHERE id = ?", id)
      .map(_.headOption)
      
  def save(user: User): F[Unit] =
    db.insert(user)
      .redeem(
        err => throw RepositoryError(err.getMessage),
        _ => ()
      )
      
  def delete(id: UserId): F[Unit] =
    F.raiseUnless(id.valid)(InvalidIdError)
      *> db.delete[User](id)
      .void
}
```

### Interpreters

```scala
// At the edge of your application, choose the concrete effect type

// Cats-Effect IO interpreter
object IOUserService {
  def apply(repo: UserRepository[IO]): UserService[IO] =
    UserService.impl[IO](repo)(Sync[IO])
}

// ZIO interpreter (using zio-interop-cats)
object ZIOUserService {
  type Env = UserRepository[Task]
  
  def apply(repo: UserRepository[Task]): UserService[Task] =
    UserService.impl[Task](repo)(Sync[Task])
}
```

## Pattern Summary Table

| Pattern | Detection | Replacement | Evidence |
|---------|-----------|-------------|----------|
| `map_unit` | `fa.map(_ => ())` | `fa.void` | Functor |
| `map_value` | `fa.map(_ => v)` | `fa.as(v)` | Functor |
| `flat_map_value` | `fa.flatMap(_ => fb)` | `fa *> fb` | Apply |
| `product_l` | `fa.flatMap(a => fb.as(a))` | `fa <* fb` | Apply |
| `flat_tap` | `fa.flatMap(a => effect.as(a))` | `fa.flatTap(a => effect)` | FlatMap |
| `when_a` | `if (cond) fa else F.unit` | `fa.whenA(cond)` | Applicative |
| `unless_a` | `if (!cond) fa else F.unit` | `fa.unlessA(cond)` | Applicative |
| `if_m` | `fb.flatMap(b => if (b) fa else fc)` | `fb.ifM(fa, fc)` | Monad |
| `handle_error` | `.attempt.flatMap { Right/Left ... }` | `.handleError(...)` | MonadError |
| `raise_when` | `if (cond) F.raiseError(err) else F.unit` | `F.raiseWhen(cond)(err)` | MonadError |
| `raise_unless` | `if (cond) F.unit else F.raiseError(err)` | `F.raiseUnless(cond)(err)` | MonadError |
| `from_option` | `opt.fold(F.raiseError(err))(F.pure)` | `F.fromOption(opt)(err)` | MonadError |
| `from_either` | `either.fold(F.raiseError, F.pure)` | `F.fromEither(either)` | MonadError |
| `redeem` | `.attempt.map { Right/Left ... }` | `.redeem(...)` | MonadError |
| `redeem_with` | `.attempt.flatMap { Right/Left ... }` | `.redeemWith(...)` | MonadError |

## See Also

- [Patterns](Patterns.md) — ZIO and Cats-Effect pattern documentation
- [AGENTS.md](../AGENTS.md) — Full architecture and pattern catalog
- [Cats Documentation](https://typelevel.org/cats/)
- [Tagless Final Pattern](https://typelevel.org/cats/guidelines/tagless-final.html)
