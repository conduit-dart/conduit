# wildfire

## Running the Application Locally

Run `conduit serve` from this directory to run the application. For running within an IDE, run `bin/main.dart`. By default, a configuration file named `config.yaml` will be used.

To generate a SwaggerUI client, run `conduit document client`.

## Running Application Tests

To run all tests for this application, run the following in this directory:

```
pub run test
```

The default configuration file used when testing is `config.src.yaml`. This file should be checked into version control. It also the template for configuration files used in deployment.

## Compiling an AOT Binary

Run the following from this directory to produce a self-contained
executable that boots without `dart:mirrors`:

```
dart pub get
dart run build_runner build --delete-conflicting-outputs
dart compile exe bin/main.dart -o build/server
```

`build_runner` generates `lib/conduit.g.dart`; `bin/main.dart` calls
the generated `bootstrap()` before constructing `Application<T>`,
which is what makes the AOT path possible.

## Deploying an Application

See the documentation for [Deployment](https://www.theconduit.dev/docs/deploy/).