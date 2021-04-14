import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dcli/dcli.dart';
import 'package:path/path.dart';

late final defaultDocPath =
    join(DartProject.current.pathToProjectRoot, 'doc', 'gitbook', 'source');

late final buildPath =
    join(DartProject.current.pathToProjectRoot, 'doc', 'gitbook', 'build');

/// This script is intended to update the .md files with any links to the api documentaiton
///
/// I suspect this script is no longer in use as I can't find any links in the doco that
/// would need to be updated.
///
/// For the moment we intend editing the .md files directly via gitbooks

Future main(List<String> args) async {
  var options = ArgParser(allowTrailingOptions: false)
    ..addOption("base-ref-url",
        abbr: "b",
        help: "Base URL of API reference",
        defaultsTo: "https://pub.dev/documentation/conduit/latest/")
    ..addOption("source-branch",
        abbr: "s",
        help: "Branch of Conduit to generate API reference from.",
        defaultsTo: "master")
    ..addOption("input",
        abbr: "i",
        help:
            "Root directory of documentation. Defaults to subdirectory $defaultDocPath with mkdocs.yaml.",
        defaultsTo: defaultDocPath)
    ..addOption("output",
        abbr: "o",
        help:
            "Where to output built site. Directory created if does not exist.",
        defaultsTo: buildPath)
    ..addFlag("help", abbr: "h", help: "Shows this", negatable: false);

  var parsed = options.parse(args);
  // ignore: unused_local_variable
  var preparer = Preparer(parsed["input"] as String, parsed["output"] as String,
      parsed["source-branch"] as String, parsed["base-ref-url"] as String);

  printerr(red(
      'This script is no longer in use. Read the comments at the top of the script'));
  exit(1);
  // await preparer.prepare();
}

class Preparer {
  Preparer(String inputDirectoryPath, String outputDirectoryPath,
      this.sourceBranch, String baseRefURL) {
    inputDirectory = inputDirectoryPath;
    outputDirectory = outputDirectoryPath;
    baseReferenceURL = Uri.parse(baseRefURL);
  }

  late final Uri baseReferenceURL;
  late final String inputDirectory;
  late final String outputDirectory;

  List<Transformer> transformers = <Transformer>[];
  String sourceBranch;
  Map<String, Map<String, List<SymbolResolution>>> symbolMap = {};
  List<String> blacklist = ["build"];

  Future cleanup() async {
    deleteDir(outputDirectory, recursive: true);
  }

  Future prepare() async {
    try {
      if (!exists(outputDirectory)) {
        createDir(outputDirectory, recursive: true);
      } else {
        deleteDir(outputDirectory, recursive: true);
        createDir(outputDirectory, recursive: true);
      }

      symbolMap = await generateSymbolMap();

      transformers = [
        BlacklistTransformer(blacklist),
        APIReferenceTransformer(symbolMap, baseReferenceURL)
      ];

      await transformDirectory(inputDirectory, outputDirectory);

      "mkdocs build"
          .start(workingDirectory: join(pwd, outputDirectory, "docs"));

      var builtDocsPath = join(outputDirectory, "docs", "site");
      var finalDocsPath = join(outputDirectory, "docs");
      var tempDocsPath = join(outputDirectory, "docs_tmp");
      moveDir(builtDocsPath, tempDocsPath);
      deleteDir(finalDocsPath, recursive: true);
      moveDir(tempDocsPath, finalDocsPath);
    } catch (e, st) {
      print("$e $st");
      await cleanup();
      exitCode = 1;
    }
  }

  Future transformDirectory(String sourcePath, String destinationPath) async {
    if (!exists(destinationPath)) {
      createDir(destinationPath, recursive: true);
    }

    var files =
        find('*.*', workingDirectory: sourcePath, recursive: false).toList();
    for (var f in files) {
      var filename = split(f).last;

      List<int>? contents;
      for (var transformer in transformers) {
        if (!transformer.shouldIncludeItem(filename)) {
          break;
        }

        if (!transformer.shouldTransformFile(filename)) {
          continue;
        }

        contents = contents ?? File(f).readAsBytesSync();
        contents = await transformer.transform(contents);
      }

      var destinationUri = join(destinationPath, filename);
      if (contents != null) {
        var outFile = File(destinationUri);
        outFile.writeAsBytesSync(contents);
      }
    }

    var subdirectories = find('*.*',
        workingDirectory: sourcePath,
        recursive: false,
        types: [Find.directory]).toList();
    for (var subdirectory in subdirectories) {
      var dirName = dirname(subdirectory);
      String? destinationDir = join(destinationPath, "$dirName");

      for (var t in transformers) {
        if (!t.shouldConsiderDirectories) {
          continue;
        }

        if (!t.shouldIncludeItem(dirName)) {
          destinationDir = null;
          break;
        }
      }

      if (destinationDir != null) {
        createDir(destinationDir);
        await transformDirectory(subdirectory, destinationDir);
      }
    }
  }

