# Cats-Effect Patterns

## Overview

Cats-Effect is a library providing tools for writing pure, typeful, and effectful programs in Scala. The core effect types are `IO[A]` for synchronous and asynchronous effects, and `Resource[F, A]` for managing resources with acquisition and release semantics.

**Type verification**: All Cats-Effect patterns use Metals LSP `textDocument/typeDefinition` to verify that matched expressions are actual `IO` or `Resource` types from the cats-effect library.

**Key type signatures:**

```scala
IO[A]           // An effect that produces an A, may fail with Throwable
Resource[IO, A] // An effect that acquires a resource A and releases it after use
```

**Difference from tagless-final:** Unlike Cats tagless-final patterns which work with generic `F[_]` type constructors, Cats-Effect patterns target concrete `IO` and `Resource` types. This means:

- Direct method calls like `IO.pure`, `IO.raiseError`, `IO.unit`
- No typeclass evidence requirements
- LSP-based type verification for accuracy

## Patterns

### Console Output

#### `println` — Use IO.println

**Detection:** `IO(println(...))`

**Replacement:** `IO.println(...)`

```scala
// Before
def log(msg: String): IO[Unit] = IO(println(msg))

// After
def log(msg: String): IO[Unit] = IO.println(msg)
```

---

#### `println_apply` — Use IO.println (apply form)

**Detection:** `IO.apply(println(...))`

**Replacement:** `IO.println(...)`

```scala
// Before
def debug(msg: String): IO[Unit] = IO.apply(println(s"[DEBUG] $msg"))

// After
def debug(msg: String): IO[Unit] = IO.println(s"[DEBUG] $msg")
```

---

#### `print` — Use IO.print

**Detection:** `IO(print(...))`

**Replacement:** `IO.print(...)`

```scala
// Before
def prompt(msg: String): IO[Unit] = IO(print(msg + ": "))

// After
def prompt(msg: String): IO[Unit] = IO.print(msg + ": ")
```

---

#### `print_apply` — Use IO.print (apply form)

**Detection:** `IO.apply(print(...))`

**Replacement:** `IO.print(...)`

```scala
// Before
def show(msg: String): IO[Unit] = IO.apply(print(msg))

// After
def show(msg: String): IO[Unit] = IO.print(msg)
```

---

### Discard/Replace Value

#### `map_unit` — Discard result with void

**Detection:** `io.map(_ => ())`

**Replacement:** `io.void`

```scala
// Before
def saveAndForget(users: List[User]): IO[Unit] =
  saveUsers(users).map(_ => ())

// After
def saveAndForget(users: List[User]): IO[Unit] =
  saveUsers(users).void
```

---

#### `map_value` — Replace result with constant

**Detection:** `io.map(_ => value)`

**Replacement:** `io.as(value)`

```scala
// Before
def checkHealth: IO[Boolean] =
  pingServer.map(_ => true)

// After
def checkHealth: IO[Boolean] =
  pingServer.as(true)
```

---

#### `pure_unit` — Use IO.unit

**Detection:** `IO.pure(())`

**Replacement:** `IO.unit`

```scala
// Before
val nothing: IO[Unit] = IO.pure(())

// After
val nothing: IO[Unit] = IO.unit
```

---

#### `as_unit` — Replace with void

**Detection:** `io.as(())`

**Replacement:** `io.void`

```scala
// Before
def execute: IO[Unit] = runQuery.as(())

// After
def execute: IO[Unit] = runQuery.void
```

---

### Sequencing & Control Flow

#### `zip_right_unit` — Sequence and discard

**Detection:** `effect *> IO.unit`

**Replacement:** `effect.void`

```scala
// Before
def cleanup: IO[Unit] = deleteFiles *> IO.unit

// After
def cleanup: IO[Unit] = deleteFiles.void
```

---

#### `zip_right_value` — Sequence and replace result

**Detection:** `effect *> IO.pure(value)`

**Replacement:** `effect.as(value)`

```scala
// Before
def fetchAndCount: IO[Int] = fetchUsers *> IO.pure(42)

// After
def fetchAndCount: IO[Int] = fetchUsers.as(42)
```

