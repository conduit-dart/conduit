import 'package:wildfire/wildfire.dart';

class SimpleController extends Controller {
  SimpleController(this.context);

  final ManagedContext context;

  @override
  Future<RequestOrResponse> handle(Request request) async {
    return Response.ok({"key": "value"});
  }
}
