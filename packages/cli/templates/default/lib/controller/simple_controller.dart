import 'package:wildfire/wildfire.dart';

class SimpleController extends Controller {
  SimpleController();

  @override
  Future<RequestOrResponse> handle(Request request) async {
    return Response.ok({"key": "value"});
  }
}
