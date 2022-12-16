import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_test/conduit_test.dart';
import 'package:conduit_test/src/body_matcher.dart';
import 'package:conduit_test/src/response_matcher.dart';
import 'package:test/test.dart';
import 'package:test_core/src/util/io.dart';

void main() async {
  late MockHTTPServer server;
  late Agent agent;

  setUpAll(() async {
    server = await getUnusedPort(MockHTTPServer.new);
    agent = Agent.onPort(server.port);
    await server.open();
  });

  tearDown(() async {
    await server.close();
  });

  test("Mismatched body shows decoded body and teh reason for the mismatch",
      () async {
    server.queueHandler((req) {
      return Response.ok({"key": "value"});
    });

    final response = await agent.get("/");
    final responseMatcher = HTTPResponseMatcher(
        200, null, HTTPBodyMatcher(equals({"notkey": "bar"})));
    expect(responseMatcher.matches(response, {}), false);

    final desc = StringDescription();
    responseMatcher.describe(desc);
    expect(desc.toString(), contains("Status code must be 200"));
    expect(desc.toString(), contains("{'notkey': 'bar'}"));

    final actual = response.toString();
    expect(actual, contains("Status code is 200"));
    expect(actual, contains("{key: value}"));
  });
}
