@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'package:quick_blue_web/quick_blue_web.dart';

@JS('eval')
external JSAny? evaluate(JSString source);
void script(String source) {
  evaluate(source.toJS);
}

int number(String source) => (evaluate(source.toJS) as JSNumber).toDartInt;

const simulator = r'''
window.qb = { starts:0, stops:0, mode:'ok', reads:0, writes:[], selected:0 };
qb.makeDevice = function(id) {
  const device = new EventTarget(); device.id=id; device.name='simulator';
  const c = new EventTarget(); c.uuid='00002a19-0000-1000-8000-00805f9b34fb';
  c.properties={read:true,write:true,writeWithoutResponse:true,notify:true,indicate:false};
  c.value = new DataView(new Uint8Array([88,42,99]).buffer,1,1);
  c.readValue=()=>{qb.reads++; if(qb.mode==='reject') return Promise.reject(new DOMException('Read denied','SecurityError'));
    if(qb.mode==='pending') return new Promise((resolve,reject)=>{qb.resolve=resolve;qb.reject=reject});
    return Promise.resolve(c.value);};
  c.writeValueWithResponse=(bytes)=>{qb.writes.push(Array.from(new Uint8Array(bytes)));return Promise.resolve();};
  c.writeValueWithoutResponse=c.writeValueWithResponse;
  c.startNotifications=()=>{qb.starts++;
    if(qb.mode==='notifyReject')return Promise.reject(new DOMException('Notify denied','SecurityError'));
    if(qb.mode==='notifyPending')return new Promise(resolve=>{qb.notifyResolve=()=>resolve(c)});
    return Promise.resolve(c);};
  c.stopNotifications=()=>{qb.stops++;return Promise.resolve(c);};
  const s={uuid:'0000180f-0000-1000-8000-00805f9b34fb',getCharacteristics:()=>Promise.resolve([c])};
  const g={connected:false,getPrimaryServices:()=>qb.mode==='discoveryPending'?new Promise(resolve=>{qb.discoveryResolve=()=>resolve([s])}):Promise.resolve([s]),
    connect:()=>{if(qb.mode==='connectPending')return new Promise(resolve=>{qb.connectResolve=()=>{g.connected=true;resolve(g);}});g.connected=true;return Promise.resolve(g);},
    disconnect:()=>{if(g.connected){g.connected=false;device.dispatchEvent(new Event('gattserverdisconnected'));}}};
  device.gatt=g; device.c=c; return device;
};
qb.devices=[qb.makeDevice('one'),qb.makeDevice('two')];
Object.defineProperty(navigator,'bluetooth',{configurable:true,value:{
 getAvailability:()=>Promise.resolve(true),
 requestDevice:(options)=>{qb.options=options;qb.selected++;
   if(qb.mode==='cancel')return Promise.reject(new DOMException('User cancelled','NotFoundError'));
   if(qb.mode==='denied')return Promise.reject(new DOMException('Permission denied','NotAllowedError'));
   if(qb.mode==='chooserPending')return new Promise(resolve=>{qb.chooserResolve=()=>resolve(qb.devices[0])});
   return Promise.resolve(qb.devices[qb.index||0]);}
}});
''';

