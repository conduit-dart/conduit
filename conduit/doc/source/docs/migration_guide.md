# Migration:  Aqueduct to Conduit

## Migrating from Aqueduct to Conduit

Aqueduct is the predessor to Conduit and was developed by stablekernel who no longer support Aqueduct.

Conduit is the community driven fork of Aqueduct.

This guide is intended to help users of Aqueduct migrate to Conduit.

## Significant changes

### Cli tooling

The most obvious change is the name and this is reflected in the cli tooling.

The aqueduect cli command is now called conduit.

To install conduit you run

```bash
dart pub global activate conduit
```

### Test database

In conduit the test database used for unit testing and the test harness had the following attributes:

user: dart password: dart db name: dart\_test

In conduit these have been changed to:

user: conduit\_test\_user password: conduit! db name: conduit\_test\_db

