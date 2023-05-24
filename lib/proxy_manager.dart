// You have generated a new plugin project without specifying the `--platforms`
// flag. A plugin project with no platform support was generated. To add a
// platform, run `flutter create -t plugin --platforms <platforms> .` under the
// same directory. You can also find a detailed instruction on how to add
// platforms in the `pubspec.yaml` at
// https://flutter.dev/docs/development/packages-and-plugins/developing-packages#plugin-platforms.

import 'dart:io';

import 'proxy_manager_platform_interface.dart';
import 'dart:ffi';
import 'package:path/path.dart' as path;
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

enum ProxyTypes { http, https, socks }

const regSubKey =
    r'SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings';
const ProxyServer = r'ProxyServer';
const ProxyEnable = r'ProxyEnable';

Object? getRegistryValue(
  int hKeyValue,
  String subKey,
  String valueName,
) {
  late Object? dataValue;

  final subKeyPtr = subKey.toNativeUtf16();
  final valueNamePtr = valueName.toNativeUtf16();
  final openKeyPtr = calloc<HANDLE>();
  final dataType = calloc<DWORD>();

  final data = calloc<BYTE>(512);
  final dataSize = calloc<DWORD>()..value = 512;

  try {
    var result = RegOpenKeyEx(hKeyValue, subKeyPtr, 0, KEY_READ, openKeyPtr);
    if (result == ERROR_SUCCESS) {
      result = RegQueryValueEx(
          openKeyPtr.value, valueNamePtr, nullptr, dataType, data, dataSize);

      if (result == ERROR_SUCCESS) {
        if (dataType.value == REG_DWORD) {
          dataValue = data.value;
        } else if (dataType.value == REG_SZ) {
          dataValue = data.cast<Utf16>().toDartString();
        } else {}
      } else {
        //(HRESULT_FROM_WIN32(result));
      }
    } else {
      //(HRESULT_FROM_WIN32(result));
    }
  } finally {
    RegCloseKey(openKeyPtr.value);
    free(subKeyPtr);
    free(valueNamePtr);
    free(openKeyPtr);
    free(data);
    free(dataSize);
  }

  return dataValue;
}

bool setRegistryStringValue(
    int hKeyValue, String regPath, String valueName, String value) {
  final phKey = calloc<HANDLE>();
  final lpKeyPath = regPath.toNativeUtf16();
  final lpValueName = valueName.toNativeUtf16();
  final lpValue = value.toNativeUtf16();

  try {
    var result = RegSetKeyValue(
        hKeyValue, lpKeyPath, lpValueName, REG_SZ, lpValue, lpValue.length * 2);
    if (result == ERROR_SUCCESS) {
      return true;
    }
  } finally {
    RegCloseKey(phKey.value);
    free(phKey);
    free(lpKeyPath);
    free(lpValueName);
    free(lpValue);
  }
  return false;
}

bool setRegistryIntValue(
    int hKeyValue, String regPath, String valueName, int value) {
  final phKey = calloc<HANDLE>();
  final lpKeyPath = regPath.toNativeUtf16();
  final lpValueName = valueName.toNativeUtf16();
  final data = calloc<DWORD>()..value = value;

  try {
    var result =
        RegSetKeyValue(hKeyValue, lpKeyPath, lpValueName, REG_DWORD, data, 4);

    if (result == ERROR_SUCCESS) {
      return true;
    }
  } finally {
    free(phKey);
    free(lpKeyPath);
    free(lpValueName);
  }
  return false;
}

class ProxyOption {
  ProxyTypes type;
  String url;
  int port;
  ProxyOption(this.type, this.url, this.port);
}

class ProxyManager {
  /// set system proxy
  Future<void> setAsSystemProxy(List<ProxyOption> options) async {
    if (options.isEmpty) {
      return;
    }
    switch (Platform.operatingSystem) {
      case "windows":
        await _setAsSystemProxyBatWindows(options);
        break;
      case "linux":
        _setAsSystemProxyBatLinux(options);
        break;
      case "macos":
        await _setAsSystemProxyBatMacos(options);
        break;
    }
  }

