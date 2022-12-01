import 'dart:io';

import 'package:conduit_config/conduit_config.dart';
import 'package:test/test.dart';

void main() {
  test("Success case", () {
    const yamlString = "port: 80\n"
        "name: foobar\n"
        "database:\n"
        "  host: stablekernel.com\n"
        "  username: bob\n"
        "  password: fred\n"
        "  databaseName: dbname\n"
        "  port: 5000";

    var t = TopLevelConfiguration.fromString(yamlString);
    expect(t.port, 80);
    expect(t.name, "foobar");
    expect(t.database.host, "stablekernel.com");
    expect(t.database.username, "bob");
    expect(t.database.password, "fred");
    expect(t.database.databaseName, "dbname");
    expect(t.database.port, 5000);

    final asMap = {
      "port": 80,
      "name": "foobar",
      "database": {
        "host": "stablekernel.com",
        "username": "bob",
        "password": "fred",
        "databaseName": "dbname",
        "port": 5000
      }
    };
    t = TopLevelConfiguration.fromMap(asMap);
    expect(t.port, 80);
    expect(t.name, "foobar");
    expect(t.database.host, "stablekernel.com");
    expect(t.database.username, "bob");
    expect(t.database.password, "fred");
    expect(t.database.databaseName, "dbname");
    expect(t.database.port, 5000);
  });

  test("Configuration subclasses success case", () {
    const yamlString = "port: 80\n"
        "extraValue: 2\n"
        "database:\n"
        "  host: stablekernel.com\n"
        "  username: bob\n"
        "  password: fred\n"
        "  databaseName: dbname\n"
        "  port: 5000\n"
        "  extraDatabaseValue: 3";

    var t = ConfigurationSubclass.fromString(yamlString);
    expect(t.port, 80);
    expect(t.extraValue, 2);
    expect(t.database.host, "stablekernel.com");
    expect(t.database.username, "bob");
    expect(t.database.password, "fred");
    expect(t.database.databaseName, "dbname");
    expect(t.database.port, 5000);
    expect(t.database.extraDatabaseValue, 3);

    final asMap = {
      "port": 80,
      "extraValue": 2,
      "database": {
        "host": "stablekernel.com",
        "username": "bob",
        "password": "fred",
        "databaseName": "dbname",
        "port": 5000,
        "extraDatabaseValue": 3
      }
    };
    t = ConfigurationSubclass.fromMap(asMap);
    expect(t.port, 80);
    expect(t.extraValue, 2);
    expect(t.database.host, "stablekernel.com");
    expect(t.database.username, "bob");
    expect(t.database.password, "fred");
    expect(t.database.databaseName, "dbname");
    expect(t.database.port, 5000);
    expect(t.database.extraDatabaseValue, 3);
  });

  test("Extra property", () {
    try {
      const yamlString = "port: 80\n"
          "name: foobar\n"
          "extraKey: 2\n"
          "database:\n"
          "  host: stablekernel.com\n"
          "  username: bob\n"
          "  password: fred\n"
          "  databaseName: dbname\n"
          "  port: 5000";

      final _ = TopLevelConfiguration.fromString(yamlString);
      fail('unreachable');
    } on ConfigurationException catch (e) {
      expect(
        e.toString(),
        allOf([
          contains("TopLevelConfiguration"),
          contains("unexpected keys found"),
          contains("'extraKey'")
        ]),
      );
    }

    try {
      final asMap = {
        "port": 80,
        "name": "foobar",
        "extraKey": 2,
        "database": {
          "host": "stablekernel.com",
          "username": "bob",
          "password": "fred",
          "databaseName": "dbname",
          "port": 5000
        }
      };
      final _ = TopLevelConfiguration.fromMap(asMap);
      fail('unreachable');
    } on ConfigurationException catch (e) {
      expect(
        e.toString(),
        allOf([
          contains("TopLevelConfiguration"),
          contains("unexpected keys found"),
          contains("'extraKey'")
        ]),
      );
    }
  });

  test("Missing required top-level (annotated property)", () {
    try {
      const yamlString = "name: foobar\n"
          "database:\n"
          "  host: stablekernel.com\n"
          "  username: bob\n"
          "  password: fred\n"
          "  databaseName: dbname\n"
          "  port: 5000";

      final _ = TopLevelConfiguration.fromString(yamlString);
      fail("Should not succeed");
    } on ConfigurationException catch (e) {
      expect(
        e.toString(),
        allOf([
          contains("missing required"),
          contains("TopLevelConfiguration"),
          contains("'port'")
        ]),
      );
    }

    try {
      final asMap = {
        "name": "foobar",
        "database": {
          "host": "stablekernel.com",
          "username": "bob",
          "password": "fred",
          "databaseName": "dbname",
          "port": 5000
        }
      };
      final _ = TopLevelConfiguration.fromMap(asMap);
      fail("Should not succeed");
    } on ConfigurationException catch (e) {
      expect(
        e.toString(),
        allOf([
          contains("missing required"),
          contains("TopLevelConfiguration"),
          contains("'port'")
        ]),
      );
    }
  });

  test("Missing required top-level (default unannotated property)", () {
    try {
      const yamlString = "port: 80\n"
          "name: foobar\n";
      final _ = TopLevelConfiguration.fromString(yamlString);
      fail("Should not succeed");
    } on ConfigurationException catch (e) {
      expect(
        e.toString(),
        allOf([
          contains("missing required"),
          contains("TopLevelConfiguration"),
          contains("'database'")
        ]),
      );
    }

    try {
      final asMap = {"port": 80, "name": "foobar"};
      final _ = TopLevelConfiguration.fromMap(asMap);
      fail("Should not succeed");
    } on ConfigurationException catch (e) {
      expect(
        e.toString(),
        allOf([
          contains("missing required"),
          contains("TopLevelConfiguration"),
          contains("'database'")
        ]),
      );
    }
  });

  test("Invalid value for top-level property", () {
    try {
      const yamlString = "name: foobar\n"
          "port: 65536\n";

      final _ = TopLevelConfigurationWithValidation.fromString(yamlString);
      fail("Should not succeed");
    } on ConfigurationException catch (e) {
      expect(e.toString(), contains("TopLevelConfigurationWithValidation"));
      expect(e.toString(), contains("port"));
      expect(e.toString(), contains("65536"));
    }

    try {
      final asMap = {"name": "foobar", "port": 65536};
      final _ = TopLevelConfigurationWithValidation.fromMap(asMap);
      fail("Should not succeed");
    } on ConfigurationException catch (e) {
      expect(e.toString(), contains("TopLevelConfigurationWithValidation"));
      expect(e.toString(), contains("port"));
      expect(e.toString(), contains("65536"));
    }
  });

  test("Missing required top-level from superclass", () {
    try {
      const yamlString = "name: foobar\n"
          "extraValue: 2\n"
          "database:\n"
          "  host: stablekernel.com\n"
          "  username: bob\n"
          "  password: fred\n"
          "  databaseName: dbname\n"
          "  port: 5000\n"
          "  extraDatabaseValue: 3";

      final _ = ConfigurationSubclass.fromString(yamlString);
      fail("unreachable");
    } on ConfigurationException catch (e) {
      expect(
        e.toString(),
        allOf([
          contains("missing required"),
          contains("ConfigurationSubclass"),
          contains("'port'")
        ]),
      );
    }

    try {
      final asMap = {
        "name": "foobar",
        "extraValue": 2,
        "database": {
          "host": "stablekernel.com",
          "username": "bob",
          "password": "fred",
          "databaseName": "dbname",
          "port": 5000,
          "extraDatabaseValue": 3
        }
      };
      final _ = ConfigurationSubclass.fromMap(asMap);
      fail("Should not succeed");
    } on ConfigurationException catch (e) {
      expect(
        e.toString(),
        allOf([
          contains("missing required"),
          contains("ConfigurationSubclass"),
          contains("'port'")
        ]),
      );
    }
  });

  test("Missing required top-level from subclass", () {
    try {
      const yamlString = "name: foobar\n"
          "port: 80\n"
          "database:\n"
          "  host: stablekernel.com\n"
          "  username: bob\n"
          "  password: fred\n"
          "  databaseName: dbname\n"
          "  port: 5000\n"
          "  extraDatabaseValue: 3";

      final _ = ConfigurationSubclass.fromString(yamlString);
      fail("Should not succeed");
    } on ConfigurationException catch (e) {
      expect(
        e.toString(),
        allOf([
          contains("missing required"),
          contains("ConfigurationSubclass"),
          contains("'extraValue'")
        ]),
      );
    }

    try {
      final asMap = {
        "name": "foobar",
        "port": 80,
        "database": {
          "host": "stablekernel.com",
          "username": "bob",
          "password": "fred",
          "databaseName": "dbname",
          "port": 5000,
          "extraDatabaseValue": 3
        }
      };
      final _ = ConfigurationSubclass.fromMap(asMap);
      fail("Should not succeed");
    } on ConfigurationException catch (e) {
      expect(
        e.toString(),
        allOf([
          contains("missing required"),
          contains("ConfigurationSubclass"),
          contains("'extraValue'")
        ]),
      );
    }
  });

  test("Missing required nested property from superclass", () {
    try {
      const yamlString = "port: 80\n"
          "name: foobar\n"
          "extraValue: 2\n"
          "database:\n"
          "  host: stablekernel.com\n"
          "  username: bob\n"
          "  password: fred\n"
          "  databaseName: dbname\n"
          "  extraDatabaseValue: 3";

      final _ = ConfigurationSubclass.fromString(yamlString);
      fail("Should not succeed");
    } on ConfigurationException catch (e) {
      expect(
        e.toString(),
        allOf([
          contains("missing required"),
          contains("ConfigurationSubclass"),
          contains("'port'")
        ]),
      );
    }

    try {
      final asMap = {
        "port": 80,
        "name": "foobar",
        "extraValue": 2,
        "database": {
          "host": "stablekernel.com",
          "username": "bob",
          "password": "fred",
          "databaseName": "dbname",
          "extraDatabaseValue": 3
        }
      };
      final _ = ConfigurationSubclass.fromMap(asMap);
      fail("Should not succeed");
    } on ConfigurationException catch (e) {
      expect(
        e.toString(),
        allOf([
          contains("missing required"),
          contains("ConfigurationSubclass"),
          contains("'port'")
        ]),
      );
    }
  });

  test("Missing required nested property from subclass", () {
    try {
      const yamlString = "port: 80\n"
          "name: foobar\n"
          "extraValue: 2\n"
          "database:\n"
          "  host: stablekernel.com\n"
          "  username: bob\n"
          "  password: fred\n"
          "  databaseName: dbname\n"
          "  port: 5000\n";

      final _ = ConfigurationSubclass.fromString(yamlString);
      fail("Should not succeed");
    } on ConfigurationException catch (e) {
      expect(
        e.toString(),
        allOf([
          contains("missing required"),
          contains("ConfigurationSubclass"),
          contains("'extraDatabaseValue'")
        ]),
      );
    }

    try {
      final asMap = {
        "port": 80,
        "name": "foobar",
        "extraValue": 2,
        "database": {
          "host": "stablekernel.com",
          "username": "bob",
          "password": "fred",
          "databaseName": "dbname",
          "port": 5000,
        }
      };
      final _ = ConfigurationSubclass.fromMap(asMap);
      fail("Should not succeed");
    } on ConfigurationException catch (e) {
      expect(
        e.toString(),
        allOf([
          contains("missing required"),
          contains("ConfigurationSubclass"),
          contains("'extraDatabaseValue'")
        ]),
      );
    }
  });

  test("Validation of the value of property from subclass", () {
    try {
      const yamlString = "port: 80\n"
          "name: foobar\n"
          "database:\n"
          "  host: not a host.com\n"
          "  username: bob\n"
          "  password: fred\n"
          "  databaseName: dbname\n"
          "  port: 5000\n";

      final _ = ConfigurationSubclassWithValidation.fromString(yamlString);
      fail("Should not succeed");
    } on ConfigurationException catch (e) {
      expect(
        e.toString(),
        allOf([
          contains("ConfigurationSubclassWithValidation"),
          contains("not a host.com")
        ]),
      );
    }

    try {
      final asMap = {
        "port": 80,
        "name": "foobar",
        "database": {
          "host": "not a host.com",
          "username": "bob",
          "password": "fred",
          "databaseName": "dbname",
          "port": 5000,
        }
      };
      final _ = ConfigurationSubclassWithValidation.fromMap(asMap);
      fail("Should not succeed");
    } on ConfigurationException catch (e) {
      expect(
        e.toString(),
        allOf([
          contains("ConfigurationSubclassWithValidation"),
          contains("not a host.com")
        ]),
      );
    }
  });

  test("Optional can be missing", () {
    const yamlString = "port: 80\n"
        "database:\n"
        "  host: stablekernel.com\n"
        "  username: bob\n"
        "  password: fred\n"
        "  databaseName: dbname\n"
        "  port: 5000";

    var t = TopLevelConfiguration.fromString(yamlString);
    expect(t.port, 80);
    expect(t.name, isNull);
    expect(t.database.host, "stablekernel.com");
    expect(t.database.username, "bob");
    expect(t.database.password, "fred");
    expect(t.database.databaseName, "dbname");
    expect(t.database.port, 5000);

    final asMap = {
      "port": 80,
      "database": {
        "host": "stablekernel.com",
        "username": "bob",
        "password": "fred",
        "databaseName": "dbname",
        "port": 5000
      }
    };
    t = TopLevelConfiguration.fromMap(asMap);
    expect(t.port, 80);
    expect(t.name, isNull);
    expect(t.database.host, "stablekernel.com");
    expect(t.database.username, "bob");
    expect(t.database.password, "fred");
    expect(t.database.databaseName, "dbname");
    expect(t.database.port, 5000);
  });

  test("Nested optional can be missing", () {
    const yamlString = "port: 80\n"
        "name: foobar\n"
        "database:\n"
        "  host: stablekernel.com\n"
        "  password: fred\n"
        "  databaseName: dbname\n"
        "  port: 5000";

    var t = TopLevelConfiguration.fromString(yamlString);
    expect(t.port, 80);
    expect(t.name, "foobar");
    expect(t.database.host, "stablekernel.com");
    expect(t.database.username, isNull);
    expect(t.database.password, "fred");
    expect(t.database.databaseName, "dbname");
    expect(t.database.port, 5000);

    final asMap = {
      "port": 80,
      "name": "foobar",
      "database": {
        "host": "stablekernel.com",
        "password": "fred",
        "databaseName": "dbname",
        "port": 5000
      }
    };
    t = TopLevelConfiguration.fromMap(asMap);
    expect(t.port, 80);
    expect(t.name, "foobar");
    expect(t.database.host, "stablekernel.com");
    expect(t.database.username, isNull);
    expect(t.database.password, "fred");
    expect(t.database.databaseName, "dbname");
    expect(t.database.port, 5000);
  });

  test("Nested required cannot be missing", () {
    try {
      const yamlString = "port: 80\n"
          "name: foobar\n"
          "database:\n"
          "  host: stablekernel.com\n"
          "  password: fred\n"
          "  port: 5000";

      final _ = TopLevelConfiguration.fromString(yamlString);
      fail("Should not succeed");
    } on ConfigurationException catch (e) {
      expect(
        e.toString(),
        allOf([
          contains("missing"),
          contains("TopLevelConfiguration"),
          contains("'databaseName'")
        ]),
      );
    }

    try {
      final asMap = {
        "port": 80,
        "name": "foobar",
        "database": {
          "host": "stablekernel.com",
          "password": "fred",
          "port": 5000
        }
      };
      final _ = TopLevelConfiguration.fromMap(asMap);
      fail("Should not succeed");
    } on ConfigurationException catch (e) {
      expect(
        e.toString(),
        allOf([
          contains("missing"),
          contains("TopLevelConfiguration"),
          contains("'databaseName'")
        ]),
      );
    }
  });

  test("Map and list cases", () {
    const yamlString = "strings:\n"
        "-  abcd\n"
        "-  efgh\n"
        "databaseRecords:\n"
        "- databaseName: db1\n"
        "  port: 1000\n"
        "  host: stablekernel.com\n"
        "- username: bob\n"
        "  databaseName: db2\n"
        "  port: 2000\n"
        "  host: stablekernel.com\n"
        "integers:\n"
        "  first: 1\n"
        "  second: 2\n"
        "databaseMap:\n"
        "  db1:\n"
        "    host: stablekernel.com\n"
        "    databaseName: db1\n"
        "    port: 1000\n"
        "  db2:\n"
        "    username: bob\n"
        "    databaseName: db2\n"
        "    port: 2000\n"
        "    host: stablekernel.com\n";

    final special = SpecialInfo.fromString(yamlString);
    expect(special.strings, ["abcd", "efgh"]);
    expect(special.databaseRecords.first.host, "stablekernel.com");
    expect(special.databaseRecords.first.databaseName, "db1");
    expect(special.databaseRecords.first.port, 1000);

    expect(special.databaseRecords.last.username, "bob");
    expect(special.databaseRecords.last.databaseName, "db2");
    expect(special.databaseRecords.last.port, 2000);
    expect(special.databaseRecords.last.host, "stablekernel.com");

    expect(special.integers["first"], 1);
    expect(special.integers["second"], 2);
    expect(special.databaseMap["db1"]!.databaseName, "db1");
    expect(special.databaseMap["db1"]!.host, "stablekernel.com");
    expect(special.databaseMap["db1"]!.port, 1000);
    expect(special.databaseMap["db2"]!.username, "bob");
    expect(special.databaseMap["db2"]!.databaseName, "db2");
    expect(special.databaseMap["db2"]!.port, 2000);
    expect(special.databaseMap["db2"]!.host, "stablekernel.com");
  });

  test("From file works the same", () {
    const yamlString = "port: 80\n"
        "name: foobar\n"
        "database:\n"
        "  host: stablekernel.com\n"
        "  username: bob\n"
        "  password: fred\n"
        "  databaseName: dbname\n"
        "  port: 5000";

    final file = File("tmp.yaml");
    file.writeAsStringSync(yamlString);

    final t = TopLevelConfiguration.fromFile(File("tmp.yaml"));
    expect(t.port, 80);
    expect(t.name, "foobar");
    expect(t.database.host, "stablekernel.com");
    expect(t.database.username, "bob");
    expect(t.database.password, "fred");
    expect(t.database.databaseName, "dbname");
    expect(t.database.port, 5000);

    file.deleteSync();
  });

  test("Optional nested ConfigurationItem can be omitted", () {
    var yamlString = "port: 80";

    var config = OptionalEmbeddedContainer.fromString(yamlString);
    expect(config.port, 80);
    expect(config.database, isNull);

    yamlString = "port: 80\n"
        "database:\n"
        "  host: here\n"
        "  port: 90\n"
        "  databaseName: db";

    config = OptionalEmbeddedContainer.fromString(yamlString);
    expect(config.port, 80);
    expect(config.database!.host, "here");
    expect(config.database!.port, 90);
    expect(config.database!.databaseName, "db");
  });

  test("Optional nested ConfigurationItem obeys required items", () {
    // Missing host intentionally
    const yamlString = "port: 80\n"
        "database:\n"
        "  port: 90\n"
        "  databaseName: db";

    try {
      final _ = OptionalEmbeddedContainer.fromString(yamlString);
      fail('unreachable');
    } on ConfigurationException catch (_) {}
  });

  test("Database configuration can come from string", () {
    const yamlString = "port: 80\n"
        "database: 'postgres://dart:pw@host:5432/dbname'\n";

    final values = OptionalEmbeddedContainer.fromString(yamlString);
    expect(values.port, 80);
    expect(values.database!.username, "dart");
    expect(values.database!.password, "pw");
    expect(values.database!.port, 5432);
    expect(values.database!.databaseName, "dbname");
  });

  test(
      "Database configuration as a string can contain an URL-encoded authority",
      () {
    const yamlString = "port: 80\n"
        "database: 'postgres://dart%40google.com:pass%23word@host:5432/dbname'\n";

    final values = OptionalEmbeddedContainer.fromString(yamlString);
    expect(values.database!.username, "dart@google.com");
    expect(values.database!.password, "pass#word");
  });

  test("Omitting optional values in a 'decoded' config still returns succees",
      () {
    const yamlString = "port: 80\n"
        "database: 'postgres://host:5432/dbname'\n";

    final values = OptionalEmbeddedContainer.fromString(yamlString);
    expect(values.port, 80);
    expect(values.database!.username, isNull);
    expect(values.database!.password, isNull);
    expect(values.database!.port, 5432);
    expect(values.database!.databaseName, "dbname");
  });

  test("Not including required values in a 'decoded' config still yields error",
      () {
    const yamlString = "port: 80\n"
        "database: 'postgres://dart:pw@host:5432'\n";

    try {
      final _ = OptionalEmbeddedContainer.fromString(yamlString);
      expect(true, false);
    } on ConfigurationException catch (e) {
      expect(
        e.toString(),
        allOf([
          contains("missing"),
          contains("OptionalEmbeddedContainer"),
          contains("'databaseName'")
        ]),
      );
    }
  });

  test("Environment variable escape values read from Environment", () {
    if (Platform.environment["TEST_BOOL"] == null ||
        Platform.environment["TEST_VALUE"] == null) {
      fail(
        "This test must be run with environment variables of TEST_VALUE=1 and "
        "TEST_BOOL=true",
      );
    }

    const yamlString = "path: \$PATH\n"
        "optionalDooDad: \$XYZ123\n"
        "testValue: \$TEST_VALUE\n"
        "testBoolean: \$TEST_BOOL";

    final values = EnvironmentConfiguration.fromString(yamlString);
    expect(values.path, Platform.environment["PATH"]);
    expect(values.testValue, int.parse(Platform.environment["TEST_VALUE"]!));
    expect(values.testBoolean, true);
    expect(values.optionalDooDad, isNull);
  });

  test("Missing environment variables throw required error", () {
    const yamlString = "value: \$MISSING_ENV_VALUE";
    try {
      final _ = EnvFail.fromString(yamlString);
      fail("unreachable");
    } on ConfigurationException catch (e) {
      expect(e.message, contains("missing required key(s): 'value'"));
    }
  });

  test("Private variables get ignored", () {
    final values = PrivateVariableConfiguration.fromString("value: 1");
    expect(values.value, 1);
    expect(values._privateVariable, null);

    try {
      final _ = PrivateVariableConfiguration.fromString(
        "value: 1\n"
        "_privateVariable: something",
      );
      fail("unreachable");
    } on ConfigurationException catch (e) {
      expect(e.message, contains("unexpected keys found: '_privateVariable'"));
    }
  });

  test("DatabaseConfiguration can be read from connection string", () {
    if (Platform.environment["TEST_DB_ENV_VAR"] == null) {
      fail(
        "This test must be run with environment variables of "
        "TEST_DB_ENV_VAR=postgres://user:password@host:5432/dbname",
      );
    }

    const yamlString = "port: 80\ndatabase: \$TEST_DB_ENV_VAR";
    final dbConfig = TopLevelConfiguration.fromString(yamlString).database;
    expect(dbConfig.username, "user");
    expect(dbConfig.password, "password");
    expect(dbConfig.host, "host");
    expect(dbConfig.port, 5432);
    expect(dbConfig.databaseName, "dbname");
  });

  test(
      "Assigning value of incorrect type to parsed integer emits error and field name",
      () {
    const yamlString = "port: foobar\n"
        "name: foobar\n"
        "database:\n"
        "  host: stablekernel.com\n"
        "  username: bob\n"
        "  password: fred\n"
        "  databaseName: dbname\n"
        "  port: 5000";

    try {
      TopLevelConfiguration.fromString(yamlString);
      fail('unreachable');
    } on ConfigurationException catch (e) {
      expect(e.toString(), contains("TopLevelConfiguration"));
      expect(e.toString(), contains("port"));
      expect(e.toString(), contains("foobar"));
    }
  });

  test(
      "Assigning value of incorrect type to nested field emits error and field name",
      () {
    const yamlString = "port: 1000\n"
        "name: foobar\n"
        "database:\n"
        "  host: stablekernel.com\n"
        "  username:\n"
        "    - item\n"
        "  password: password\n"
        "  databaseName: dbname\n"
        "  port: 5000";

    try {
      TopLevelConfiguration.fromString(yamlString);
      fail('unreachable');
    } on ConfigurationException catch (e) {
      expect(e.toString(), contains("TopLevelConfiguration"));
      expect(e.toString(), contains("database.username"));
      expect(e.toString(), contains("input is wrong type"));
    }
  });

  test("Can read boolean values without quotes", () {
    const yamlTrue = "value: true";
    const yamlFalse = "value: false";

    final cfgTrue = BoolConfig.fromString(yamlTrue);
    expect(cfgTrue.value, true);

    final cfgFalse = BoolConfig.fromString(yamlFalse);
    expect(cfgFalse.value, false);
  });

  test("Default values can be assigned in field declaration", () {
    const yaml = "required: foobar";
    final cfg = DefaultValConfig.fromString(yaml);
    expect(cfg.required, "foobar");
    expect(cfg.value, "default");

    const yaml2 = "required: foobar\nvalue: stuff";
    final cfg2 = DefaultValConfig.fromString(yaml2);
    expect(cfg2.required, "foobar");
    expect(cfg2.value, "stuff");
  });
}