---

#### `flat_map_value` — Sequence and discard parameter

**Detection:** `io.flatMap(_ => effect)`

**Replacement:** `io >> effect`

```scala
// Before
def pipeline: IO[Result] = validateInput.flatMap(_ => computeResult)

// After
def pipeline: IO[Result] = validateInput >> computeResult
```

---

#### `flat_tap` — Side-effect and continue

**Detection:** `io.flatMap(a => effect.as(a))`

**Replacement:** `io.flatTap(a => effect)`

```scala
// Before
def fetchWithAudit: IO[User] =
  fetchUser.flatMap(user => audit(user).as(user))

// After
def fetchWithAudit: IO[User] =
  fetchUser.flatTap(user => audit(user))
```

---

#### `when_a` — Conditional execution

**Detection:** `if (condition) effect else IO.unit`

**Replacement:** `effect.whenA(condition)`

```scala
// Before
def maybeSave(enabled: Boolean): IO[Unit] =
  if (enabled) saveToDatabase else IO.unit

// After
def maybeSave(enabled: Boolean): IO[Unit] =
  saveToDatabase.whenA(enabled)
```

---

#### `unless_a` — Conditional execution (negated)

**Detection:** `if (!condition) effect else IO.unit`

**Replacement:** `effect.unlessA(condition)`

```scala
// Before
def skipIfCached(isCached: Boolean): IO[Unit] =
  if (!isCached) fetchFromSource else IO.unit

// After
def skipIfCached(isCached: Boolean): IO[Unit] =
  fetchFromSource.unlessA(isCached)
```

---

#### `if_m` — Monadic conditional

**Detection:** `pred.flatMap(b => if (b) fa else fb)`

**Replacement:** `pred.ifM(fa, fb)`

```scala
// Before
def process: IO[Result] =
  isEnabled.flatMap(enabled =>
    if (enabled) runComputation else IO.pure(defaultResult)
  )

// After
def process: IO[Result] =
  isEnabled.ifM(runComputation, IO.pure(defaultResult))
```

---

#### `forever_m` — Run forever

**Detection:** `def loop = effect.flatMap(_ => loop)`

**Replacement:** `effect.foreverM`

```scala
// Before
def pollForever: IO[Nothing] = {
  def loop: IO[Nothing] = poll >> loop
  loop
}

// After
def pollForever: IO[Nothing] = poll.foreverM
```

---

### Error Handling

#### `handle_error` — Recover with fallback

**Detection:** `io.attempt.flatMap { case Right(a) => IO.pure(a); case Left(e) => IO.pure(default) }`

**Replacement:** `io.handleError(_ => default)` or `io.handleErrorWith(e => IO.pure(default(e)))`

```scala
// Before
def fetchWithFallback: IO[User] =
  fetchUser.attempt.flatMap {
    case Right(user) => IO.pure(user)
    case Left(_) => IO.pure(User.default)
  }

// After
def fetchWithFallback: IO[User] =
  fetchUser.handleError(_ => User.default)
```

---

#### `raise_when` — Conditional error

**Detection:** `if (condition) IO.raiseError(err) else IO.unit`

**Replacement:** `IO.raiseWhen(condition)(err)`

```scala
// Before
def validate(invalid: Boolean): IO[Unit] =
  if (invalid) IO.raiseError(ValidationError) else IO.unit

// After
def validate(invalid: Boolean): IO[Unit] =
  IO.raiseWhen(invalid)(ValidationError)
```

---

#### `raise_unless` — Guard with error

**Detection:** `if (condition) IO.unit else IO.raiseError(err)`

**Replacement:** `IO.raiseUnless(condition)(err)`

```scala
// Before
def requireValid(valid: Boolean): IO[Unit] =
  if (valid) IO.unit else IO.raiseError(ValidationError)

// After
def requireValid(valid: Boolean): IO[Unit] =
  IO.raiseUnless(valid)(ValidationError)
```

---

#### `from_option` — Lift Option to IO

**Detection:** `opt.fold(IO.raiseError(err))(IO.pure)`