  Future<List<String>> _getNetworkDeviceListMacos() async {
    final resp = await Process.run(
        "/usr/sbin/networksetup", ["-listallnetworkservices"]);
    final lines = resp.stdout.toString().split("\n");
    lines.removeWhere((element) => element.contains("*"));
    return lines;
  }

  Future<void> _setAsSystemProxyBatMacos(List<ProxyOption> options) async {
    for (var opt in options) {
      _setAsSystemProxyMacos(opt.type, opt.url, opt.port);
    }
  }

  Future<void> _setAsSystemProxyMacos(
      ProxyTypes type, String url, int port) async {
    final devices = await _getNetworkDeviceListMacos();
    for (final dev in devices) {
      switch (type) {
        case ProxyTypes.http:
          await Process.run(
              "/usr/sbin/networksetup", ["-setwebproxystate", dev, "on"]);
          await Process.run(
              "/usr/sbin/networksetup", ["-setwebproxy", dev, url, "$port"]);
          break;
        case ProxyTypes.https:
          await Process.run(
              "/usr/sbin/networksetup", ["-setsecurewebproxystate", dev, "on"]);
          await Process.run("/usr/sbin/networksetup",
              ["-setsecurewebproxy", dev, url, "$port"]);
          break;
        case ProxyTypes.socks:
          await Process.run("/usr/sbin/networksetup",
              ["-setsocksfirewallproxystate", dev, "on"]);
          await Process.run("/usr/sbin/networksetup",
              ["-setsocksfirewallproxy", dev, url, "$port"]);
          break;
      }
    }
  }

  Future<void> _cleanSystemProxyMacos() async {
    final devices = await _getNetworkDeviceListMacos();
    for (final dev in devices) {
      await Future.wait([
        Process.run(
            "/usr/sbin/networksetup", ["-setautoproxystate", dev, "off"]),
        Process.run(
            "/usr/sbin/networksetup", ["-setwebproxystate", dev, "off"]),
        Process.run(
            "/usr/sbin/networksetup", ["-setsecurewebproxystate", dev, "off"]),
        Process.run("/usr/sbin/networksetup",
            ["-setsocksfirewallproxystate", dev, "off"]),
      ]);
    }
  }

  String _getProxyWindows(List<ProxyOption> options) {
    String proxy = "";
    for (var opt in options) {
      if (opt.type == ProxyTypes.http) {
        proxy = proxy + "http://${opt.url}:${opt.port};";
      } else if (opt.type == ProxyTypes.https) {
        proxy = proxy + "https://${opt.url}:${opt.port};";
      } else if (opt.type == ProxyTypes.socks) {
        //windows socks proxy must set by registry
        proxy = proxy + "socks5://${opt.url}:${opt.port};";
      } else {
        continue;
      }
    }
    return proxy;
  }

  Future<void> _setAsSystemProxyBatWindows(List<ProxyOption> options) async {
    String proxy = _getProxyWindows(options);
    if (proxy.isEmpty) {
      return;
    }

    setRegistryStringValue(HKEY_CURRENT_USER, regSubKey, ProxyServer, proxy);
    setRegistryIntValue(HKEY_CURRENT_USER, regSubKey, ProxyEnable, 1);
  }

  void _setAsSystemProxyBatLinux(List<ProxyOption> options) {
    for (var opt in options) {
      _setAsSystemProxyLinux(opt.type, opt.url, opt.port);
    }
  }

