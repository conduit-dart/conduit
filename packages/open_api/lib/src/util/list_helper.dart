/// Remove any null entries from the list and convert the type.
/// In reality I don't think the list can have nulls but we still
/// need the conversion.
List<String>? removeNullsFromList(List<String?>? list) {
  if (list == null) return null;

  // remove nulls and convert to List<String>
  return list.nonNulls.toList();
}
