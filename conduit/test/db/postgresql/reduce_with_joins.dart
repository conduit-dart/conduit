import 'dart:async';

import 'package:conduit/conduit.dart';
import 'package:conduit_common_test/conduit_common_test.dart';
import 'package:test/test.dart';

late ManagedContext ctx;
late Company emptyCompany;
late Company company1;
late Company company2;
late List<Employee> employees = [];

void main() {
  setUpAll(() async {
      ctx = await PostgresTestConfig().contextWithModels([Company, Employee, Record, Report]);
    await populate();

    /* Note that objects are sorted by id, and therefore all values are in sorted order */
    // objects.sort((t1, t2) => t1.id.compareTo(t2.id));
  });

  tearDownAll(() async {
    await ctx.close();
  });
  group("Implicit", () {
    group("valid", () {
      test("join using 'belongs to' in one to many relation.", () async {
        final q = Query<Employee>(ctx)
          ..where((e) => e.worksIn!.budget).greaterThan(200001);
        final sum = await q.reduce.sum((e) => e.salary);
        expect(sum, 5500);
        final count = await q.reduce.count();
        expect(count, 10);
      });

      test("join using 'has one' relation.", () async {
        final q = Query<Employee>(ctx)
          ..where((e) => e.personalRecord!.payedLeaveLeft).greaterThan(10);
        final sum = await q.reduce.sum((e) => e.salary);
        expect(sum, 2000);
        final count = await q.reduce.count();
        expect(count, 8);
      });

      test("join using 'belongs to' in one to one relation.", () async {
        final q = Query<Record>(ctx)
          ..where((r) => r.employee!.salary).lessThan(101);
        final count = await q.reduce.count();
        expect(count, 2);
        final avg = await q.reduce.average((r) => r.payedLeaveLeft);
        expect(avg, 18.0);
      });

      test("join chinning relation.", () async {
        final q = Query<Record>(ctx)
          ..where((r) => r.employee!.worksIn!.budget).greaterThan(200001);
        final count = await q.reduce.count();
        expect(count, 10);
        final avg = await q.reduce.average((r) => r.payedLeaveLeft);
        expect(avg, 9.0);
      });
    });
  });

  group("Explicit", () {
    group("valid", () {
      test("join using 'belongs to' in one to many relation.", () async {
        final q = Query<Employee>(ctx)
          ..join(object: (e) => e.worksIn)
          ..where((e) => e.salary).lessThan(101);
        final count = await q.reduce.count();
        expect(count, 2);
        final avg = await q.reduce.average((r) => r.salary);
        expect(avg, 100.0);
      });

      test("join using 'has one' relation.", () async {
        final q = Query<Employee>(ctx)
          ..join(object: (e) => e.personalRecord)
          ..where((e) => e.salary).lessThan(101);
        final count = await q.reduce.count();
        expect(count, 2);
        final avg = await q.reduce.average((r) => r.salary);
        expect(avg, 100.0);
      });

      test("join using 'belongs to' in one to one relation.", () async {
        final q = Query<Record>(ctx)
          ..join(object: (r) => r.employee)
          ..where((r) => r.payedLeaveLeft).greaterThan(10);
        final count = await q.reduce.count();
        expect(count, 8);
        final avg = await q.reduce.average((r) => r.payedLeaveLeft);
        expect(avg, 15.0);
      });

      test("join chinning relation.", () async {
        final q = Query<Record>(ctx)
          ..join(object: (r) => r.employee).join(object: (e) => e.worksIn)
          ..where((r) => r.payedLeaveLeft).greaterThan(10);
        final count = await q.reduce.count();
        expect(count, 8);
        final avg = await q.reduce.average((r) => r.payedLeaveLeft);
        expect(avg, 15.0);
      });
    });

    group("invalid", () {
      test("join using has many relation directly.", () async {
        final q = Query<Company>(ctx)..join(set: (c) => c.employs);
        try {
          await q.reduce.count();
        } on StateError catch (e) {
          expect(
            e.message,
            "Invalid query. Cannot use 'join(set: ...)' with 'reduce' query.",
          );
          return;
        }
        fail('Should raise and exception.');
      });

      test("join using has many relation indirectly.", () async {
        final q = Query<Employee>(ctx)
          ..join(object: (e) => e.worksIn).join(set: (c) => c.quarterlyReports);
        try {
          await q.reduce.count();
        } on StateError catch (e) {
          expect(
            e.message,
            "Invalid query. Cannot use 'join(set: ...)' with 'reduce' query.",
          );
          return;
        }
        fail('Should raise and exception.');
      });
    });
  });
}

Future populate() async {
  emptyCompany = await (Query<Company>(ctx)..values.budget = 100000).insert();
  company1 = await (Query<Company>(ctx)..values.budget = 200000).insert();
  company2 = await (Query<Company>(ctx)..values.budget = 300000).insert();

  Future addEmployees(Company company) async {
    for (var i = 1; i <= 10; ++i) {
      final employee = await (Query<Employee>(ctx)
            ..values.salary = i * 100
            ..values.worksIn = company)
          .insert();
      employees.add(employee);
      final record = await (Query<Record>(ctx)
            ..values.payedLeaveLeft = 20 - 2 * i
            ..values.employee = employee)
          .insert();

      employee.personalRecord = record;
    }
  }

  await addEmployees(company1);
  await addEmployees(company2);
}

class Company extends ManagedObject<_Company> implements _Company {}

class _Company {
  @primaryKey
  int? id;

  int? budget;

  ManagedSet<Employee>? employs;
  ManagedSet<Report>? quarterlyReports;
}

class Employee extends ManagedObject<_Employee> implements _Employee {}

class _Employee {
  @primaryKey
  int? id;

  int? salary;

  @Relate(#employs)
  Company? worksIn;

  Record? personalRecord;
}

class Record extends ManagedObject<_Record> implements _Record {}

class _Record {
  @primaryKey
  int? id;

  int? payedLeaveLeft;

  @Relate(#personalRecord)
  Employee? employee;
}

class Report extends ManagedObject<_Report> implements _Report {}

class _Report {
  @primaryKey
  int? id;

  int? earnings;

  @Relate(#quarterlyReports)
  Company? company;
}
