# Introduction

![](assets/image.png)

[![Linux](https://github.com/conduit-dart/conduit/actions/workflows/linux.yml/badge.svg)](https://github.com/conduit-dart/conduit/actions/workflows/linux.yml) [![Windows](https://github.com/conduit-dart/conduit/actions/workflows/windows.yml/badge.svg)](https://github.com/conduit-dart/conduit/actions/workflows/windows.yml) [![Macos](https://github.com/conduit-dart/conduit/actions/workflows/macos.yml/badge.svg)](https://github.com/conduit-dart/conduit/actions/workflows/macos.yml) [<img src="https://discord.com/assets/3437c10597c1526c3dbd98c737c2bcae.svg" width="28" height="20">](https://discord.gg/MHz5cqktHW)
[![melos](https://img.shields.io/badge/maintained%20with-melos-f700ff.svg?style=flat-square)](https://github.com/invertase/melos)

## Conduit

Conduit is a fork from Stablekernel's Aqueduct webserver framework. The project originally split off when null-safety was introduced as a feature in Dart. Stablekernel elected to discontinue development for Aqueduct and a community effort began to resurrect the framework as Conduit.

## Getting Started

For an educational experience read the [Core Concepts](core_concepts/) page while working through the [tutorial](tut/getting-started.md). If you simply need to start up a project quickly, you can use templates to deploy servers with authentication and database logic already implemented. For additional information about Conduit read the [API Reference](https://pub.dev/documentation/conduit/latest/).

Conduit is catered towards test-driven development - the best way to write an application is to write tests using a [test harness](testing/tests.md) and run those tests after implementing an endpoint. You may also run the command `conduit document client` in your project directory to generate a web client for your application. This client can be opened in any browser and will execute requests against your locally running application.