  /// Generates the dart doc by running 'dartdoc' and then
  /// builds a symbol map from the resulting api documentation.
  Future<Map<String, Map<String, List<SymbolResolution>>>>
      generateSymbolMap() async {
    print("Cloning 'conduit' (${sourceBranch})...");

    "git clone -b $sourceBranch git@github.com:conduit.dart/conduit.git"
        .start(workingDirectory: outputDirectory);

    print("Generating API reference...");
    var sourceDir = join(outputDirectory, "conduit");
    "dartdoc".start(workingDirectory: sourceDir);

    print("Building symbol map...");
    var indexFile = File(join(sourceDir, "doc", "api", "index.json"));
    List<Map<String, dynamic>> indexJSON = json
        .decode(await indexFile.readAsString()) as List<Map<String, dynamic>>;
    var libraries = indexJSON
        .where((m) => m["type"] == "library")
        .map((lib) => lib["qualifiedName"])
        .toList();

    List<SymbolResolution> resolutions = indexJSON
        .where((m) => m["type"] != "library")
        .map((obj) => SymbolResolution.fromMap(obj))
        .toList();

    var qualifiedMap = <String, List<SymbolResolution>>{};
    var nameMap = <String, List<SymbolResolution>>{};
    resolutions.forEach((resolution) {
      if (!nameMap.containsKey(resolution.name)) {
        nameMap[resolution.name!] = [resolution];
      } else {
        nameMap[resolution.name]!.add(resolution);
      }

      var qualifiedKey =
          libraries.fold(resolution.qualifiedName, (String? p, e) {
        return p!.replaceFirst("${e}.", "");
      });
      if (!qualifiedMap.containsKey(qualifiedKey)) {
        qualifiedMap[qualifiedKey!] = [resolution];
      } else {
        qualifiedMap[qualifiedKey]!.add(resolution);
      }
    });

    deleteDir(sourceDir, recursive: true);

    return {"qualified": qualifiedMap, "name": nameMap};
  }
}

class SymbolResolution {
  SymbolResolution.fromMap(Map<String, dynamic> map) {
    name = map["name"] as String;
    qualifiedName = map["qualifiedName"] as String;
    link = map["href"] as String;
    type = map["type"] as String;
  }

  late final String? name;
  late final String? qualifiedName;
  late final String? type;
  late final String? link;

  @override
  String toString() => "$name: $qualifiedName $link $type";
}

abstract class Transformer {
  bool shouldTransformFile(String filename) => true;
  bool get shouldConsiderDirectories => false;
  bool shouldIncludeItem(String filename) => true;
  Future<List<int>> transform(List<int> inputContents) async => inputContents;
}

class BlacklistTransformer extends Transformer {
  BlacklistTransformer(this.blacklist);
  List<String> blacklist;

  @override
  bool get shouldConsiderDirectories => true;

  @override
  bool shouldIncludeItem(String filename) {
    if (filename.startsWith(".")) {
      return false;
    }

    for (var b in blacklist) {
      if (b == filename) {
        return false;
      }
    }

    return true;
  }
}

/// Transforms .md files. Replacing any
class APIReferenceTransformer extends Transformer {
  APIReferenceTransformer(this.symbolMap, this.baseReferenceURL);

  Uri baseReferenceURL;
  final RegExp regex = RegExp("`([A-Za-z0-9_\\.\\<\\>@\\(\\)]+)`");
  Map<String, Map<String, List<SymbolResolution>>> symbolMap;

  @override
  bool shouldTransformFile(String filename) {
    return filename.endsWith(".md");
  }

  @override
  Future<List<int>> transform(List<int> inputContents) async {
    var contents = utf8.decode(inputContents);

    var matches = regex.allMatches(contents).toList().reversed;

    matches.forEach((match) {
      var symbol = match.group(1)!;
      var resolution = bestGuessForSymbol(symbol);
      if (resolution != null) {
        symbol = symbol.replaceAll("<", "&lt;").replaceAll(">", "&gt;");
        var replacement = constructedReferenceURLFrom(
            baseReferenceURL, resolution.link!.split("/"));
        contents = contents.replaceRange(
            match.start, match.end, "<a href=\"$replacement\">${symbol}</a>");
      } else {
//        missingSymbols.add(symbol);
      }
    });

    return utf8.encode(contents);
  }

  SymbolResolution? bestGuessForSymbol(String symbol) {
    if (symbolMap.isEmpty) {
      return null;
    }

    var _symbol = symbol;
    _symbol =
        _symbol.replaceAll("<T>", "").replaceAll("@", "").replaceAll("()", "");

    var possible = symbolMap["qualified"]?[_symbol];
    possible ??= symbolMap["name"]?[_symbol];

    if (possible == null) {
      return null;
    }

    if (possible.length == 1) {
      return possible.first;
    }

    return possible.firstWhere((r) => r.type == "class",
        orElse: () => possible!.first);
  }
}

Uri constructedReferenceURLFrom(Uri base, List<String> relativePathComponents) {
  var subdirectories =
      relativePathComponents.sublist(0, relativePathComponents.length - 1);
  Uri enclosingDir = subdirectories.fold(base, (Uri prev, elem) {
    return prev.resolve("${elem}/");
  });

  return enclosingDir.resolve(relativePathComponents.last);
}
