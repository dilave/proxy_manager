import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'proxy_manager.dart';
import 'proxy_manager_platform_interface.dart';

/// An implementation of [ProxyManagerPlatform] that uses method channels.
///
/// now for [windows] only!
class MethodChannelProxyManager extends ProxyManagerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('proxy_manager');

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<void> setSystemProxy(String proxy) async {
    await methodChannel
        .invokeMethod('setSystemProxy', <String, dynamic>{"proxy": proxy});
  }

  @override
  Future<void> cleanSystemProxy() async {
    await methodChannel.invokeMethod('cleanSystemProxy');
  }

  @override
  Future<bool> getSystemProxyEnable(String proxy) async {
    String ret = await methodChannel.invokeMethod(
        'getSystemProxyEnable', <String, dynamic>{"proxy": proxy});
    return ret == "true";
  }
}
