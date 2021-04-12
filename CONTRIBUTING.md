- For bug fixes, please file an issue or submit a pull request to master. 
- For documentation improvements (typos, errors, etc.), please submit a pull request to the branch `docs/source`.
- For new features that are not already identified in issues, please file a new issue to discuss.

## Pull Request Requirements

Please document the intent of the pull request. All non-documentation pull requests must also include automated tests that cover the new code, including failure cases. If applicable, please update the documentation in the `docs/source` branch.

## Running Tests

Tests will automatically be run when you submit a pull request, but you will need to run tests locally. 

To script exists to make running the unit tests easy.

tool/install_unit_test_dependencies.dart
tool/run_unit_tests.dart

These scripts install a docker container running postgres on an alternate port 5432 and then
run the unit test against those scripts.

### Manual db configuration
If you have to create your own postgres install (not recommended) then you need to configure
it to run on port 5432.

You can override each of the db connection args via environment variables:

PSQL_HOST
PSQL_PORT
PSQL_USERNAME
PSQL_PASSWORD
PSQL_DBNAME


TODO: allow a user to configure the port the unit tests are run on. 

To manually create the test db:

```bash
psql -p 5432 -c 'create user dart with createdb;' -U postgres
psql -p 5432  -c "alter user dart with password 'dart';" -U postgres
psql -p 5432  -c 'create database dart_test;' -U postgres
psql -p 5432  -c 'grant all on database dart_test to dart;' -U postgres
```

Run all tests with the following command:

                pub run test -j 1