**Replacement:** `IO.fromOption(opt)(err)`

```scala
// Before
def findUser(id: UserId): IO[User] =
  queryDatabase(id).fold(IO.raiseError(UserNotFound))(IO.pure)

// After
def findUser(id: UserId): IO[User] =
  IO.fromOption(queryDatabase(id))(UserNotFound)
```

---

#### `from_option_match` — Lift Option match to IO

**Detection:** `opt match { case Some(x) => IO.pure(x); case None => IO.raiseError(err) }`

**Replacement:** `IO.fromOption(opt)(err)`

```scala
// Before
def getEnv(key: String): IO[String] =
  sys.env.get(key) match {
    case Some(value) => IO.pure(value)
    case None => IO.raiseError(MissingEnv(key))
  }

// After
def getEnv(key: String): IO[String] =
  IO.fromOption(sys.env.get(key))(MissingEnv(key))
```

---

#### `from_either` — Lift Either to IO

**Detection:** `either.fold(IO.raiseError, IO.pure)`

**Replacement:** `IO.fromEither(either)`

```scala
// Before
def process(input: String): IO[Result] =
  validateInput(input).fold(IO.raiseError, IO.pure)

// After
def process(input: String): IO[Result] =
  IO.fromEither(validateInput(input))
```

---

#### `from_either_match` — Lift Either match to IO

**Detection:** `either match { case Right(y) => IO.pure(y); case Left(e) => IO.raiseError(e) }`

**Replacement:** `IO.fromEither(either)`

```scala
// Before
def handle(result: Either[Error, Value]): IO[Value] =
  result match {
    case Right(value) => IO.pure(value)
    case Left(err) => IO.raiseError(err)
  }

// After
def handle(result: Either[Error, Value]): IO[Value] =
  IO.fromEither(result)
```

---

#### `from_try` — Lift Try to IO

**Detection:** `Try(x).fold(IO.raiseError, IO.pure)`

**Replacement:** `IO.fromTry(Try(x))`

```scala
// Before
def parseFile(content: String): IO[Data] =
  scala.util.Try(parse(content)).fold(IO.raiseError, IO.pure)

// After
def parseFile(content: String): IO[Data] =
  IO.fromTry(scala.util.Try(parse(content)))
```

---

#### `redeem` — Handle both success and failure

**Detection:** `io.attempt.map { case Right(a) => f(a); case Left(e) => g(e) }`

**Replacement:** `io.redeem(g, f)`

```scala
// Before
def fetchWithMessage: IO[String] =
  fetchUser.attempt.map {
    case Right(user) => s"Found: ${user.name}"
    case Left(err) => s"Error: ${err.getMessage}"
  }

// After
def fetchWithMessage: IO[String] =
  fetchUser.redeem(
    err => s"Error: ${err.getMessage}",
    user => s"Found: ${user.name}"
  )
```

---

#### `recover_with` — Selective error recovery

**Detection:** `io.attempt.flatMap { case Left(e: T) => recover(e); case Left(e) => IO.raiseError(e); case Right(a) => IO.pure(a) }`

**Replacement:** `io.recoverWith { case e: T => recover(e) }`

```scala
// Before
def fetchWithRetry: IO[User] =
  fetchUser.attempt.flatMap {
    case Left(e: TimeoutException) => retryFetch
    case Left(e) => IO.raiseError(e)
    case Right(user) => IO.pure(user)
  }

// After
def fetchWithRetry: IO[User] =
  fetchUser.recoverWith { case e: TimeoutException => retryFetch }
```

---

#### `adapt_error` — Transform error type

**Detection:** `io.handleErrorWith(e => IO.raiseError(wrap(e)))`

**Replacement:** `io.adaptError { case e => wrap(e) }`

```scala
// Before
def process: IO[Result] =
  queryService.handleErrorWith(e => IO.raiseError(AppError.from(e)))

// After
def process: IO[Result] =
  queryService.adaptError { case e => AppError.from(e) }
```

---

### Parallelism & Traversal

#### `traverse` — Transform and sequence

**Detection:** `coll.map(f).sequence`

**Replacement:** `coll.traverse(f)`

