#!/bin/bash

set -e

psql -c 'create user conduit_test_user with createdb;' -U postgres
psql -c "alter user conduit_test_user with password 'conduit!';" -U postgres
psql -c 'create database conduit_test_db;' -U postgres
psql -c 'grant all on database conduit_test_db to conduit_test_user;' -U postgres

cd "$TEST_DIR"

pub get

$RUNNER_CMD $RUNNER_ARGS

#if [[ "$TRAVIS_BUILD_STAGE_NAME" == "coverage" && "$TRAVIS_BRANCH" == "master" && "$TRAVIS_PULL_REQUEST" == false ]]; then
#  pub global activate -sgit https://github.com/stablekernel/conduit-coverage-tool.git
#  pub global run conduit_coverage_tool:main
#fi

cd ..
