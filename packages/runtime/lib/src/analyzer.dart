import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/physical_file_system.dart';

class CodeAnalyzer {
  CodeAnalyzer(this.uri) {
    if (!uri.isAbsolute) {
      throw ArgumentError("'uri' must be absolute for CodeAnalyzer");
    }

    contexts = AnalysisContextCollection(includedPaths: [path]);

    if (contexts.contexts.isEmpty) {
      throw ArgumentError("no analysis context found for path '$path'");
    }
  }

  String get path {
    return getPath(uri);
  }

  late final Uri uri;

  late AnalysisContextCollection contexts;

  final _resolvedAsts = <String, AnalysisResult>{};

  Future<AnalysisResult> resolveUnitOrLibraryAt(Uri uri) async {
    if (FileSystemEntity.isFileSync(
        uri.toFilePath(windows: Platform.isWindows))) {
      return await resolveUnitAt(uri);
    } else {
      return await resolveLibraryAt(uri);
    }
  }

  Future<ResolvedLibraryResult> resolveLibraryAt(Uri uri) async {
    assert(FileSystemEntity.isDirectorySync(
        uri.toFilePath(windows: Platform.isWindows)));
    for (final ctx in contexts.contexts) {
      final path = getPath(uri);
      if (_resolvedAsts.containsKey(path)) {
        return _resolvedAsts[path]! as ResolvedLibraryResult;
      }

      final output = await ctx.currentSession.getResolvedLibrary(path)
          as ResolvedLibraryResult;
      return _resolvedAsts[path] = output;
    }

    throw ArgumentError("'uri' could not be resolved (contexts: "
        "${contexts.contexts.map((c) => c.contextRoot.root.toUri()).join(", ")})");
  }

  Future<ResolvedUnitResult> resolveUnitAt(Uri uri) async {
    assert(FileSystemEntity.isFileSync(
        uri.toFilePath(windows: Platform.isWindows)));
    for (final ctx in contexts.contexts) {
      final path = getPath(uri);
      if (_resolvedAsts.containsKey(path)) {
        return _resolvedAsts[path]! as ResolvedUnitResult;
      }

      final output =
          await ctx.currentSession.getResolvedUnit(path) as ResolvedUnitResult;
      return _resolvedAsts[path] = output;
    }

    throw ArgumentError("'uri' could not be resolved (contexts: "
        "${contexts.contexts.map((c) => c.contextRoot.root.toUri()).join(", ")})");
  }

  ClassDeclaration? getClassFromFile(String className, Uri fileUri) {
    try {
      return _getFileAstRoot(fileUri)
          .declarations
          .whereType<ClassDeclaration>()
          .firstWhere((c) => c.name.value() == className);
    } catch (e) {
      if (e is StateError || e is TypeError) {
        print(e);
        return null;
      }
      throw e;
    }
  }

  List<ClassDeclaration> getSubclassesFromFile(
      String superclassName, Uri fileUri) {
    return _getFileAstRoot(fileUri)
        .declarations
        .whereType<ClassDeclaration>()
        .where((c) => c.extendsClause?.superclass.name.name == superclassName)
        .toList();
  }

  CompilationUnit _getFileAstRoot(Uri fileUri) {
    assert(FileSystemEntity.isFileSync(
        fileUri.toFilePath(windows: Platform.isWindows)));
    try {
      final path = getPath(fileUri);
      if (_resolvedAsts.containsKey(path)) {
        return (_resolvedAsts[path]! as ResolvedUnitResult).unit;
      }
    } catch (e) {
      print(e);
    }
    final unit = contexts
        .contextFor(path)
        .currentSession
        .getParsedUnit(fileUri.path) as ParsedUnitResult;
    return unit.unit;
  }

  static String getPath(dynamic inputUri) {
    return PhysicalResourceProvider.INSTANCE.pathContext.normalize(
        PhysicalResourceProvider.INSTANCE.pathContext.fromUri(inputUri));
  }
}