class TopLevelConfiguration extends Configuration {
  TopLevelConfiguration();

  TopLevelConfiguration.fromString(super.contents) : super.fromString();

  TopLevelConfiguration.fromFile(super.file) : super.fromFile();

  TopLevelConfiguration.fromMap(super.map) : super.fromMap();

  late int port;

  String? name;

  late DatabaseConfiguration database;
}

class TopLevelConfigurationWithValidation extends Configuration {
  TopLevelConfigurationWithValidation();

  TopLevelConfigurationWithValidation.fromString(super.contents)
      : super.fromString();

  TopLevelConfigurationWithValidation.fromFile(super.file) : super.fromFile();

  TopLevelConfigurationWithValidation.fromMap(super.map) : super.fromMap();

  late int port;

  String? name;

  @override
  void validate() {
    super.validate();
    if (port < 0 || port > 65535) {
      throw ConfigurationException(this, "$port", keyPath: ["port"]);
    }
  }
}

class DatabaseConfigurationSubclass extends DatabaseConfiguration {
  DatabaseConfigurationSubclass();

  late int extraDatabaseValue;
}

class ConfigurationSuperclass extends Configuration {
  ConfigurationSuperclass();

  ConfigurationSuperclass.fromString(super.contents) : super.fromString();

  ConfigurationSuperclass.fromFile(super.file) : super.fromFile();

