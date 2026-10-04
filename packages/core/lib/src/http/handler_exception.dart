import 'package:conduit_core/src/http/http.dart';

class HandlerException(final Response _response) implements Exception {
  Response get response => _response;
}
