import 'package:wildfire/wildfire.dart';

class SimpleController extends ResourceController {
  SimpleController(this.context);

  final ManagedContext context;

  @Operation.get()
  Future<Response> getAll() async {
    return Response.ok({"key": "value"});
  }
}
