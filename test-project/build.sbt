// Test project for scala-hints.nvim pattern verification
// This project contains intentional code smells to test the plugin

val scala3Version = "3.8.1"

val zioVersion = "2.1.7"
val catsEffectVersion = "3.5.7"
val catsVersion = "2.12.0"

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
    ),
    scalacOptions ++= Seq(
      "-deprecation",
      "-feature",
      "-unchecked",
    ),
  )
