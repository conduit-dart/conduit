class TypeCoercionException(final Type expectedType, final Type actualType)
    implements Exception {
  @override
  String toString() {
    return "input is not expected type '$expectedType' (input is '$actualType')";
  }
}
