# Contributing
- For bug fixes, please file an issue or submit a pull request to master. 
- For documentation improvements (typos, errors, etc.), please submit a pull request to the branch `docs/source`.
- For new features that are not already identified in issues, please file a new issue to discuss.

## Pull Request Requirements

Please document the intent of the pull request. All non-documentation pull requests must also include automated tests that cover the new code, including failure cases. If applicable, please update the documentation in the `docs/source` branch.

## Running Tests

Tests will automatically be run when you submit a pull request (PR), but you will need to run tests locally before submitting your PR.

The Conduit repo contains scripts to make running the unit tests easier.

The scripts a written using dcli so you need to install dcli first:

```bash
pub global activate dcli
```


To configure unit tests, including install a docker based postgres image run:

```bash
tool/setup_unit_tests.dart

```

To run the unit tests:

```
tool/run_unit_tests.dart
```

These scripts install a docker container running postgres on an alternate port 15432 and then
run the unit test against those scripts.

### Manual db configuration
If you have to create your own postgres install (not recommended) then you need to configure
it to run on port 15432.

You can override each of the db connection args via environment variables or by creating a .settings.yaml file in the conduit/tool directory.

Environment variables:

POSTGRES_HOST
POSTGRES_PORT
POSTGRES_USER
POSTGRES_PASSWORD
POSTGRES_DB
POSTGRES_PORT


tool/.setting.yaml

```yaml
# SettingsYaml settings file
POSTGRES_HOST: localhost
POSTGRES_PORT: 15432
POSTGRES_USER: conduit_test_user
POSTGRES_PASSWORD: conduit!
POSTGRES_DB: conduit_test_db
```



If you have installed postgres yourself then you will need to create the test db:

```bash
psql -c 'create user conduit_test_user with createdb;' -U postgres
psql -c "alter user conduit_test_user with password 'conduit!';" -U postgres
psql -c 'create database conduit_test_db;' -U postgres
psql -c 'grant all on database conduit_test_db to conduit_test_user;' -U postgres
```

# Running unit tests manually

Before you can manually run the unit tests you MUST have configured your postgres db as described above.


Run all tests with the following command:

```
pub run test -j 1
```


# Running individual unit tests

If you need to run an individual unit tests that requires the test postgres db, can use:

```
tool/start_db.dart
```

You need to have either run tool/setup_unit_tests.dart to correctly configure the db settings.