```scala
// Before
def processAll(users: List[User]): IO[List[Result]] =
  users.map(u => processUser(u)).sequence

// After
def processAll(users: List[User]): IO[List[Result]] =
  users.traverse(u => processUser(u))
```

---

#### `traverse_` — Transform and sequence, discard results

**Detection:** `coll.map(f).sequence_`

**Replacement:** `coll.traverse_(f)`

```scala
// Before
def notifyAll(users: List[User]): IO[Unit] =
  users.map(u => sendNotification(u)).sequence_

// After
def notifyAll(users: List[User]): IO[Unit] =
  users.traverse_(u => sendNotification(u))
```

---

#### `par_tupled` — Parallel tuple

**Detection:** `fa.flatMap(a => fb.map(b => (a, b)))`

**Replacement:** `(fa, fb).tupled`

```scala
// Before
def fetchBoth: IO[(User, Profile)] =
  fetchUser.flatMap(user =>
    fetchProfile(user.id).map(profile => (user, profile))
  )

// After
def fetchBoth: IO[(User, Profile)] =
  (fetchUser, fetchProfile(userId)).tupled
```

---

#### `par_tupled` (parallel variant) — Parallel execution

**Detection:** `fa.flatMap(a => fb.map(b => (a, b))).parTupled`

**Replacement:** `(fa, fb).parTupled`

```scala
// Before
def fetchParallel: IO[(A, B)] =
  fetchA.flatMap(a => fetchB.map(b => (a, b))).parTupled

// After
def fetchParallel: IO[(A, B)] =
  (fetchA, fetchB).parTupled
```

---

#### `par_sequence` — Parallel sequence

**Detection:** `coll.map(f).parSequence`

**Replacement:** `coll.parTraverse(f)`

```scala
// Before
def fetchAll(ids: List[Id]): IO[List[Data]] =
  ids.map(id => fetchData(id)).parSequence

// After
def fetchAll(ids: List[Id]): IO[List[Data]] =
  ids.parTraverse(id => fetchData(id))
```

---

#### `par_sequence_` — Parallel sequence, discard results

**Detection:** `coll.map(f).parSequence_`

**Replacement:** `coll.parTraverse_(f)`

```scala
// Before
def sendAll(msgs: List[Message]): IO[Unit] =
  msgs.map(msg => sendMessage(msg)).parSequence_

// After
def sendAll(msgs: List[Message]): IO[Unit] =
  msgs.parTraverse_(msg => sendMessage(msg))
```

---

#### `par_tupled_fibers` — Parallel fiber execution

**Detection:** `for { fA <- fa.start; fB <- fb.start; a <- fA.joinWithNever; b <- fB.joinWithNever } yield (a, b)`

**Replacement:** `(fa, fb).parTupled`

```scala
// Before
def fetchBothParallel: IO[(A, B)] = for {
  fA <- fetchA.start
  fB <- fetchB.start
  a <- fA.joinWithNever
  b <- fB.joinWithNever
} yield (a, b)

// After
def fetchBothParallel: IO[(A, B)] =
  (fetchA, fetchB).parTupled
```

---

#### `option_traverse` — Option traverse

**Detection:** `opt match { case Some(a) => f(a); case None => IO.unit }`

**Replacement:** `opt.traverse_(f)`

```scala
// Before
def processMaybe(opt: Option[Data]): IO[Unit] =
  opt match {
    case Some(data) => processData(data)
    case None => IO.unit
  }

// After
def processMaybe(opt: Option[Data]): IO[Unit] =
  opt.traverse_(data => processData(data))
```

---

#### `replicate_a_` — Repeat effect N times

**Detection:** `(1 to n).toList.traverse(_ => effect)`

**Replacement:** `effect.replicateA_(n)`

```scala
// Before
def retryThreeTimes: IO[Unit] =
  (1 to 3).toList.traverse_(_ => attemptOperation)

// After
def retryThreeTimes: IO[Unit] =
  attemptOperation.replicateA_(3)
```

---

#### `map_n` — Combine N effects

**Detection:** `for { a <- fa; b <- fb } yield Constructor(a, b)`

