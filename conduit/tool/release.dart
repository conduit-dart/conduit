import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:conduit_config/conduit_config.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

Future main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag("dry-run")
    ..addFlag("docs-only")
    ..addOption("name")
    ..addOption("config", abbr: "c", defaultsTo: "release.yaml");
  final runner = Runner(parser.parse(args));

  try {
    exitCode = await runner.run();
  } catch (e, st) {
    // ignore: avoid_print
    print("Release failed!");
    // ignore: avoid_print
    print("$e");
    // ignore: avoid_print
    print("$st");
    exitCode = -1;
  } finally {
    await runner.cleanup();
  }
}

class Runner {
  Runner(this.options) {
    configuration = ReleaseConfig(options["config"] as String);
  }

  ArgResults options;
  late ReleaseConfig configuration;
  final List<Function> _cleanup = [];
  bool? get isDryRun => options["dry-run"] as bool?;
  bool? get docsOnly => options["docs-only"] as bool?;
  String? get name => options["name"] as String?;
  Uri baseReferenceURL =
      Uri.parse("https://www.dartdocs.org/documentation/conduit/latest/");

  Future cleanup() async {
    return Future.forEach(_cleanup, (dynamic f) => f());
  }

  Future<int> run() async {
    // Ensure we have all the appropriate command line utilities as a pre-check
    // - git
    // - pub
    // - mkdocs

    if (name == null && !(isDryRun! || docsOnly!)) {
      throw "--name is required.";
    }

    print(
        "Preparing release: '$name'... ${isDryRun! ? "(dry-run)" : ""} ${docsOnly! ? "(docs-only)" : ""}");

    final master = await directoryWithBranch("master");
    String? upcomingVersion;
    String? changeset;
    if (!docsOnly!) {
      final previousVersion = await latestVersion();
      upcomingVersion = await versionFromDirectory(master);
      if (upcomingVersion == previousVersion) {
        throw "Release failed. Version $upcomingVersion already exists.";
      }

      // ignore: avoid_print
      print("Preparing to release $upcomingVersion (from $previousVersion)...");
      changeset = await changesFromDirectory(master, upcomingVersion);
    }

    // Clone docs/source into another directory.
    final docsSource = await directoryWithBranch("docs/source");
    await publishDocs(docsSource, master);

    if (!docsOnly!) {
      await postGithubRelease(upcomingVersion, name, changeset);
      await publish(master);
    }

    return 0;
  }

  Future publishDocs(Directory docSource, Directory code) async {
    final symbolMap = await generateSymbolMap(code);
    final blacklist = ["tools", "build"];
    final transformers = [
      BlacklistTransformer(blacklist),
      APIReferenceTransformer(symbolMap, baseReferenceURL)
    ];

    final docsLive = await directoryWithBranch("gh-pages");
    // ignore: avoid_print
    print("Cleaning ${docsLive.path}...");
    docsLive.listSync().where((fse) {
      if (fse is Directory) {
        final lastPathComponent =
            fse.uri.pathSegments[fse.uri.pathSegments.length - 2];
        return lastPathComponent != ".git";
      } else if (fse is File) {
        return fse.uri.pathSegments.last != ".nojekyll";
      }
      return false;
    }).forEach((fse) {
      fse.deleteSync(recursive: true);
    });

    // ignore: avoid_print
    print("Transforming docs from ${docSource.path} into ${docsLive.path}...");
    await transformDirectory(transformers, docSource, docsLive);

    // ignore: avoid_print
    print("Building /source to /docs site with mkdoc...");
    var process = await Process.start(
        "mkdocs", ["build", "-d", docsLive.uri.resolve("docs").path, "-s"],
        workingDirectory: docsLive.uri.resolve("source").path);
    // ignore: unawaited_futures
    stderr.addStream(process.stderr);
    // ignore: unawaited_futures
    stdout.addStream(process.stdout);
    var exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw "mkdocs failed with exit code $exitCode.";
    }

