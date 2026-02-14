Here’s a grab‑bag of **Cats‑Effect idioms** (CE3/CE4) that make code shorter, clearer, and less error‑prone—very similar in spirit to your ZIO examples.

I’ll show each as:

*   **Smell** → what to avoid
*   **Prefer** → shorter or more idiomatic
*   **Why** → brief rationale

***

## 1) Discarding results

**Smell**

```scala
Console[IO].println("hello").map(_ => ())
```

**Prefer**

```scala
Console[IO].println("hello").void
```

**Why:** `void` is the canonical “discard value” combinator.

***

## 2) Replace `map(_ => c)` / `map(_ => Unit)` patterns

**Smell**

```scala
Console[IO].println("hello").map(_ => 42)
```

**Prefer**

```scala
Console[IO].println("hello").as(42)
```

**Why:** `as` communicates intent better and avoids creating throwaway lambdas.

***

## 3) Sequencing effects & ignoring the left result

**Smell**

```scala
fa.flatMap(_ => fb)                 // or
fa.map(_ => ()).flatMap(_ => fb)
```

**Prefer**

```scala
fa *> fb    // keep fb’s value; ignore fa’s result
// or when you need a plain sequence with same type:
fa >> fb    // alias for flatMap(_ => fb)
```

**Why:** `*>` / `>>` are standard for sequencing with ignored left value.

***

## 4) Conditional effects

**Smell**

```scala
if (cond) fa else IO.unit
```

**Prefer**

```scala
fa.whenA(cond)
// or
fa.unlessA(cond)
```

**Why:** Expresses the “maybe perform this effect” pattern directly.

***

## 5) Effectful conditionals

**Smell**

```scala
pred.flatMap(b => if (b) fa else fb)
```

**Prefer**

```scala
pred.ifM(fa, fb)
```

**Why:** Standard idiom for `F[Boolean]` branching.

***

## 6) Turning booleans into failures

**Smell**

```scala
if (cond) IO.unit else IO.raiseError(err)
```

**Prefer**

```scala
IO.raiseUnless(cond)(err)
// or
IO.raiseWhen(!cond)(err)
```

**Why:** Reads declaratively and composes nicely.

***

## 7) Lifting `Option`/`Either`/`Try` into effects

**Smell**

```scala
opt.fold(IO.raiseError(err))(IO.pure)
either.fold(IO.raiseError, IO.pure)
Try(x).fold(IO.raiseError, IO.pure)
```

**Prefer**

```scala
IO.fromOption(opt)(err)
IO.fromEither(either)
IO.fromTry(scala.util.Try(x))
```

**Why:** Canonical constructors avoid manual plumbing.

***

## 8) Error handling (recover / transform)

**Smell**

```scala
fa.attempt.flatMap {
  case Right(a) => IO.pure(a)
  case Left(_)  => IO.pure(default)
}
```

**Prefer**

```scala
fa.handleError(_ => default)
// or if using the error:
fa.handleErrorWith(e => IO.pure(default(e)))
```

**Why:** Use the dedicated error combinators.

***

## 9) Error handling (total transformation)

**Smell**

```scala
fa.attempt.map {
  case Right(a) => f(a)
  case Left(e)  => g(e)
}
```

**Prefer**

```scala
fa.redeem(g, f)           // map both error and success
// or when you need effects on both sides:
fa.redeemWith(g, f)
```

**Why:** `redeem`/`redeemWith` are purpose-built for “fold over effect”.

***

## 10) Narrowing to a specific exception type

**Smell**

```scala
fa.attempt.flatMap {
  case Left(e: MyEx) => recover(e)
  case Left(e)       => IO.raiseError(e)
  case Right(a)      => IO.pure(a)
}
```

**Prefer**

```scala
fa.attemptNarrow[MyEx].redeemWith(recover, IO.pure)
```

**Why:** Avoids unsafe casts and noisy pattern matches.

***

## 11) Finalizers / try–finally

**Smell**

```scala
fa.flatMap(a => fb).guarantee(finalizer) // good, but sometimes people write:
fa.attempt.flatMap(_ => finalizer.attempt *> fa) // (don’t)
```

**Prefer**

```scala
fa.guarantee(finalizer)                  // always run finalizer
fa.guaranteeCase {
  case Outcome.Succeeded(_) => onOk
  case Outcome.Errored(e)   => onError(e)
  case Outcome.Canceled()   => onCancel
}
```

