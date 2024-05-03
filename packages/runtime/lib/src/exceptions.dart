class TypeCoercionException implements Exception {
  TypeCoercionException(this.expectedType, this.actualType);

  final Type expectedType;
  final Type actualType;

  @override
  String toString() {
    return "input is not expected type '$expectedType' (input is '$actualType')";
  }
}
