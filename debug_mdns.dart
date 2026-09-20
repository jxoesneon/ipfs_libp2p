#!/usr/bin/env dart

import 'dart:io';
import 'dart:async';
import 'package:mdns_dart/mdns_dart.dart';

/// Simple mDNS diagnostic tool
void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart debug_mdns.dart [advertise|discover|both]');
    return;
  }

  final mode = args[0];

  switch (mode) {
    case 'advertise':
      await testAdvertising();
      break;
    case 'discover':
      await testDiscovery();
      break;
    case 'both':
      await testBoth();
      break;
    default:
      print('Unknown mode: $mode');
      print('Usage: dart debug_mdns.dart [advertise|discover|both]');
  }
}

Future<void> testAdvertising() async {
  print('🚀 Testing mDNS service advertisement...');

  try {
    // Get local IP addresses
    final interfaces = await NetworkInterface.list();
    final ips = <InternetAddress>[];

    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        if (!addr.isLoopback && !addr.isLinkLocal) {
          ips.add(addr);
        }
      }
    }

    if (ips.isEmpty) {
      print('⚠️ No suitable IP addresses found');
      return;
    }

    print('🌐 Using IPs: ${ips.map((ip) => ip.address).join(', ')}');

    // Create a test service
    final service = await MDNSService.create(
      instance: 'test-dart-libp2p-${DateTime.now().millisecondsSinceEpoch}',
      service: '_p2p._udp',
      domain: 'local',
      port: 4001,
      ips: ips,
      txt: ['dnsaddr=/ip4/${ips.first.address}/udp/4001/udx'],
    );

    print('📡 Created service: ${service.instance}._p2p._udp.local');

    // Start the server
    final config = MDNSServerConfig(
      zone: service,
      logger: (message) => print('🔧 [mDNS Server] $message'),
    );

    final server = MDNSServer(config);
    await server.start();

    print('✅ mDNS service advertisement started successfully');
    print(
        '💡 You can now run "dart debug_mdns.dart discover" in another terminal');
    print('   or use "dns-sd -B _p2p._udp local" to verify the service');
    print('');
    print('Press Ctrl+C to stop...');

    // Keep running
    while (true) {
      await Future.delayed(Duration(seconds: 5));
      print(
          '⏰ Service still advertising... (${DateTime.now().toIso8601String()})');
    }
  } catch (e) {
    print('❌ Failed to advertise service: $e');
  }
}

Future<void> testDiscovery() async {
  print('🔍 Testing mDNS service discovery...');

  try {
    print('🔍 Looking for _p2p._udp.local services...');

    // Use MDNSClient.query() with extended timeout instead of lookup() which has 1s timeout
    final params = QueryParams(
      service:
          '_p2p._udp', // Correct: just the service type, not _p2p._udp.local
      domain: 'local', // Domain gets appended automatically
      timeout: const Duration(seconds: 10),
      logger: (message) => print('🔧 [mDNS Debug] $message'),
    );

    final stream = await MDNSClient.query(params);

    var foundCount = 0;
    await for (final serviceEntry in stream) {
      foundCount++;
      print('');
      print('🎯 Found service #$foundCount:');
      print('   Name: ${serviceEntry.name}');
      print('   Host: ${serviceEntry.host}');
      print('   Port: ${serviceEntry.port}');
      print('   TXT: ${serviceEntry.infoFields}');
    }

    if (foundCount == 0) {
      print('❌ No _p2p._udp.local services found');
      print(
          '💡 Make sure you have a service advertising (run "dart debug_mdns.dart advertise")');
    } else {
      print('');
      print('✅ Discovery completed - found $foundCount service(s)');
    }
  } catch (e) {
    print('❌ Failed to discover services: $e');
  }
}

Future<void> testBoth() async {
  print('🚀 Testing mDNS advertisement AND discovery...');

  // Start advertising in the background
  final advertisingFuture = testAdvertising();

  // Wait a bit for advertising to start
  await Future.delayed(Duration(seconds: 2));

  // Perform discovery
  await testDiscovery();

  print('');
  print('💡 Advertisement is still running in the background...');
  print('   Press Ctrl+C to stop');

  await advertisingFuture;
}
