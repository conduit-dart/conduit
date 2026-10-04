class IntermediateException implements Exception {
  new(this.underlying, this.keyPath);

  final dynamic underlying;

  final List<dynamic> keyPath;
}
