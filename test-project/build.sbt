// Test project for scala-hints.nvim pattern verification
// This project contains intentional code smells to test the plugin

val scala3Version = "3.8.1"

val zioVersion = "2.1.7"
// Monix 3.4.0's monix-catnap module depends on Cats-Effect 2.x.
// Keep this aligned so sbt can export the root Bloop target for Metals.
val catsEffectVersion = "2.5.1"
val catsVersion = "2.12.0"
val monixVersion = "3.4.0"

lazy val root = project
  .in(file("."))
  .settings(
    name := "scala-hints-test",
    version := "0.1.0",
    scalaVersion := scala3Version,
    libraryDependencies ++= Seq(
      // ZIO
      "dev.zio" %% "zio" % zioVersion,
      "dev.zio" %% "zio-streams" % zioVersion,
      "dev.zio" %% "zio-test" % zioVersion % Test,
      
      // Cats-Effect
      "org.typelevel" %% "cats-effect" % catsEffectVersion,
      
      // Cats (for tagless-final)
      "org.typelevel" %% "cats-core" % catsVersion,

      // Monix (Task and Observable)
      "io.monix" %% "monix" % monixVersion,
    ),
    scalacOptions ++= Seq(
      "-deprecation",
      "-feature",
      "-unchecked",
    ),
  )
