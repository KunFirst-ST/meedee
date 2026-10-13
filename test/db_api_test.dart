import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:msu_food2/models/food_order.dart';
import 'package:msu_food2/models/shop.dart';
import 'package:msu_food2/services/db.dart';
import 'support/api_auth_harness.dart';

void main() {
  final shop = Shop(
    id: 'shop-a',
    name: 'ร้าน',
    ownerId: 'merchant',
    isOpen: true,
  );
  final items = [
    OrderItem(menuItemId: 'menu-a', name: 'client name', price: 45.50, qty: 2),
  ];

  Future<Db> signedIn(Harness h) async {
    expect(
      await h.auth.signInWithEmail('student@example.com', 'Password123!'),
      isNull,
    );
    return Db(
      client: h.api,
      auth: h.auth,
      refreshInterval: const Duration(milliseconds: 20),
    );
  }

  http.Response login() =>
      success({'token': 'real-server-token', 'user': user()});

  test(
    'checkout sends IDs, integer prices and stable retry key without trusting client totals',
    () async {
      final h = Harness(
        (r) => r.url.path.endsWith('/auth/login')
            ? login()
            : success({'id': 'order-a'}),
      );
      final db = await signedIn(h);
      for (var retry = 0; retry < 2; retry++) {
        expect(
          await db.placeOrder(
            shop: shop,
            customerId: 'api-user',
            customerName: 'forged',
            items: items,
            note: ' no onion ',
            requestId: 'same-checkout',
          ),
          'order-a',
        );
      }
      final requests = h.requests
          .where((r) => r.url.path.endsWith('/orders'))
          .toList();
      expect(requests, hasLength(2));
      expect(requests[0].headers['authorization'], 'Bearer real-server-token');
      expect(requests[0].body, requests[1].body);
      expect(jsonDecode(requests[0].body), {
        'shopId': 'shop-a',
        'requestId': 'same-checkout',
        'note': 'no onion',
        'items': [
          {'menuItemId': 'menu-a', 'qty': 2, 'expectedPriceSatang': 4550},
        ],
      });
    },
  );

  test('server conflict and missing order ID never count as placed', () async {
    var conflict = true;
    final h = Harness(
      (r) => r.url.path.endsWith('/auth/login')
          ? login()
          : conflict
          ? failure(409, 'ราคาเปลี่ยนแล้ว')
          : success({}),
    );
    final db = await signedIn(h);
    Future<String> place() => db.placeOrder(
      shop: shop,
      customerId: 'api-user',
      customerName: '',
      items: items,
      note: '',
      requestId: 'checkout',
    );
    await expectLater(
      place(),
      throwsA(
        isA<OrderValidationException>().having(
          (e) => e.message,
          'server message',
          'ราคาเปลี่ยนแล้ว',
        ),
      ),
    );
    conflict = false;
    await expectLater(place(), throwsA(isA<OrderValidationException>()));
  });

  test(
    'cross-account profile writes are rejected before network access',
    () async {
      final h = Harness((r) => login());
      final db = await signedIn(h);
      final before = h.requests.length;
      await expectLater(
        db.updateProfile('other-user', displayName: 'Name', phone: ''),
        throwsA(isA<OrderValidationException>()),
      );
      expect(h.requests, hasLength(before));
    },
  );

  test('menu updates send integer satang and explicit image removal', () async {
    final h = Harness(
      (r) => r.url.path.endsWith('/auth/login') ? login() : success(null),
    );
    final db = await signedIn(h);
    await db.updateMenuItem('menu-a', ' ข้าว ', 45.50, removeImage: true);
    final r = h.requests.last;
    expect(r.method, 'PATCH');
    expect(r.url.path, '/api/v1/menu/menu-a');
    expect(jsonDecode(r.body), {
      'name': 'ข้าว',
      'priceSatang': 4550,
      'imageBase64': null,
    });
  });

  test(
    'order review is sent to the authenticated API with a trimmed comment',
    () async {
      final h = Harness(
        (r) => r.url.path.endsWith('/auth/login')
            ? login()
            : success({'rating': 5}),
      );
      final db = await signedIn(h);
      await db.reviewOrder('order-a', rating: 5, comment: '  อร่อยมาก  ');
      final request = h.requests.last;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/orders/order-a/review');
      expect(request.headers['authorization'], 'Bearer real-server-token');
      expect(jsonDecode(request.body), {'rating': 5, 'comment': 'อร่อยมาก'});
      await expectLater(
        db.reviewOrder('order-a', rating: 6, comment: ''),
        throwsA(isA<OrderValidationException>()),
      );
    },
  );

  test(
    'polling reads actual API data and cancels after first subscription',
    () async {
      final h = Harness(
        (r) => r.url.path.endsWith('/auth/login')
            ? login()
            : success([
                {
                  'id': 'shop-a',
                  'name': 'Server shop',
                  'ownerId': 'merchant',
                  'isOpen': true,
                },
              ]),
      );
      final db = await signedIn(h);
      expect((await db.watchShops().first).single.name, 'Server shop');
      final count = h.requests.length;
      await Future<void>.delayed(const Duration(milliseconds: 65));
      expect(h.requests, hasLength(count));
    },
  );

  test(
    'a polling stream can be listened to again after its last listener cancels',
    () async {
      final h = Harness(
        (r) => r.url.path.endsWith('/auth/login')
            ? login()
            : success([
                {
                  'id': 'shop-a',
                  'name': 'Server shop',
                  'ownerId': 'merchant',
                  'isOpen': true,
                },
              ]),
      );
      final db = await signedIn(h);
      final stream = db.watchShops();

      expect((await stream.first).single.name, 'Server shop');
      expect((await stream.first).single.name, 'Server shop');
      expect(
        h.requests.where((r) => r.url.path == '/api/v1/shops'),
        hasLength(2),
      );
    },
  );

  test('polling surfaces backend failures', () async {
    final h = Harness(
      (r) => r.url.path.endsWith('/auth/login')
          ? login()
          : failure(503, 'โหลดไม่ได้'),
    );
    final db = await signedIn(h);
    await expectLater(
      db.watchShops().first,
      throwsA(
        isA<OrderValidationException>().having(
          (e) => e.message,
          'message',
          'โหลดไม่ได้',
        ),
      ),
    );
  });

  test('in-flight private response is discarded when session ends', () async {
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final h = Harness((r) {
      if (r.url.path.endsWith('/auth/login')) return login();
      if (r.url.path.endsWith('/auth/logout')) return success(null);
      if (!started.isCompleted) started.complete();
      return pending.future;
    });
    final db = await signedIn(h);
    final values = <Object>[];
    final sub = db.watchMyOrders('api-user').listen(values.add);
    await started.future;
    await h.auth.signOut();
    pending.complete(success([]));
    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(values, isEmpty);
    await sub.cancel();
  });
}