  ConfigurationSuperclass.fromMap(super.map) : super.fromMap();

  late int port;

  String? name;
}

class ConfigurationSubclass extends ConfigurationSuperclass {
  ConfigurationSubclass();

  ConfigurationSubclass.fromString(super.contents) : super.fromString();

  ConfigurationSubclass.fromFile(super.file) : super.fromFile();

  ConfigurationSubclass.fromMap(super.map) : super.fromMap();

  late int extraValue;

  late DatabaseConfigurationSubclass database;
}

class ConfigurationSubclassWithValidation extends ConfigurationSuperclass {
  ConfigurationSubclassWithValidation();

  ConfigurationSubclassWithValidation.fromString(super.contents)
      : super.fromString();

  ConfigurationSubclassWithValidation.fromFile(super.file) : super.fromFile();

  ConfigurationSubclassWithValidation.fromMap(super.map) : super.fromMap();

  late DatabaseConfigurationSubclassWithValidation database;
}

class DatabaseConfigurationSubclassWithValidation
    extends DatabaseConfiguration {
  DatabaseConfigurationSubclassWithValidation();

  @override
  void validate() {
    super.validate();
    final RegExp validHost = RegExp(
      r"^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$",
    );
    if (!validHost.hasMatch(host)) {
      throw ConfigurationException(this, host, keyPath: ["host"]);
    }
  }
}

