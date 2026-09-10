package smells

import monix.eval.Task
import monix.reactive.Observable

import scala.util.Try
import scala.concurrent.duration._

// Test project for scala-hints.nvim pattern verification.
// Contains intentional Monix code smells; each def triggers a specific pattern.

// Task.now(()) ~> Task.unit
def smell01 = Task.now(())

// Task.pure(()) ~> Task.unit
def smell02 = Task.pure(())

// Task.now(None) ~> Task.none
def smell03 = Task.now(None)

// Task.now(Some(v)) ~> Task.some(v)
def smell04 = Task.now(Some(42))

// Task.now(Right(v)) ~> Task.right(v)
def smell05 = Task.now(Right(42))

// Task.now(Left(v)) ~> Task.left(v)
def smell06 = Task.now(Left("err"))

// Task(1).map(_ => ()) ~> Task(1).void
def smell07 = Task(1).map(_ => ())

// Task(1).map(_ => 42) ~> Task(1).as(42)
def smell08 = Task(1).map(_ => 42)

// Task(1).map(v => { log(v); v }) ~> Task(1).tapEval(v => log(v))
def smell09 = Task(1).map(v => { log(v); v })

// Task(1).flatMap(a => effect(a).as(a)) ~> Task(1).tapEval(a => effect(a))
def smell10 = Task(1).flatMap(a => effect(a).as(a))

// Task(1).attempt.map { case Right/Left } ~> .redeem / .redeemWith
def smell11 = Task(1).attempt.map {
  case Right(v) => v + 1
  case Left(e) => 0
}

// Task(1).attempt.flatMap { case Right/Left } ~> .redeemWith
def smell12 = Task(1).attempt.flatMap {
  case Right(v) => Task.now(v + 1)
  case Left(e) => Task.now(0)
}

// either.fold(Task.raiseError, Task.now) ~> Task.fromEither(either)
def smell13(either: Either[Throwable, Int]) =
  either.fold(Task.raiseError, Task.now)

// Try(x).fold(Task.raiseError, Task.now) ~> Task.fromTry(Try(x))
def smell14 =
  Try(1).fold(Task.raiseError, Task.now)

// Task.sequence(coll.map(f)) ~> Task.traverse(coll)(f)
def smell15(coll: List[Int]) =
  Task.sequence(coll.map(loadUser))

// Task.parTraverse(coll)(f) ~> Task.parTraverseN(n)(coll)(f)
def smell16(coll: List[Int]) =
  Task.parTraverse(coll)(loadUser)

// Task.parSequence(coll) ~> Task.parSequenceN(n)(coll)
def smell17(coll: List[Task[Int]]) =
  Task.parSequence(coll)

// Task.sleep(d) *> effect ~> effect.delayExecution(d)
def smell18 = Task.sleep(5.seconds) *> loadUser(1)

// Task.sleep(d).flatMap(_ => effect) ~> effect.delayExecution(d)
def smell19 = Task.sleep(5.seconds).flatMap(_ => loadUser(1))

// if (cond) effect else Task.unit ~> Task.when(cond)(effect)
def smell20(cond: Boolean) = if (cond) save(1) else Task.unit

// if (!cond) effect else Task.unit ~> Task.unless(cond)(effect)
def smell21(cond: Boolean) = if (!cond) save(1) else Task.unit

// if (cond) Task.raiseError(e) else Task.unit ~> Task.raiseWhen(cond)(e)
def smell22(cond: Boolean) = if (cond) Task.raiseError(err) else Task.unit

// if (!cond) Task.raiseError(e) else Task.unit ~> Task.raiseUnless(cond)(e)
def smell23(cond: Boolean) = if (!cond) Task.raiseError(err) else Task.unit

// Observable.now(()) ~> Observable.unit
def smell24 = Observable.now(())

// obs.mapEval(a => Task.now(a + 1)) ~> obs.map(a => a + 1)
def smell25(obs: Observable[Int]) = obs.mapEval(a => Task.now(a + 1))

// obs.switchIfEmpty(Observable.empty) ~> obs
def smell26(obs: Observable[Int]) = obs.switchIfEmpty(Observable.empty)

// Helpers referenced by the smells above; defined at the bottom so each
// smell def stays short and matches the treesitter query sources.
def log(v: Int): Unit = println(s"log: $v")
def effect(a: Int): Task[Int] = Task.now(a)
def loadUser(id: Int): Task[Int] = Task.now(id)
def save(id: Int): Task[Unit] = Task.unit
val err = new RuntimeException("boom")