**Replacement:** `(fa, fb).mapN(Constructor.apply)`

```scala
// Before
def buildUser: IO[User] = for {
  id <- generateId
  name <- fetchName
} yield User(id, name)

// After
def buildUser: IO[User] =
  (generateId, fetchName).mapN(User.apply)
```

---

### Timing

#### `delay_by` — Delay effect execution

**Detection:** `Temporal[IO].sleep(duration) *> effect`

**Replacement:** `effect.delayBy(duration)`

```scala
// Before
def delayedProcess: IO[Unit] =
  Temporal[IO].sleep(5.seconds) *> processBatch

// After
def delayedProcess: IO[Unit] =
  processBatch.delayBy(5.seconds)
```

---

#### `timeout` — Add timeout

**Detection:** `IO.race(effect, Temporal[IO].sleep(d)).flatMap { ... }`

**Replacement:** `effect.timeout(d)`

```scala
// Before
def fetchWithTimeout: IO[User] =
  IO.race(fetchUser, Temporal[IO].sleep(5.seconds)).flatMap {
    case Right(_) => IO.raiseError(TimeoutError)
    case Left(user) => IO.pure(user)
  }

// After
def fetchWithTimeout: IO[User] =
  fetchUser.timeout(5.seconds)
```

---

### Resources

#### `bracket` — Resource management

**Detection:** `acquire.flatMap(a => use(a).guarantee(release(a)))`

**Replacement:** `acquire.bracket(a => use(a))(a => release(a))`

```scala
// Before
def withFile(path: String): IO[Result] =
  openFile(path).flatMap { file =>
    processFile(file).guarantee(closeFile(file))
  }

// After
def withFile(path: String): IO[Result] =
  openFile(path).bracket(processFile)(closeFile)
```

---

## Full Examples

### Service Layer

```scala
trait UserService:
  def findById(id: UserId): IO[Option[User]]
  def create(user: User): IO[User]
  def delete(id: UserId): IO[Unit]

object UserService:
  def apply(repo: UserRepository): UserService = new UserService:
    
    def findById(id: UserId): IO[Option[User]] =
      repo.find(id)
        .flatTap(user => IO.println(s"Found: $user"))
        .whenA(id.value.nonEmpty)
        
    def create(user: User): IO[User] =
      validateUser(user)
        .flatMap(repo.save)
        .handleError(_ => User.default)
        
    def delete(id: UserId): IO[Unit] =
      IO.raiseUnless(id.valid)(InvalidIdError) >>
        repo.delete(id).void
```

### HTTP Handler with Error Handling

```scala
object UserRoutes:
  def routes: HttpRoutes[IO] = HttpRoutes.of[IO] {
    case GET -> Root / "users" / userId =>
      IO.fromOption(UserId.fromString(userId))(InvalidUserId)
        .flatMap(id => UserService.findById(id))
        .flatMap {
          case Some(user) => Ok(user.asJson)
          case None => NotFound("User not found")
        }
        .recoverWith {
          case e: InvalidId => BadRequest(e.getMessage)
        }
  }
```

### Parallel Processing

```scala
object DataPipeline:
  def fetchAllData(ids: List[DataId]): IO[List[Data]] =
    ids.parTraverse(id => fetchData(id))
      .timeout(30.seconds)
      
  def aggregate: IO[Aggregation] =
    (fetchUsers, fetchOrders, fetchInventory)
      .parTupled
      .mapN(Aggregation.fromResults)
```

### Resource Management

```scala
object Database:
  def withConnection[A](use: Connection => IO[A]): IO[A] =
    acquireConnection.bracket(use)(conn => 
      IO.println("Releasing connection") >> conn.close
    )
    
  private def acquireConnection: IO[Connection] =
    IO.println("Acquiring connection") >>
      IO.blocking(DriverManager.getConnection(url))
```

---

## Pattern Summary Table