    final sourceDirectoryInLive =
        Directory.fromUri(docsLive.uri.resolve("source"));
    sourceDirectoryInLive.deleteSync(recursive: true);
    process = await Process.start("git", ["add", "."],
        workingDirectory: docsLive.path);
    // ignore: unawaited_futures
    stderr.addStream(process.stderr);
    // ignore: unawaited_futures
    stdout.addStream(process.stdout);
    exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw "git add in ${docsLive.path} failed with exit code $exitCode.";
    }

    process = await Process.start(
        "git", ["commit", "-m", "commit by release tool"],
        workingDirectory: docsLive.path);
    // ignore: unawaited_futures
    stderr.addStream(process.stderr);
    // ignore: unawaited_futures
    stdout.addStream(process.stdout);
    exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw "git commit in ${docsLive.path} failed with exit code $exitCode.";
    }

    // Push gh-pages to remote
    if (!isDryRun!) {
      // ignore: avoid_print
      print("Pushing gh-pages to remote...");
      final process =
          await Process.start("git", ["push"], workingDirectory: docsLive.path);
      // ignore: unawaited_futures
      stderr.addStream(process.stderr);
      // ignore: unawaited_futures
      stdout.addStream(process.stdout);
      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        throw "git push to ${docsLive.path} failed with exit code $exitCode.";
      }
    }
  }

  Future<Directory> directoryWithBranch(String branchName) async {
    final dir =
        await Directory.current.createTemp(branchName.replaceAll("/", "_"));
    _cleanup.add(() => dir.delete(recursive: true));

    // ignore: avoid_print
    print("Cloning '$branchName' into ${dir.path}...");
    final process = await Process.start("git", [
      "clone",
      "-b",
      branchName,
      "git@github.com:stablekernel/conduit.git",
      dir.path
    ]);
    // ignore: unawaited_futures
    stderr.addStream(process.stderr);
    // ignore: unawaited_futures
    // stdout.addStream(process.stdout);

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw "directoryWithBranch ($branchName) failed with exit code $exitCode.";
    }

    return dir;
  }

  Future<String> latestVersion() async {
    // ignore: avoid_print
    print("Getting latest version...");
    final response = await http.get(
      Uri.parse(
        "https://api.github.com/repos/stablekernel/conduit/releases/latest",
      ),
      headers: {"Authorization": "Bearer ${configuration.githubToken}"},
    );

    if (response.statusCode != 200) {
      throw "latestVersion failed with status code ${response.statusCode}. Reason: ${response.body}";
    }

    final tag = json.decode(response.body)["tag_name"] as String?;
    if (tag == null) {
      throw "latestVersion failed. Reason: no tag found";
    }

    return tag.trim();
  }

  Future<String> versionFromDirectory(Directory directory) async {
    final pubspecFile = File.fromUri(directory.uri.resolve("pubspec.yaml"));
    final yaml = loadYaml(await pubspecFile.readAsString());

    return "v${(yaml["version"] as String).trim()}";
  }

  Future<String> changesFromDirectory(
      Directory directory, String prefixedVersion) async {
    // Strip "v"
    final version = prefixedVersion.substring(1);
    assert(version.split(".").length == 3);

    final regex = RegExp(r"^## ([0-9]+\.[0-9]+\.[0-9]+)", multiLine: true);

    final changelogFile = File.fromUri(directory.uri.resolve("CHANGELOG.md"));
    final changelogContents = await changelogFile.readAsString();
    final versionContentsList = regex.allMatches(changelogContents).toList();
    final latestChangelogVersion = versionContentsList
        .firstWhere((m) => m.group(1) == version, orElse: () {
      throw "Release failed. No entry in CHANGELOG.md for $version.";
    });

    final changeset = changelogContents
        .substring(
            latestChangelogVersion.end,
            versionContentsList[
                    versionContentsList.indexOf(latestChangelogVersion) + 1]
                .start)
        .trim();

    // ignore: avoid_print
    print("Changeset for $prefixedVersion:");
    print(changeset);

    return changeset;
  }

  Future postGithubRelease(
      String? version, String? name, String? description) async {
    final body =
        json.encode({"tag_name": version, "name": name, "body": description});

    // ignore: avoid_print
    print("Tagging GitHub release $version");
    // ignore: avoid_print
    print("- $name");

    if (!isDryRun!) {
      final response = await http.post(
        Uri.parse("https://api.github.com/repos/stablekernel/conduit/releases"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${configuration.githubToken}"
        },
        body: body,
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw "GitHub release tag failed with status code ${response.statusCode}. Reason: ${response.body}.";
      }
    }
  }

  Future publish(Directory master) async {
    // ignore: avoid_print
    print("Formatting code...");
    final fmt = await Process.run("dartfmt", ["-w", "lib/", "bin/"]);
    if (fmt.exitCode != 0) {
      // ignore: avoid_print
      print("WARNING: Failed to run 'dartfmt -w lib/ bin/");
    }

    // ignore: avoid_print
    print("Publishing to pub...");
    final args = ["publish"];
    if (isDryRun!) {
      args.add("--dry-run");
    } else {
      args.add("-f");
    }

    final process =
        await Process.start("pub", args, workingDirectory: master.path);
    // ignore: unawaited_futures
    stderr.addStream(process.stderr);
    // ignore: unawaited_futures
    stdout.addStream(process.stdout);

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw "Publish failed with exit code: $exitCode.";
    }
  }

  Future<Map<String, Map<String?, List<SymbolResolution>>>> generateSymbolMap(
      Directory codeBranchDir) async {
    // ignore: avoid_print
    print("Generating API reference...");
    final process = await Process.start("dartdoc", [],
        workingDirectory: codeBranchDir.path);
    // ignore: unawaited_futures
    stderr.addStream(process.stderr);
    // ignore: unawaited_futures
    stdout.addStream(process.stdout);

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw "Release failed. Generating API reference failed with exit code: $exitCode.";
    }

    // ignore: avoid_print
    print("Building symbol map...");
    final indexFile = File.fromUri(codeBranchDir.uri
        .resolve("doc/")
        .resolve("api/")
        .resolve("index.json"));
    final indexJSON = json.decode(await indexFile.readAsString())
        as List<Map<String, dynamic>>;
    final libraries = indexJSON
        .where((m) => m["type"] == "library")
        .map((lib) => lib["qualifiedName"])
        .toList();

    final List<SymbolResolution> resolutions = indexJSON
        .where((m) => m["type"] != "library")
        .map((obj) => SymbolResolution.fromMap(obj.cast()))
        .toList();

    final qualifiedMap = <String?, List<SymbolResolution>>{};
    final nameMap = <String?, List<SymbolResolution>>{};
    resolutions.forEach((resolution) {
      if (!nameMap.containsKey(resolution.name)) {
        nameMap[resolution.name] = [resolution];
      } else {
        nameMap[resolution.name]!.add(resolution);
      }

      final qualifiedKey =
          libraries.fold(resolution.qualifiedName, (String? p, e) {
        return p!.replaceFirst("$e.", "");
      });
      if (!qualifiedMap.containsKey(qualifiedKey)) {
        qualifiedMap[qualifiedKey] = [resolution];
      } else {
        qualifiedMap[qualifiedKey]!.add(resolution);
      }
    });

    return {"qualified": qualifiedMap, "name": nameMap};
  }

  Future transformDirectory(List<Transformer> transformers, Directory source,
      Directory destination) async {
    final contents = source.listSync();
    final files = contents.whereType<File>();
    for (final f in files) {
      final filename = f.uri.pathSegments.last;

      List<int>? contents;
      for (final transformer in transformers) {
        if (!transformer.shouldIncludeItem(filename)) {
          break;
        }

        if (!transformer.shouldTransformFile(filename)) {
          continue;
        }

        contents = contents ?? f.readAsBytesSync();
        contents = await transformer.transform(contents);
      }

      final destinationUri = destination.uri.resolve(filename);
      if (contents != null) {
        final outFile = File.fromUri(destinationUri);
        outFile.writeAsBytesSync(contents);
      }
    }

    final Iterable<Directory> subdirectories = contents.whereType<Directory>();
    for (final subdirectory in subdirectories) {
      final dirName = subdirectory
          .uri.pathSegments[subdirectory.uri.pathSegments.length - 2];
      Directory? destinationDir =
          Directory.fromUri(destination.uri.resolve(dirName));

      for (final t in transformers) {
        if (!t.shouldConsiderDirectories) {
          continue;
        }

        if (!t.shouldIncludeItem(dirName)) {
          destinationDir = null;
          break;
        }
      }

      if (destinationDir != null) {
        destinationDir.createSync();
        await transformDirectory(transformers, subdirectory, destinationDir);
      }
    }
  }
}

