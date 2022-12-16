# Deploy on a Local Machine

## Before You Begin

This guide requires that you have created a Conduit project. If not, please refer to the first part of the [Tutorial](../tut/getting-started.md).

## Overview

1. Create a local database.
2. Upload the application schema to the local database.
3. Add an OAuth 2.0 client.
4. Modify the configuration file.
5. Run the application.

## Step 1: Create a Local Database

Create a database with the same name as your application and a user that can access that database. Run the following SQL locally with a user that has privileges to create databases.

```sql
CREATE DATABASE app_name;
CREATE USER app_name_user WITH CREATEDB;
ALTER USER app_name_user WITH PASSWORD 'yourpassword';
GRANT ALL ON DATABASE app_name TO app_name_user;
```

!!! warning "dart\_test database" Do not use the name 'dart\_test' for the database; this database is used by Conduit to run tests by default.

## Step 2: Upload the Application Schema

If you have not yet created database migration files for your project, run the database schema generation tool from the project directory:

```bash
conduit db generate
```

This command creates the file `migrations/00000001_initial.migration.dart`. Now, run the database migration tool to execute the migration file against the local database. Ensure that the values for the option `--connect` match those of the database created in the last step.

```bash
conduit db upgrade --connect postgres://app_name_user:yourpassword@localhost:5432/app_name
```

\(Note that you may provide database credentials in a file named `database.yaml` instead of using `--connect`. See `conduit db --help` for details.\)

## Step 3: Add an OAuth 2.0 client.

If you are using `package:conduit_core/managed_auth`, you'll want to create an OAuth2 client identifier. From the command line, run the following, ensuring that the values for the option `--connect` match the recently created database.

```bash
conduit auth add-client --id com.app_name.standard --secret abcdefghi --connect postgres://app_name_user:yourpassword@localhost:5432/app_name
```

## Step 4: Modify the Configuration File

If `config.yaml` doesn't exist, create it by copying the configuration file template `config.yaml.src`.

In `config.yaml`, update the database credentials to the local database.

```yaml
database:
 username: app_name_user
 password: yourpassword
 host: localhost
 port: 5432
 databaseName: app_name
```

## Step 5: Run the Application

From the project directory, run:

```bash
conduit serve
```

Your application is now running. You may also run the generated start script in your project's `bin` directory:

```bash
dart bin/main.dart
```

If you restart the application, the data in your database will remain.

