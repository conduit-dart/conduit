# Introduction

![Conduit](https://s3.amazonaws.com/conduit-collateral/conduit.png)

[![Build Status](https://travis-ci.org/conduit.dart/conduit.svg?branch=master)](https://travis-ci.org/conduit.dart/conduit) [![codecov](https://codecov.io/gh/conduit.dart/conduit/branch/master/graph/badge.svg)](https://codecov.io/gh/conduit.dart/conduit)

## Conduit

Conduit is an HTTP web server framework for building REST applications written in Dart.

## How to Use this Documentation

The menu on the left contains a hierarchy documents. Those documents - and how you should use them - are described in the following table:

| Location | Description | Recommended Usage |
| :--- | :--- | :--- |
| Top-Level \(e.g. Tour, Core Concepts\) | Introductory and quick reference documents | Read these documents when you are new to Conduit |
| Snippets | Example code snippets of common behaviors | Read these documents for examples and inspiration |
| Tutorial | A linear, guided tutorial to building your first application | A 1-3 hour long tutorial to learn Conduit |
| Guides | A hierarchy of in-depth guides for the many facets of Conduit | Refer to these documents often to understand concepts and usage of Conduit |

In addition to these guides, be sure to use the [API Reference](https://pub.dev/documentation/conduit/latest/) to look up classes, methods, functions and other elements of the framework.

## Getting Started Tips

The best way to get started is to read the [Core Concepts guide](core_concepts.md) while working through the [tutorial](tut/getting-started.md). Then, add new features to the application created during the tutorial by looking up the classes you are using in the [API Reference](https://pub.dev/documentation/conduit/latest/), and implementing behavior not found in the tutorial.

Once you have the basic concepts down, start reading the guides in the left hand menu to take advantage of the many features of the framework. Check out the repository of examples [here](https://github.com/conduit.dart/conduit_examples).

Import [this file](https://s3.amazonaws.com/conduit-intellij/conduit.jar) into IntelliJ IDEA for Conduit file and code templates.

Conduit is catered towards test-driven development - the best way to write an application is to write tests using a [test harness](testing/tests.md) and run those tests after implementing an endpoint. You may also run the command `conduit document client` in your project directory to generate a web client for your application. This client can be opened in any browser and will execute requests against your locally running application.

