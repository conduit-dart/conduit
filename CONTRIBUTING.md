# Contributing
Welcome to the project. All PRs are welcome, though I will be critical of PRs to the best of my ability. I want to find developers who can help check my work and also help foster newcomers so that they can help keep me accountable as well. Thank you for your support. If you have any questions, please reach out on the (discord server)[https://discord.gg/FyJj45NXPx]. If I don't respond on the server, feel free to reach out to me (frosty#1337).

## Branching
If you have a change you want to commit create a branch with the below naming conventions and topic names.
`docs/<description>`
`fix/<username>-<description>`
`feature/<username>-<description>`
`refactor/<username>-<description>`
If the scope of the issue changes for any reason, please rebranch and use the appropriate anming convention.

## Local Testing
While we do provide CI/CD through github actions, it is slow to get results on the CI. You should set up your environment in order to run tests locally before pushing commits
### Setup
To set up your testing environment, a general rule is to follow what is provided in the CI configurations:
```bash
# This can be found in .github/workflows/test.yml
dart pub global activate melos
cd packages/isolate_exec_test_packages/test_package && dart pub get
melos bootstrap
melos cache-source
. ./ci/.env
```
Provide a database with the appropriate configurations. I highly recommend that you (install docker)[https://docs.docker.com/get-docker/] and use the provided docker compose file at [ci/docker-compose.yaml] which sets up a similar database used in the github CI.
### Running Tests
Currently there are three tests that need to be run to hit all the tests:
```bash
melos test-unit
# These two need to be run inside packages/conduit
dart test -j1 -t cli test/*
dart tool/generated_test_runner.dart
```
The first will run all the unit tests in conduit and all its dependencies. The last two test cli components and string-compiled code respectively.

## PR Acceptance Requirements
Please document the intent of the pull request. All non-documentation pull requests must also include automated tests that cover the new code, including failure cases. In the case that tests work locally, but not on the CI, please mention @j4qfrost on the PR. If I don't respond, the best way to contact me is through discord.

## Commits
The project uses [melos](https://pub.dev/packages/melos) for tooling, which provides autoversioning based on [conventional commits](https://www.conventionalcommits.org/en/v1.0.0/). Commits to `master` will usually be squashed from PRs, so make sure that the PR name uses conventional commits to trigger the versioning and publishing CI; you do NOT need to use conventional commits on each commit to your branch.