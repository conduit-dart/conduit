import 'package:args/args.dart' as args;

abstract class Argument {
  void addToParser(args.ArgParser parser);
}

class const Flag(
  final String name, {
  final String? abbr,
  final String? help,
  final bool defaultsTo = false,
  final bool negatable = true,
  final bool hide = false,
}) implements Argument {
  @override
  void addToParser(args.ArgParser parser) {
    parser.addFlag(
      name,
      abbr: abbr,
      help: help,
      defaultsTo: defaultsTo,
      negatable: negatable,
      hide: hide,
    );
  }
}

class Option implements Argument {
  const new(
    this.name, {
    this.abbr,
    this.help,
    this.valueHelp,
    this.allowed,
    this.allowedHelp,
    this.defaultsTo,
    this.hide = false,
  });

  final String name;
  final String? abbr;
  final String? help;
  final String? valueHelp;
  final Iterable<String>? allowed;
  final Map<String, String>? allowedHelp;
  final String? defaultsTo;
  final bool hide;

  @override
  void addToParser(args.ArgParser parser) {
    parser.addOption(
      name,
      abbr: abbr,
      help: help,
      valueHelp: valueHelp,
      allowed: allowed,
      allowedHelp: allowedHelp,
      defaultsTo: defaultsTo,
      hide: hide,
    );
  }
}

class const MultiOption(
  final String name, {
  final String? abbr,
  final String? help,
  final String? valueHelp,
  final Iterable<String>? allowed,
  final Map<String, String>? allowedHelp,
  final Iterable<String>? defaultsTo,
  final bool hide = false,
  final bool splitsCommas = true,
}) implements Argument {
  @override
  void addToParser(args.ArgParser parser) {
    parser.addMultiOption(
      name,
      abbr: abbr,
      help: help,
      valueHelp: valueHelp,
      allowed: allowed,
      allowedHelp: allowedHelp,
      defaultsTo: defaultsTo,
      hide: hide,
      splitCommas: splitsCommas,
    );
  }
}