**Why:** Use structured finalization; `guaranteeCase` gives full outcome.

***

## 12) Resource safety vs manual acquire/release

**Smell**

```scala
open.acquire.bracket(use)(_ => open.release) // or manual try/finally around use
```

**Prefer**

```scala
Resource.make(acquire)(release).use { res =>
  use(res)
}
// trivial release? Use .onCancel/.guarantee on F, or Resource.surround
```

**Why:** `Resource` is the CE way for scoped lifecycles.

***

## 13) Delay scheduling

**Smell**

```scala
Temporal[IO].sleep(500.millis) *> fa
```

**Prefer**

```scala
fa.delayBy(500.millis)
// or run then wait:
fa.delayByStart(500.millis) // CE4
fa.delayBy(500.millis)      // CE3/4 (before starting fa)
```

**Why:** Reads better; fewer combinators.

***

## 14) Timeouts and races

**Smell**

```scala
IO.race(fa, Temporal[IO].sleep(1.second)).flatMap {
  case Left(a)  => IO.pure(a)
  case Right(_) => IO.raiseError(new TimeoutException)
}
```

**Prefer**

```scala
fa.timeout(1.second)
// or with fallback:
fa.timeoutTo(1.second, fallback)
```

**Why:** Built-in timeout combinators cover the common race pattern.

***

## 15) Parallelism: stop reimplementing with `start/join`

**Smell**

```scala
for {
  f1 <- fa.start
  f2 <- fb.start
  a  <- f1.joinWithNever
  b  <- f2.joinWithNever
} yield (a, b)
```

**Prefer**

```scala
import cats.syntax.parallel._

// pair
(fa, fb).parTupled

// list
list.parTraverse(process)
// ignore results
list.parTraverse_(fireAndForget)
```

**Why:** `Parallel` syntax expresses intent, handles cancellation/propagation.

***

## 16) Running two effects and keeping both results (sequencing vs parallel)

**Smell**

```scala
fa.flatMap(a => fb.map(b => (a, b)))          // sequential
```

**Prefer**

```scala
(fa, fb).tupled      // sequential but shorter
(fa, fb).parTupled  // parallel when legal
```

**Why:** Use `tupled`/`parTupled` instead of manual `flatMap`/`map`.

***

## 17) Logging / side effects without changing the value

**Smell**

```scala
fa.flatMap(a => Console[IO].println(a).as(a))
```

**Prefer**

```scala
fa.flatTap(a => Console[IO].println(a))
// For streams/resources, prefer evalTap from fs2/Resource
```

**Why:** Keep the original value, run an effect “on the side”.

***

## 18) Repeats

**Smell**

```scala
def loop: IO[Nothing] = fa.flatMap(_ => loop)
loop
```

**Prefer**

```scala
fa.foreverM                          // run forever (non-terminating)
fa.replicateA_(n)                    // run n times, ignore results
list.traverse_(fa)                   // run per element, ignore results
```

**Why:** Standard repetition combinators are clearer and less error-prone.

***

## 19) Option/Either effectful mapping

**Smell**

```scala
opt match {
  case Some(a) => f(a)
  case None    => IO.unit
}
```

**Prefer**

```scala
opt.traverse_(f)     // ignore results
opt.traverse(f)      // keep results
either.traverse(f)   // same for Either (right-biased)
```

**Why:** Traverse folds structure + effects in one go.

***

## 20) Short-circuiting on `Option`/`Either` in for-comprehensions

**Smell**

```scala
for {
  a <- IO.fromOption(optA)(AError)
  b <- IO.fromEither(eitherB)
  c <- IO.fromOption(optC)(CError)
} yield (a, b, c)
// (this is actually already good, but often people do nested if/elses)
```

**Prefer:** (same as above)

```scala
IO.fromOption(optA)(AError)
IO.fromEither(eitherB)
IO.fromOption(optC)(CError)
```

**Why:** Use `fromX` constructors instead of nested conditionals.

***

## 21) Unnecessary `Ref`/`Deferred` when `Resource` or `Scope` fits

**Smell**

```scala
for {
  d <- Deferred[IO, Unit]
  _ <- acquire.onCancel(d.complete(()).void)
  _ <- d.get
  _ <- release
} yield ()
```