| Pattern | Detection | Replacement |
|---------|-----------|-------------|
| `println` | `IO(println(x))` | `IO.println(x)` |
| `println_apply` | `IO.apply(println(x))` | `IO.println(x)` |
| `print` | `IO(print(x))` | `IO.print(x)` |
| `print_apply` | `IO.apply(print(x))` | `IO.print(x)` |
| `map_unit` | `.map(_ => ())` | `.void` |
| `map_value` | `.map(_ => v)` | `.as(v)` |
| `pure_unit` | `IO.pure(())` | `IO.unit` |
| `as_unit` | `.as(())` | `.void` |
| `zip_right_unit` | `*> IO.unit` | `.void` |
| `zip_right_value` | `*> IO.pure(v)` | `.as(v)` |
| `flat_map_value` | `.flatMap(_ => v)` | `>> v` |
| `flat_tap` | `.flatMap(a => effect.as(a))` | `.flatTap(a => effect)` |
| `when_a` | `if (cond) fa else IO.unit` | `fa.whenA(cond)` |
| `unless_a` | `if (!cond) fa else IO.unit` | `fa.unlessA(cond)` |
| `if_m` | `.flatMap(b => if (b) fa else fb)` | `.ifM(fa, fb)` |
| `forever_m` | `def loop = effect.flatMap(_ => loop)` | `effect.foreverM` |
| `handle_error` | `.attempt.flatMap { Right/Left ... }` | `.handleError(...)` |
| `raise_when` | `if (cond) IO.raiseError(err) else IO.unit` | `IO.raiseWhen(cond)(err)` |
| `raise_unless` | `if (cond) IO.unit else IO.raiseError(err)` | `IO.raiseUnless(cond)(err)` |
| `from_option` | `opt.fold(IO.raiseError(err))(IO.pure)` | `IO.fromOption(opt)(err)` |
| `from_option_match` | `opt match { Some/None => ... }` | `IO.fromOption(opt)(err)` |
| `from_either` | `either.fold(IO.raiseError, IO.pure)` | `IO.fromEither(either)` |
| `from_either_match` | `either match { Right/Left => ... }` | `IO.fromEither(either)` |
| `from_try` | `Try(x).fold(IO.raiseError, IO.pure)` | `IO.fromTry(Try(x))` |
| `redeem` | `.attempt.map { Right/Left ... }` | `.redeem(...)` |
| `recover_with` | `.attempt.flatMap { typed Left ... }` | `.recoverWith { case ... }` |
| `adapt_error` | `.handleErrorWith(e => IO.raiseError(wrap(e)))` | `.adaptError { case e => wrap(e) }` |
| `traverse` | `.map(f).sequence` | `.traverse(f)` |
| `traverse_` | `.map(f).sequence_` | `.traverse_(f)` |
| `par_tupled` | `fa.flatMap(a => fb.map(b => (a, b)))` | `(fa, fb).tupled` |
| `par_sequence` | `.map(f).parSequence` | `.parTraverse(f)` |
| `par_sequence_` | `.map(f).parSequence_` | `.parTraverse_(f)` |
| `par_tupled_fibers` | `for { .start; .joinWithNever } yield (...)` | `(fa, fb).parTupled` |
| `option_traverse` | `opt match { Some => f(a); None => IO.unit }` | `opt.traverse_(f)` |
| `replicate_a_` | `(1 to n).toList.traverse(_ => effect)` | `effect.replicateA_(n)` |
| `map_n` | `for { a <- fa; b <- fb } yield C(a, b)` | `(fa, fb).mapN(C.apply)` |
| `delay_by` | `sleep(d) *> effect` | `effect.delayBy(d)` |
| `timeout` | `IO.race(effect, sleep(d)).flatMap { ... }` | `effect.timeout(d)` |
| `bracket` | `acquire.flatMap(a => use(a).guarantee(release))` | `acquire.bracket(use)(release)` |

---

## See Also

- [ZIO Patterns](ZIO.md)
- [Cats Tagless-Final Patterns](Cats-Tagless-Final.md)
- [Cats-Effect Documentation](https://typelevel.org/cats-effect/)
- [Cats-Effect IO](https://typelevel.org/cats-effect/docs/std/io)
- [Cats-Effect Resource](https://typelevel.org/cats-effect/docs/std/resource)
