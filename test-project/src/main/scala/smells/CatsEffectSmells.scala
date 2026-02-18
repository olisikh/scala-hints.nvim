// Cats-Effect Smells - All 40 patterns
// Each pattern has a comment showing the expected replacement
// Run Metals on this file to see scala-hints.nvim diagnostics

package smells

import cats.effect.*
import cats.syntax.all.*
import scala.concurrent.duration.*

object CatsEffectSmells:

  // ============================================================================
  // Console Output (4 patterns)
  // ============================================================================

  // println: IO(println(x)) -> IO.println(x)
  def smell1 = IO(println("hello"))
  
  // println_apply: IO.apply(println(x)) -> IO.println(x)
  def smell2 = IO.apply(println("hello"))
  
  // print: IO(print(x)) -> IO.print(x)
  def smell3 = IO(print("hello"))
  
  // print_apply: IO.apply(print(x)) -> IO.print(x)
  def smell4 = IO.apply(print("hello"))

  // ============================================================================
  // Discard/Replace Value (4 patterns)
  // ============================================================================

  // map_unit: .map(_ => ()) -> .void
  def smell5 = IO(42).map(_ => ())
  
  // map_value: .map(_ => v) -> .as(v)
  def smell6 = IO(42).map(_ => "hello")
  
  // pure_unit: IO.pure(()) -> IO.unit
  def smell7 = IO.pure(())
  
  // as_unit: .as(()) -> .void
  def smell8 = IO(42).as(())

  // ============================================================================
  // Sequencing & Control Flow (5 patterns)
  // ============================================================================

  // zip_right_unit: effect *> IO.unit -> effect.void
  def smell9 = IO(42) *> IO.unit
  
  // zip_right_value: effect *> IO.pure(v) -> effect.as(v)
  def smell10 = IO(42) *> IO.pure("hello")
  
  // flat_map_value: .flatMap(_ => io) -> >> io
  def smell11 = IO(42).flatMap(_ => IO("hello"))
  
  // when_a: if (cond) io else IO.unit -> io.whenA(cond)
  def smell12(cond: Boolean) = if (cond) IO(42) else IO.unit
  
  // unless_a: if (!cond) io else IO.unit -> io.unlessA(cond)
  def smell13(cond: Boolean) = if (!cond) IO(42) else IO.unit

  // ============================================================================
  // Error Handling (8 patterns)
  // ============================================================================

  // handle_error: .attempt.flatMap { case Right/Left ... } -> .handleError
  def smell14 = IO(42).attempt.flatMap {
    case Right(a) => IO.pure(a)
    case Left(e) => IO.pure(-1)
  }
  
  // raise_when: if (cond) IO.raiseError(err) else IO.unit -> IO.raiseWhen(cond)(err)
  def smell15(cond: Boolean) = if (cond) IO.raiseError(new Exception("error")) else IO.unit
  
  // raise_unless: if (!cond) IO.raiseError(err) else IO.unit -> IO.raiseUnless(cond)(err)
  def smell16(cond: Boolean) = if (!cond) IO.raiseError(new Exception("error")) else IO.unit
  
  // from_option: opt.fold(IO.raiseError(err))(IO.pure) -> IO.fromOption(opt)(err)
  def smell17(opt: Option[Int]) = opt.fold(IO.raiseError(new Exception("none")))(IO.pure)
  
  // from_either: either.fold(IO.raiseError, IO.pure) -> IO.fromEither(either)
  def smell18(either: Either[Throwable, Int]) = either.fold(IO.raiseError, IO.pure)
  
  // redeem: .attempt.map { case Right/Left ... } -> .redeem
  def smell19 = IO(42).attempt.map {
    case Right(a) => s"success: $a"
    case Left(e) => s"error: ${e.getMessage}"
  }
  
  // redeem_with: .attempt.flatMap { case Right/Left ... } -> .redeemWith
  def smell20 = IO(42).attempt.flatMap {
    case Right(a) => IO.pure(a)
    case Left(e) => IO.pure(-1)
  }

  // ============================================================================
  // Lifting Values (2 patterns)
  // ============================================================================

  // from_option_match: Option match with IO.pure/IO.raiseError -> IO.fromOption
  def smell21(opt: Option[Int]) = opt match {
    case Some(a) => IO.pure(a)
    case None => IO.raiseError(new Exception("none"))
  }
  
  // from_either_match: Either match with IO.pure/IO.raiseError -> IO.fromEither
  def smell22(either: Either[Throwable, Int]) = either match {
    case Right(a) => IO.pure(a)
    case Left(e) => IO.raiseError(e)
  }

  // ============================================================================
  // Parallelism & Traversal (5 patterns)
  // ============================================================================

  // par_tupled: (io1, io2).parMapN -> (io1, io2).parTupled
  def smell23 = (IO(1), IO(2)).parMapN((a, b) => (a, b))
  
  // par_sequence: IO.parSequence -> IO.parSequence
  def smell24 = List(IO(1), IO(2), IO(3)).parSequence
  
  // par_sequence_: IO.parSequence_ -> IO.parSequence_
  def smell25 = List(IO(1), IO(2), IO(3)).parSequence_
  
  // traverse: .map(f).sequence -> .traverse(f)
  def smell26 = List(1, 2, 3).map(x => IO(x * 2)).sequence
  
  // traverse_: .map(f).sequence_ -> .traverse_(f)
  def smell27 = List(1, 2, 3).map(x => IO(println(x))).sequence_

  // ============================================================================
  // Timing (1 pattern)
  // ============================================================================

  // delay_by: IO.sleep(d) *> effect -> effect.delayBy(d)
  def smell28 = IO.sleep(1.second) *> IO(42)

  // ============================================================================
  // Monadic Operations (1 pattern)
  // ============================================================================

  // if_m: fb.flatMap(b => if (b) fa else fc) -> fb.ifM(fa, fc)
  def smell29 = IO(true).flatMap(b => if (b) IO("yes") else IO("no"))

  // ============================================================================
  // Additional Patterns
  // ============================================================================

  // map_n: for-comprehension with constructor yield -> .mapN
  def smell30 = for {
    a <- IO(1)
    b <- IO(2)
  } yield (a, b)