**Prefer**

```scala
Resource.make(acquire)(_ => release).use(_ => work)
// or with scoped concurrency, use `Supervisor` (CE3) or `Spawn` + `Scope` (CE4)
```

**Why:** Concurrency/scope tools exist; prefer them over DIY coordination when possible.

***

## 22) Manual `Try`/`catch` for pure code

**Smell**

```scala
IO(unsafePure()).handleErrorWith(e => IO.raiseError(transform(e)))
```

**Prefer**

```scala
IO.interruptibleMany(unsafePure())  // for blocking/interruptible
IO.blocking(blockingCall)           // for blocking calls
IO.delay(pureButMayThrow())         // lightweight wrapping of pure but throwing
```

**Why:** Choose the proper constructor based on blocking/interruptibility.

***

## 23) `onError` misuse (forgetting to rethrow)

**Smell**

```scala
fa.onError { case e => Console[IO].println(s"oops $e") } // ok
// but sometimes people swallow the error with .attempt...
```

**Prefer**

```scala
fa.onError { case e => Console[IO].println(s"oops $e") } // this logs *and* preserves failure
```

**Why:** `onError` is a tap; it doesn’t recover. Don’t add extra `attempt` unless you really want recovery.

***

## 24) Cancelation-safe cleanups without full `Resource`

**Smell**

```scala
acquire *> use.guarantee(release)   // release even if acquire failed?
```

**Prefer**

```scala
Resource.makeFullpoll => acquire(release).use(use)
// or if you just want “after use” for an already-acquired A:
use.guarantee(release)
```

**Why:** `makeFull` lets you mask cancelation precisely during critical regions.

***

## 25) Exit on specific conditions

**Smell**

```scala
fa.flatMap {
  case Good => IO.unit
  case Bad  => IO.raiseError(new Exception("bad"))
}
```

**Prefer**

```scala
fa.flatMap {
  case Good => IO.unit
  case Bad  => IO.raiseError(BadError)
}.void
// or more declarative with raiseWhen/raiseUnless if you can phrase as boolean
```

**Why:** Keep branches minimal, prefer declarative raises when possible.

***

## 26) Converting `Unit` effect to a constant value

**Smell**

```scala
Console[IO].println("ok").map(_ => true)
```

**Prefer**

```scala
Console[IO].println("ok").as(true)
```

**Why:** Same idea as §2; `as` makes intent crisp.

***

## 27) Combining many independent effects into a case class

**Smell**

```scala
for {
  a <- fa
  b <- fb
  c <- fc
} yield My(a, b, c)
```

**Prefer**

```scala
(fa, fb, fc).mapN(My.apply)         // sequential
(fa, fb, fc).parMapN(My.apply)      // parallel
```

**Why:** `mapN`/`parMapN` are concise and emphasize independence.

***

## 28) Debug printing

**Smell**

```scala
fa.flatMap(a => IO(println(a)).as(a))
```

**Prefer**

```scala
import cats.effect.syntax.all._
fa.debug  // CE4: pretty prints with fiber info; otherwise use flatTap with Console
```

**Why:** CE4’s `debug` is handy for diagnostics.

***

### A tiny “cheat sheet” summary

*   **Discard / replace**: `.void`, `.as(c)`
*   **Sequence**: `fa *> fb` / `fa >> fb`
*   **Conditionals**: `.whenA`, `.unlessA`, `.ifM`
*   **Raise**: `raiseWhen/raiseUnless`, `fromOption/fromEither/fromTry`
*   **Errors**: `handleError/handleErrorWith`, `redeem/redeemWith`, `attemptNarrow`
*   **Finalization**: `guarantee/guaranteeCase`, prefer `Resource` for lifecycles
*   **Time**: `delayBy`, `timeout/timeoutTo`, `sleep`
*   **Parallel**: `.parTupled`, `.parMapN`, `.parTraverse(_)`
*   **Side-effects w/o changing value**: `.flatTap`
*   **Repetition**: `.foreverM`, `.replicateA_`, `.traverse_`

If you want, I can tailor this to **your exact CE version (3 vs 4)** and **your codebase style** (e.g., heavy `Resource`, `Supervisor`, `Dispatcher`, fs2 integration), or convert any ZIO snippet you like into the closest CE idiom.