class ReleaseConfig extends Configuration {
  ReleaseConfig(String filename) : super.fromFile(File(filename));

  String? githubToken;
}

//////

class SymbolResolution {
  SymbolResolution.fromMap(Map<String, String> map) {
    name = map["name"];
    qualifiedName = map["qualifiedName"];
    link = map["href"];
    type = map["type"];
  }

  String? name;
  String? qualifiedName;
  String? type;
  String? link;

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

    for (final b in blacklist) {
      if (b == filename) {
        return false;
      }
    }

    return true;
  }
}

class APIReferenceTransformer extends Transformer {
  APIReferenceTransformer(this.symbolMap, this.baseReferenceURL);

  Uri baseReferenceURL;
  final RegExp regex = RegExp("`([A-Za-z0-9_\\.\\<\\>@\\(\\)]+)`");
  Map<String, Map<String?, List<SymbolResolution>>> symbolMap;

  @override
  bool shouldTransformFile(String filename) {
    return filename.endsWith(".md");
  }

  @override
  Future<List<int>> transform(List<int> inputContents) async {
    var contents = utf8.decode(inputContents);

    final matches = regex.allMatches(contents).toList().reversed;

    matches.forEach((match) {
      var symbol = match.group(1);
      final resolution = bestGuessForSymbol(symbol);
      if (resolution != null) {
        symbol = symbol!.replaceAll("<", "&lt;").replaceAll(">", "&gt;");
        final replacement = constructedReferenceURLFrom(
            baseReferenceURL, resolution.link!.split("/"));
        contents = contents.replaceRange(
            match.start, match.end, "<a href=\"$replacement\">$symbol</a>");
      } else {
//        missingSymbols.add(symbol);
      }
    });

    return utf8.encode(contents);
  }

  SymbolResolution? bestGuessForSymbol(String? inputSymbol) {
    if (symbolMap.isEmpty) {
      return null;
    }

    final symbol = inputSymbol!
        .replaceAll("<T>", "")
        .replaceAll("@", "")
        .replaceAll("()", "");

    var possible = symbolMap["qualified"]![symbol];
    possible ??= symbolMap["name"]![symbol];

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
  final subdirectories =
      relativePathComponents.sublist(0, relativePathComponents.length - 1);
  final Uri enclosingDir = subdirectories.fold(base, (Uri prev, elem) {
    return prev.resolve("$elem/");
  });

  return enclosingDir.resolve(relativePathComponents.last);
}
