/// Riverpod wiring for Health Connect's two edges: the phone and the log.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/health_gateway.dart';
import 'health_channel_gateway.dart';
import 'prefs_health_send_log.dart';

part 'health_providers.g.dart';

@Riverpod(keepAlive: true)
HealthGateway healthGateway(Ref ref) => const ChannelHealthGateway();

@Riverpod(keepAlive: true)
HealthSendLog healthSendLog(Ref ref) => const PrefsHealthSendLog();

/// Whether this build can talk to Health Connect. Tests pin it.
@Riverpod(keepAlive: true)
bool healthIsSupported(Ref ref) => healthSupported;