  void _setAsSystemProxyLinux(ProxyTypes type, String url, int port) {
    final homeDir = Platform.environment['HOME']!;
    final configDir = path.join(homeDir, ".config");
    final cmdList = List<List<String>>.empty(growable: true);
    final desktop = Platform.environment['XDG_CURRENT_DESKTOP'];
    final isKDE = desktop == "KDE";

    // gsetting
    cmdList
        .add(["gsettings", "set", "org.gnome.system.proxy", "mode", "manual"]);
    cmdList.add([
      "gsettings",
      "set",
      "org.gnome.system.proxy.${type.name}",
      "host",
      "$url"
    ]);
    cmdList.add([
      "gsettings",
      "set",
      "org.gnome.system.proxy.${type.name}",
      "port",
      "$port"
    ]);
    // kde
    if (isKDE) {
      cmdList.add([
        "kwriteconfig5",
        "--file",
        "$configDir/kioslaverc",
        "--group",
        "Proxy Settings",
        "--key",
        "ProxyType",
        "1"
      ]);
      cmdList.add([
        "kwriteconfig5",
        "--file",
        "$configDir/kioslaverc",
        "--group",
        "Proxy Settings",
        "--key",
        "${type.name}Proxy",
        "${type.name}://$url:$port"
      ]);
    }
    for (final cmd in cmdList) {
      final res = Process.runSync(cmd[0], cmd.sublist(1), runInShell: true);
      print('cmd: $cmd returns ${res.exitCode}');
    }
  }

  /// clean system proxy
  Future<void> cleanSystemProxy() async {
    switch (Platform.operatingSystem) {
      case "linux":
        _cleanSystemProxyLinux();
        break;
      case "windows":
        await _cleanSystemProxyWindows();
        break;
      case "macos":
        await _cleanSystemProxyMacos();
    }
  }

  Future<void> _cleanSystemProxyWindows() async {
    setRegistryIntValue(HKEY_CURRENT_USER, regSubKey, ProxyEnable, 0);
  }

  void _cleanSystemProxyLinux() {
    final homeDir = Platform.environment['HOME']!;
    final configDir = path.join(homeDir, ".config/");
    final cmdList = List<List<String>>.empty(growable: true);
    final desktop = Platform.environment['XDG_CURRENT_DESKTOP'];
    final isKDE = desktop == "KDE";
    // gsetting
    cmdList.add(["gsettings", "set", "org.gnome.system.proxy", "mode", "none"]);
    if (isKDE) {
      cmdList.add([
        "kwriteconfig5",
        "--file",
        "$configDir/kioslaverc",
        "--group",
        "Proxy Settings",
        "--key",
        "ProxyType",
        "0"
      ]);
    }
    for (final cmd in cmdList) {
      final res = Process.runSync(cmd[0], cmd.sublist(1));
      print('cmd: $cmd returns ${res.exitCode}');
    }
  }

  Future<bool> getSystemProxyEnable(List<ProxyOption> options) async {
    if (options.isEmpty) {
      return false;
    }
    switch (Platform.operatingSystem) {
      case "windows":
        return await _getSystemProxyEnableWindows(options);
      case "linux":
        return await _getSystemProxyEnableLinux(options);
      case "macos":
        return await _getSystemProxyEnableMacos(options);
    }
    return false;
  }

  Future<bool> _getSystemProxyEnableWindows(List<ProxyOption> options) async {
    String proxy = _getProxyWindows(options);
    if (proxy.isEmpty) {
      return false;
    }
    Object? serverObject =
        getRegistryValue(HKEY_CURRENT_USER, regSubKey, ProxyServer);
    Object? enableObject =
        getRegistryValue(HKEY_CURRENT_USER, regSubKey, ProxyEnable);
    if (serverObject == null || enableObject == null) {
      return false;
    }
    String server = serverObject as String;
    int enable = enableObject as int;
    return server == proxy && (enable == 1);
  }

  Future<bool> _getSystemProxyEnableLinux(List<ProxyOption> options) async {
    throw UnimplementedError(
        '_getSystemProxyEnableLinux() has not been implemented.');
  }

  Future<bool> _getSystemProxyEnableMacos(List<ProxyOption> options) async {
    throw UnimplementedError(
        '_getSystemProxyEnableMacos() has not been implemented.');
  }
}
