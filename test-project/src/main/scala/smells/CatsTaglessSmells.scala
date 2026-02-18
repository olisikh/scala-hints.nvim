// Cats Tagless-Final Smells - All 15 patterns
// Each pattern has a comment showing the expected replacement
// Run Metals on this file to see scala-hints.nvim diagnostics

package smells

import cats.*
import cats.syntax.all.*

object CatsTaglessSmells:

  // ============================================================================
  // Functor Patterns (2 patterns)
  // ============================================================================

  // map_unit: fa.map(_ => ()) -> fa.void (requires Functor)
  def smell1[F[_]: Functor](fa: F[Int]): F[Unit] =
    fa.map(_ => ())

  // map_value: fa.map(_ => v) -> fa.as(v) (requires Functor)
  def smell2[F[_]: Functor](fa: F[Int]): F[String] =
    fa.map(_ => "hello")

  // ============================================================================
  // FlatMap Patterns (3 patterns)
  // ============================================================================

  // flat_map_value: fa.flatMap(_ => fb) -> fa *> fb (requires FlatMap)
  def smell3[F[_]: FlatMap](fa: F[Int], fb: F[String]): F[String] =
    fa.flatMap(_ => fb)

  // product_l: fa.flatMap(a => fb.as(a)) -> fa <* fb (requires FlatMap)
  def smell4[F[_]: FlatMap](fa: F[Int], fb: F[String]): F[Int] =
    fa.flatMap(a => fb.as(a))

  // flat_tap: fa.flatMap(a => effect.as(a)) -> fa.flatTap(a => effect) (requires FlatMap)
  def smell5[F[_]: FlatMap](fa: F[Int], effect: F[Unit]): F[Int] =
    fa.flatMap(a => effect.as(a))

  // ============================================================================
  // Applicative Patterns (2 patterns)
  // ============================================================================

  // when_a: if (cond) fa else F.unit -> fa.whenA(cond) (requires Applicative)
  def smell6[F[_]: Applicative](fa: F[Int], cond: Boolean): F[Unit] =
    if (cond) fa.void else Applicative[F].unit

  // unless_a: if (!cond) fa else F.unit -> fa.unlessA(cond) (requires Applicative)
  def smell7[F[_]: Applicative](fa: F[Int], cond: Boolean): F[Unit] =
    if (!cond) fa.void else Applicative[F].unit

  // ============================================================================
  // Monad Patterns (1 pattern)
  // ============================================================================

  // if_m: fb.flatMap(b => if (b) fa else fc) -> fb.ifM(fa, fc) (requires Monad)
  def smell8[F[_]: Monad](
      fa: F[String],
      fb: F[Boolean],
      fc: F[String]
  ): F[String] =
    fb.flatMap(b => if (b) fa else fc)

  // ============================================================================
  // MonadError Patterns (7 patterns)
  // ============================================================================

  // handle_error: fa.attempt.flatMap { case Right/Left ... } -> fa.handleError (requires MonadError)
  def smell9[F[_]](fa: F[Int])(implicit F: MonadError[F, Throwable]): F[Int] =
    fa.attempt.flatMap {
      case Right(a) => F.pure(a)
      case Left(e)  => F.pure(-1)
    }

  // raise_when: if (cond) F.raiseError(err) else F.unit -> F.raiseWhen(cond)(err) (requires MonadError)
  def smell10[F[_]](cond: Boolean)(implicit
      F: MonadError[F, Throwable]
  ): F[Unit] =
    if (cond) F.raiseError(new Exception("error")) else F.unit

  // raise_unless: if (!cond) F.raiseError(err) else F.unit -> F.raiseUnless(cond)(err) (requires MonadError)
  def smell11[F[_]](cond: Boolean)(implicit
      F: MonadError[F, Throwable]
  ): F[Unit] =
    if (!cond) F.raiseError(new Exception("error")) else F.unit

  // from_option: opt.fold(F.raiseError(err))(F.pure) -> F.fromOption(opt)(err) (requires MonadError)
  def smell12[F[_]](opt: Option[Int])(implicit
      F: MonadError[F, Throwable]
  ): F[Int] =
    opt.fold(F.raiseError(new Exception("none")))(F.pure)

  // from_either: either.fold(F.raiseError, F.pure) -> F.fromEither(either) (requires MonadError)
  def smell13[F[_]](either: Either[Throwable, Int])(implicit
      F: MonadError[F, Throwable]
  ): F[Int] =
    either.fold(F.raiseError, F.pure)

  // redeem: .attempt.map { case Right/Left ... } -> .redeem (requires MonadError)
  def smell14[F[_]](
      fa: F[Int]
  )(implicit F: MonadError[F, Throwable]): F[String] =
    fa.attempt.map {
      case Right(a) => s"success: $a"
      case Left(e)  => s"error: ${e.getMessage}"
    }

  // redeem_with: .attempt.flatMap { case Right/Left ... } -> .redeemWith (requires MonadError)
  def smell15[F[_]](fa: F[Int], fallback: F[Int])(implicit
      F: MonadError[F, Throwable]
  ): F[Int] =
    fa.attempt.flatMap {
      case Right(a) => F.pure(a)
      case Left(_)  => fallback
    }
