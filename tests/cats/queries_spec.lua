--- Tests for Cats (tagless-final) queries.
--- These handlers are Treesitter-based and gated by explicit evidence in the enclosing def.

local H = require('tests.helpers')
local queries = require('scala-hints.libs.cats.queries')

describe('Cats tagless queries', function()
  local bufnr

  after_each(function()
    if bufnr then
      H.cleanup_buf(bufnr)
      bufnr = nil
    end
  end)

  describe('map_unit', function()
    it('matches map(_ => ()) when Functor evidence exists', function()
      local source = [=[
        def foo[F[_]: Functor](fa: F[Int]) = fa.map(_ => ())
      ]=]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.map_unit)
      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'void',
      })
    end)

    it('does not match without evidence', function()
      local source = [=[
        def foo[F[_]](fa: F[Int]) = fa.map(_ => ())
      ]=]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.map_unit)
      assert.are.equal(0, #pending)
      assert.are.equal(0, #ready)
    end)
  end)

  describe('map_value', function()
    it('matches map(_ => value) when Functor evidence exists', function()
      local source = [=[
        def foo[F[_]](fa: F[Int])(implicit F: Functor[F]) = fa.map(_ => 42)
      ]=]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.map_value)
      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'as(42)',
      })
    end)
  end)

  describe('flat_map_value', function()
    it('matches flatMap(_ => fb) when Apply evidence exists', function()
      local source = [=[
        def foo[F[_]: Apply](fa: F[Int], fb: F[String]) = fa.flatMap(_ => fb)
      ]=]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.flat_map_value)
      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = ' *> fb',
      })
    end)
  end)

  describe('when_a', function()
    it('matches if (cond) fa else Applicative[F].unit', function()
      local source = [=[
        def foo[F[_]: Applicative](cond: Boolean, fa: F[Int]) = if (cond) fa else Applicative[F].unit
      ]=]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.when_a)
      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'fa.whenA(cond)',
      })
    end)
  end)

  describe('unless_a', function()
    it('matches if (!cond) fa else F.unit when Applicative evidence exists', function()
      local source = [=[
        def foo[F[_]: Applicative](cond: Boolean, fa: F[Int]) = if (!cond) fa else F.unit
      ]=]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.unless_a)
      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'fa.unlessA(cond)',
      })
    end)

    it('matches if (cond) F.unit else fa when Applicative evidence exists', function()
      local source = [=[
        def foo[F[_]: Applicative](cond: Boolean, fa: F[Int]) = if (cond) F.unit else fa
      ]=]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.unless_a)
      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'fa.unlessA(cond)',
      })
    end)

    it('does not match without Applicative evidence', function()
      local source = [=[
        def foo[F[_]](cond: Boolean, fa: F[Int]) = if (cond) F.unit else fa
      ]=]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.unless_a)
      assert.are.equal(0, #pending)
      assert.are.equal(0, #ready)
    end)
  end)

  describe('if_m', function()
    it('matches flatMap(b => if (b) fa else fc) when Monad evidence exists', function()
      local source = [=[
        def foo[F[_]: Monad](fb: F[Boolean], fa: F[Int], fc: F[Int]) = fb.flatMap(b => if (b) fa else fc)
      ]=]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.if_m)
      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'ifM(fa, fc)',
      })
    end)
  end)

  describe('handle_error', function()
    it('matches attempt.flatMap with pure left/right when MonadError evidence exists', function()
      local source = [=[
        def foo[F[_]](fa: F[Int], default: Int)(implicit F: MonadError[F, Throwable]) =
          fa.attempt.flatMap {
            case Right(a) => Applicative[F].pure(a)
            case Left(e) => Applicative[F].pure(default)
          }
      ]=]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.handle_error)
      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = '.handleError(_ => default)',
      })
    end)
  end)
end)
  describe('raise_when', function()
    it('matches if (cond) F.raiseError(err) else F.unit when MonadError evidence exists', function()
      local source = [=[
        def foo[F[_]](cond: Boolean, err: Throwable)(implicit F: MonadError[F, Throwable]) =
          if (cond) F.raiseError(err) else F.unit
      ]=]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.raise_when)
      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'F.raiseWhen(cond)(err)',
      })
    end)

    it('does not match without MonadError evidence', function()
      local source = [=[
        def foo[F[_]](cond: Boolean, err: Throwable) =
          if (cond) F.raiseError(err) else F.unit
      ]=]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.raise_when)
      assert.are.equal(0, #pending)
      assert.are.equal(0, #ready)
    end)
  end)

  describe('raise_unless', function()
    it('matches if (!cond) F.raiseError(err) else F.unit when MonadError evidence exists', function()
      local source = [=[
        def foo[F[_]](cond: Boolean, err: Throwable)(implicit F: MonadError[F, Throwable]) =
          if (!cond) F.raiseError(err) else F.unit
      ]=]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.raise_unless)
      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'F.raiseUnless(cond)(err)',
      })
    end)

    it('does not match without MonadError evidence', function()
      local source = [=[
        def foo[F[_]](cond: Boolean, err: Throwable) =
          if (!cond) F.raiseError(err) else F.unit
      ]=]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.raise_unless)
      assert.are.equal(0, #pending)
      assert.are.equal(0, #ready)
    end)
  end)

  describe('from_option', function()
    it('matches opt.fold(F.raiseError(err))(F.pure) when MonadError evidence exists', function()
      local source = [=[
        def foo[F[_]: MonadError](opt: Option[Int], err: Throwable) =
          opt.fold(F.raiseError(err))(F.pure)
      ]=]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.from_option)
      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'F.fromOption(opt)(err)',
      })
    end)

    it('does not match without MonadError evidence', function()
      local source = [=[
        def foo[F[_]](opt: Option[Int], err: Throwable) =
          opt.fold(F.raiseError(err))(F.pure)
      ]=]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.from_option)
      assert.are.equal(0, #pending)
      assert.are.equal(0, #ready)
    end)
  end)

  describe('from_either', function()
    it('matches either.fold(F.raiseError, F.pure) when MonadError evidence exists', function()
      local source = [=[
        def foo[F[_]: MonadError](either: Either[String, Int]) =
          either.fold(F.raiseError, F.pure)
      ]=]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.from_either)
      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'F.fromEither(either)',
      })
    end)

    it('does not match without MonadError evidence', function()
      local source = [=[
        def foo[F[_]](either: Either[String, Int]) =
          either.fold(F.raiseError, F.pure)
      ]=]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.from_either)
      assert.are.equal(0, #pending)
      assert.are.equal(0, #ready)
    end)
  end)