void main() {
  test('disconnect terminates notification owners before reconnect', () async {
    script(simulator);
    final backend = QuickBlueWeb(
      operationTimeout: const Duration(milliseconds: 150),
    );
    QuickBluePlatform.instance = backend;
    final device = await backend.requestDevice(serviceUuids: ['180f']);
    await device.connect();
    await device.discoverGatt();
    final done = Completer<void>();
    final errors = <Object>[];
    final subscription = device
        .characteristic('180f', '2a19')
        .notifications()
        .listen((_) {}, onError: errors.add, onDone: done.complete);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await device.disconnect();
    try {
      await done.future.timeout(const Duration(milliseconds: 200));
      expect(errors, isNotEmpty);
      await device.connect();
      await device.discoverGatt();
      final next = device
          .characteristic('180f', '2a19')
          .notifications()
          .listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(number('qb.starts'), 2);
      await next.cancel();
    } finally {
      await subscription.cancel();
      await device.disconnect();
    }
  });
  late QuickBlueWeb platform;
  setUp(() {
    script(simulator);
    platform = QuickBlueWeb(
      operationTimeout: const Duration(milliseconds: 150),
    );
    QuickBluePlatform.instance = platform;
  });
  Future<BluetoothDevice> ready() async {
    final device = await platform.requestDevice(serviceUuids: ['180f']);
    await device.connect();
    await device.discoverGatt();
    return device;
  }

  test(
    'chooser timeout rejects late selection and blocks overlapping chooser',
    () async {
      script("qb.mode='chooserPending'");
      await expectLater(
        platform.requestDevice(),
        throwsA(isA<QuickBlueException>()),
      );
      await expectLater(
        platform.requestDevice(),
        throwsA(isA<QuickBlueException>()),
      );
      script('qb.chooserResolve()');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await expectLater(
        platform.connect('one'),
        throwsA(isA<QuickBlueException>()),
      );
      script("qb.mode='ok'");
      expect((await platform.requestDevice()).deviceId, 'one');
    },
  );

  test(
    'disconnected discovery cannot publish late services into a replacement',
    () async {
      final device = await ready();
      script("qb.mode='discoveryPending'");
      final pending = platform.discoverServices('one');
      final failure = expectLater(pending, throwsA(isA<QuickBlueException>()));
      await device.disconnect();
      await failure;
      script("qb.discoveryResolve();qb.mode='ok'");
      final services = <BluetoothService>[];
      final sub = platform.serviceDiscoveryStream.listen(services.add);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(services, isEmpty);
      await device.connect();
      await device.discoverGatt();
      expect(services.length, 1);
      await sub.cancel();
      await device.disconnect();
    },
  );

  for (final mode in ['notifyReject', 'notifyPending']) {
    test('$mode settles and removes notification listeners before retry', () async {
      final device = await ready();
      script("qb.mode='$mode'");
      final done = Completer<void>();
      final errors = <Object>[];
      final values = <Uint8List>[];
      final sub = device
          .characteristic('180f', '2a19')
          .notifications()
          .listen(values.add, onError: errors.add, onDone: done.complete);
      await done.future.timeout(const Duration(seconds: 1));
      expect(errors, isNotEmpty);
      if (mode == 'notifyPending') script('qb.notifyResolve()');
      script(
        "qb.mode='ok';qb.devices[0].c.dispatchEvent(new Event('characteristicvaluechanged'))",
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(values, isEmpty);
      await sub.cancel();
      await device.connect();
      await device.discoverGatt();
      final again = device
          .characteristic('180f', '2a19')
          .notifications()
          .listen(values.add);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      script(
        "qb.devices[0].c.dispatchEvent(new Event('characteristicvaluechanged'))",
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(values, [
        [42],
      ]);
      await again.cancel();
      await device.disconnect();
    });
  }

  test(
    'chooser calls browser synchronously and authorizes normalized service UUIDs',
    () async {
      final pending = platform.requestDevice(
        serviceUuids: ['180F'],
        optionalServices: ['180a'],
      );
      expect(number('qb.selected'), 1); // before any awaited preflight
      expect(
        number(
          "qb.options.filters[0].services[0]==='0000180f-0000-1000-8000-00805f9b34fb'?1:0",
        ),
        1,
      );
      expect(number('qb.options.optionalServices.length'), 1);
      expect((await pending).deviceId, 'one');
    },
  );
  for (final mode in ['cancel', 'denied']) {
    test('chooser $mode is an actionable error, never a scan result', () async {
      script("qb.mode='$mode'");
      await expectLater(
        platform.requestDevice(),
        throwsA(isA<QuickBlueException>()),
      );
      script("qb.mode='ok'");
      expect((await platform.requestDevice()).deviceId, 'one');
    });
  }
  test('notification setup preserves the shared snapshot guard', () async {
    final device = await ready();
    await expectLater(
      platform
          .characteristicNotifications(
            device.deviceId,
            '180f',
            '2a19',
            beforeSubmission: () => throw StateError('retired snapshot'),
          )
          .first,
      throwsA(isA<StateError>()),
    );
    expect(number('qb.starts'), 0);
    await device.disconnect();
  });
  test('unavailable API and native-only APIs fail explicitly', () async {
    script(
      "Object.defineProperty(navigator, 'bluetooth', {configurable:true, value:undefined})",
    );
    expect(await platform.isBluetoothAvailable(), false);
    await expectLater(
      platform.requestDevice(),
      throwsA(isA<QuickBlueException>()),
    );
    await expectLater(platform.startScan(), throwsA(isA<QuickBlueException>()));
    await expectLater(
      platform.requestMtu('one', 247),
      throwsA(isA<QuickBlueException>()),
    );
    expect(
      (await platform.capabilities()).connectedDeviceLookup,
      BluetoothConnectedDeviceLookupCapability.unsupported,
    );
  });
  test(
    'public handles discover/read exact DataView slice/write exact Uint8List view',
    () async {
      final device = await ready();
      final gatt = await device.discoverGatt();
      final c = gatt.characteristic('2a19', service: '180f');
      expect(await c.read(), [42]);
      await c.write(
        Uint8List.sublistView(Uint8List.fromList([9, 7, 8, 9]), 1, 3),
        BleOutputProperty.withResponse,
      );
      expect(number('qb.writes[0].length'), 2);
      expect(number('qb.writes[0][0]'), 7);
      await device.disconnect();
    },
  );
  test('operation rejection propagates', () async {
    final device = await ready();
    script("qb.mode='reject'");
    await expectLater(
      device.characteristic('180f', '2a19').read(),
      throwsA(isA<QuickBlueException>()),
    );
    await device.disconnect();
  });
  test(
    'timeout fences late read and quarantines reconnect until browser settles',
    () async {
      final device = await ready();
      script("qb.mode='pending'");
      await expectLater(
        platform.readCharacteristicValue('one', '180f', '2a19'),
        throwsA(isA<QuickBlueException>()),
      );
      await expectLater(
        platform.connect('one'),
        throwsA(isA<QuickBlueException>()),
      );
      script("qb.resolve(qb.devices[0].c.value);qb.mode='ok'");
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await device.connect();
      await device.discoverGatt();
      expect(await device.characteristic('180f', '2a19').read(), [42]);
      await device.disconnect();
    },
  );
  test('disconnect pending read, switch device, discard late result', () async {
    final device = await ready();
    script("qb.mode='pending'");
    final pending = platform.readCharacteristicValue('one', '180f', '2a19');
    final failed = expectLater(pending, throwsA(isA<QuickBlueException>()));
    await device.disconnect();
    await failed;
    script("qb.index=1;qb.mode='ok'");
    final other = await ready();
    final values = <Uint8List>[];
    final subscription = platform.characteristicValueStream.listen(
      (value) => values.add(value.value),
    );
    script('qb.resolve(qb.devices[0].c.value)');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(values, isEmpty);
    await subscription.cancel();
    await other.disconnect();
  });
  test('late connect is disconnected before a new session can start', () async {
    final device = await platform.requestDevice();
    script("qb.mode='connectPending'");
    await expectLater(
      platform.connect(device.deviceId),
      throwsA(isA<QuickBlueException>()),
    );
    await expectLater(
      platform.connect(device.deviceId),
      throwsA(isA<QuickBlueException>()),
    );
    script("qb.connectResolve();qb.mode='ok'");
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(number('qb.devices[0].gatt.connected?1:0'), 0);
    await device.connect();
    await device.disconnect();
  });
  test(
    'notification cancel/relisten repeated cycles have one listener and one event',
    () async {
      final device = await ready();
      for (var cycle = 0; cycle < 3; cycle++) {
        final values = <Uint8List>[];
        final sub = device
            .characteristic('180f', '2a19')
            .notifications()
            .listen(values.add);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        script(
          "qb.devices[0].c.dispatchEvent(new Event('characteristicvaluechanged'))",
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(values, [
          [42],
        ]);
        await sub.cancel();
        script(
          "qb.devices[0].c.dispatchEvent(new Event('characteristicvaluechanged'))",
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(values.length, 1);
      }
      expect(number('qb.starts'), 3);
      expect(number('qb.stops'), 3);
      await device.disconnect();
    },
  );
}