class SpecialInfo extends Configuration {
  SpecialInfo();

  SpecialInfo.fromString(super.contents) : super.fromString();

  late List<String> strings;
  late List<DatabaseConfiguration> databaseRecords;
  late Map<String, int> integers;
  late Map<String, DatabaseConfiguration> databaseMap;
}

class OptionalEmbeddedContainer extends Configuration {
  OptionalEmbeddedContainer();

  OptionalEmbeddedContainer.fromString(super.contents) : super.fromString();

  late int port;

  DatabaseConfiguration? database;
}

class EnvironmentConfiguration extends Configuration {
  EnvironmentConfiguration();

  EnvironmentConfiguration.fromString(super.contents) : super.fromString();

  late String path;
  late int testValue;
  late bool testBoolean;

  String? optionalDooDad;
}

class StaticVariableConfiguration extends Configuration {
  StaticVariableConfiguration();

  StaticVariableConfiguration.fromString(super.contents) : super.fromString();

  static late String staticVariable;

  late int value;
}

class PrivateVariableConfiguration extends Configuration {
  PrivateVariableConfiguration();

  PrivateVariableConfiguration.fromString(super.contents) : super.fromString();

  String? _privateVariable;
  late int value;
}

class EnvFail extends Configuration {
  EnvFail();

  EnvFail.fromString(super.contents) : super.fromString();

  late String value;
}

class BoolConfig extends Configuration {
  BoolConfig();
  BoolConfig.fromString(super.contents) : super.fromString();

  late bool value;
}

class DefaultValConfig extends Configuration {
  DefaultValConfig();
  DefaultValConfig.fromString(super.contents) : super.fromString();

  late String required;

  String value = "default";
}
