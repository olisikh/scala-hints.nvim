// ZIO Smells - All 35 patterns
// Each pattern has a comment showing the expected replacement
// Run Metals on this file to see scala-hints.nvim diagnostics

package smells

import zio.*

object ZioSmells:

  // ============================================================================
  // Constructors & Units
  // ============================================================================

  // succeed_unit: ZIO.succeed(()) -> ZIO.unit
  def smell1 = ZIO.succeed(())
  
  // map_unit: .map(_ => ()) -> .unit
  def smell2 = ZIO.succeed(42).map(_ => ())
  
  // as_unit: .as(()) -> .unit
  def smell3 = ZIO.succeed(42).as(())
  
  // zip_right_unit: *> ZIO.unit -> .unit
  def smell4 = ZIO.succeed(42) *> ZIO.unit
  
  // zip_right_value: *> ZIO.succeed(v) -> .as(v)
  def smell5 = ZIO.succeed(42) *> ZIO.succeed("hello")

  // ============================================================================
  // Combinators
  // ============================================================================

  // zip_right_operator: .zipRight(v) -> *> v
  def smell6 = ZIO.succeed(42).zipRight(ZIO.succeed("hello"))
  
  // zip_left_value: .tap(_ => v) -> .zipLeft(v) (when param unused)
  def smell7 = ZIO.succeed(42).tap(_ => ZIO.succeed("side effect"))
  
  // flat_map_value: .flatMap(_ => v) -> .zipRight(v)
  def smell8 = ZIO.succeed(42).flatMap(_ => ZIO.succeed("hello"))
  
  // map_value: .map(_ => v) -> .as(v)
  def smell9 = ZIO.succeed(42).map(_ => "hello")

  // ============================================================================
  // Error Handling
  // ============================================================================

  // zio_die: ZIO.fail(ex).orDie -> ZIO.die(ex)
  def smell10(ex: Throwable) = ZIO.fail(ex).orDie
  
  // catch_all_unit: .catchAll(_ => ZIO.unit) -> .ignore
  def smell11 = ZIO.fail("error").catchAll(_ => ZIO.unit)
  
  // zio_cond: ZIO.cond(cond, (), err) -> ZIO.fail(err).unless(cond)
  def smell12(cond: Boolean, err: String) = ZIO.cond(cond, (), err)
  
  // fold_cause_ignore: .foldCause(_ => (), _ => ()) -> .ignore
  def smell13 = ZIO.fail("error").foldCause(_ => (), _ => ())
  
  // or_else_fail: .mapError(_ => v) -> .orElseFail(v)
  def smell14 = ZIO.fail("error").mapError(_ => "fallback error")
  
  // or_else_fail2: .orElse(ZIO.fail(v)) -> .orElseFail(v)
  def smell15 = ZIO.fail("error").orElse(ZIO.fail("fallback error"))
  
  // or_else_fail3: .flatMapError(_ => ZIO.succeed(v)) -> .orElseFail(v)
  def smell16 = ZIO.fail("error").flatMapError(_ => ZIO.succeed("fallback error"))

  // ============================================================================
  // Type Aliases
  // ============================================================================

  // zio_type: ZIO[Any, Nothing, A] -> UIO[A]
  def smell17: ZIO[Any, Nothing, String] = ZIO.succeed("hello")
  
  // zio_type: ZIO[Any, Throwable, A] -> Task[A]
  def smell18: ZIO[Any, Throwable, String] = ZIO.succeed("hello")
  
  // zio_type: ZIO[Any, Nothing, Nothing] -> UIO[Nothing]
  def smell19: ZIO[Any, Nothing, Nothing] = ZIO.die(new RuntimeException)
  
  // zlayer_type: ZLayer[Any, Nothing, A] -> ULayer[A]
  def smell20: ZLayer[Any, Nothing, String] = ZLayer.succeed("hello")
  
  // zlayer_type: ZLayer[Any, Throwable, A] -> TaskLayer[A]
  def smell21: ZLayer[Any, Throwable, String] = ZLayer.succeed("hello")

  // ============================================================================
  // Option/Either
  // ============================================================================

  // zio_none: ZIO.succeed(None) -> ZIO.none
  def smell22 = ZIO.succeed(None)
  
  // zio_some: ZIO.succeed(Some(v)) -> ZIO.some(v)
  def smell23 = ZIO.succeed(Some("hello"))
  
  // zio_either: ZIO.succeed(Left(v)) -> ZIO.left(v)
  def smell24 = ZIO.succeed(Left("error"))
  
  // zio_either: ZIO.succeed(Right(v)) -> ZIO.right(v)
  def smell25 = ZIO.succeed(Right("value"))

  // ============================================================================
  // Timing & Layers
  // ============================================================================

  // delay: ZIO.sleep(d) *> effect -> effect.delay(d)
  def smell26 = ZIO.sleep(1.second) *> ZIO.succeed("hello")

  // ============================================================================
  // Transform Helpers
  // ============================================================================

  // tap: .map(v => { sideEffect(v); v }) -> .tap(sideEffect)
  def smell27 = ZIO.succeed(42).map(v => { println(v); v })
  
  // tap_error: .mapError(e => { sideEffect(e); e }) -> .tapError(sideEffect)
  def smell28 = ZIO.fail("error").mapError(e => { println(e); e })
  
  // tap_both: chained map/mapError side-effects -> .tapBoth(...)
  def smell29 = ZIO.fail("error")
    .map(v => { println(s"success: $v"); v })
    .mapError(e => { println(s"error: $e"); e })
  
  // when: if (cond) eff else ZIO.unit -> eff.when(cond)
  def smell30(cond: Boolean) = if (cond) ZIO.succeed(42) else ZIO.unit
  
  // unless: if (!cond) eff else ZIO.unit -> eff.unless(cond)
  def smell31(cond: Boolean) = if (!cond) ZIO.succeed(42) else ZIO.unit

  // ============================================================================
  // Exit Codes
  // ============================================================================

  // exit_code_map: .map(_ => ExitCode.success) -> .exitCode
  def smell32 = ZIO.succeed(42).map(_ => ExitCode.success)
  
  // exit_code_as: .as(ExitCode.success) -> .exitCode
  def smell33 = ZIO.succeed(42).as(ExitCode.success)
  
  // exit_code_fold: .fold(...ExitCode...) -> .exitCode
  def smell34 = ZIO.fail("error").fold(_ => ExitCode.failure, _ => ExitCode.success)

  // ============================================================================
  // Collections
  // ============================================================================

  // zio_foreach: ZIO.collectAll(coll.map(f)) -> ZIO.foreach(coll)(f)
  def smell35 = ZIO.collectAll(List(1, 2, 3).map(x => ZIO.succeed(x * 2)))
