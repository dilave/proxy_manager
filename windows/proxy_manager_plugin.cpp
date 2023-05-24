#include "proxy_manager_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <WinInet.h>
#include <Ras.h>
#include <RasError.h>
#include <vector>
#include <iostream>

#pragma comment(lib, "wininet")
#pragma comment(lib, "Rasapi32")

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>

// Big Thanks to Qv2ray opensource project
std::string encodeableMapToString(const flutter::EncodableMap* args){
    auto proxy = std::get<std::string>(args->at(flutter::EncodableValue("proxy")));
    return proxy;
}
void setSystemProxy(const flutter::EncodableMap* args) {
    INTERNET_PER_CONN_OPTION_LISTA list;
    DWORD dwBufSize = sizeof(list);
    // Fill the list structure.
    list.dwSize = sizeof(list);
    // NULL == LAN, otherwise connectoid name.
    list.pszConnection = nullptr;

    auto url = encodeableMapToString(args);

    list.dwOptionCount = 2;
    list.pOptions = new INTERNET_PER_CONN_OPTIONA[2];

    if (nullptr == list.pOptions)
    {
        return;
    }

    // Set flags.
    list.pOptions[0].dwOption = INTERNET_PER_CONN_FLAGS;
    list.pOptions[0].Value.dwValue = PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY;
    // Set proxy name.
    list.pOptions[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
    list.pOptions[1].Value.pszValue =  url.data();
    // Set proxy override.
    // list.pOptions[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
    // auto localhost = L"localhost";
    // list.pOptions[2].Value.pszValue = NO_CONST(localhost);

    if (!InternetSetOptionA(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &list, dwBufSize))
    {
        // LOG("InternetSetOption failed for LAN, GLE=" + QSTRN(GetLastError()));
    }

    RASENTRYNAMEA entry;
    entry.dwSize = sizeof(entry);
    std::vector<RASENTRYNAMEA> entries;
    DWORD size = sizeof(entry), count;
    LPRASENTRYNAMEA entryAddr = &entry;
    auto ret = RasEnumEntriesA(nullptr, nullptr, entryAddr, &size, &count);
    if (ERROR_BUFFER_TOO_SMALL == ret)
    {
        entries.resize(count);
        entries[0].dwSize = sizeof(RASENTRYNAMEA);
        entryAddr = entries.data();
        ret = RasEnumEntriesA(nullptr, nullptr, entryAddr, &size, &count);
    }
    if (ERROR_SUCCESS != ret)
    {
        return;
    }

    // Set proxy for each connectoid.
    for (DWORD i = 0; i < count; ++i)
    {
        list.pszConnection = entryAddr[i].szEntryName;
        if (!InternetSetOptionA(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &list, dwBufSize))
        {
            // LOG("InternetSetOption failed for connectoid " + QString::fromWCharArray(list.pszConnection) + ", GLE=" + QSTRN(GetLastError()));
        }
    }

    delete[] list.pOptions;
    InternetSetOptionA(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
    InternetSetOptionA(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
}

bool getSystemProxyEnable(const flutter::EncodableMap* args) {
    auto url = encodeableMapToString(args);

    INTERNET_PER_CONN_OPTION_LISTA list;
    INTERNET_PER_CONN_OPTIONA option[2];
    unsigned long nSize = sizeof(INTERNET_PER_CONN_OPTION_LIST);
    option[0].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
    option[1].dwOption = INTERNET_PER_CONN_FLAGS;
  
    list.dwSize = sizeof(INTERNET_PER_CONN_OPTION_LIST);
    list.pszConnection = NULL;
    list.dwOptionCount = 2;
    list.dwOptionError = 0;
    list.pOptions = option;

    if(!InternetQueryOptionA(NULL, INTERNET_OPTION_PER_CONNECTION_OPTION, &list, &nSize)){
        return false;
    }
    if (option[0].Value.pszValue != NULL){
        if(url != option[0].Value.pszValue){
            return false;
        }
        GlobalFree(option[0].Value.pszValue);
    }
    
    bool enable = option[1].Value.dwValue & PROXY_TYPE_PROXY;
    return enable;
}
void cleanSystemProxy() {
    INTERNET_PER_CONN_OPTION_LISTA list;
    DWORD dwBufSize = sizeof(list);
    // Fill the list structure.
    list.dwSize = sizeof(list);
    // NULL == LAN, otherwise connectoid name.
    list.pszConnection = nullptr;
    // clean
    //
    list.dwOptionCount = 1;
    list.pOptions = new INTERNET_PER_CONN_OPTIONA[1];

    // Ensure that the memory was allocated.
    if (nullptr == list.pOptions)
    {
        // Return if the memory wasn't allocated.
        return;
    }
    // Set flags.
    list.pOptions[0].dwOption = INTERNET_PER_CONN_FLAGS;
    list.pOptions[0].Value.dwValue = PROXY_TYPE_DIRECT;

    // Set proxy for LAN.
    InternetSetOptionA(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &list, dwBufSize);

    RASENTRYNAMEA entry;
    entry.dwSize = sizeof(entry);
    std::vector<RASENTRYNAMEA> entries;
    DWORD size = sizeof(entry), count;
    LPRASENTRYNAMEA entryAddr = &entry;
    auto ret = RasEnumEntriesA(nullptr, nullptr, entryAddr, &size, &count);
    if (ERROR_BUFFER_TOO_SMALL == ret)
    {
        entries.resize(count);
        entries[0].dwSize = sizeof(RASENTRYNAMEA);
        entryAddr = entries.data();
        ret = RasEnumEntriesA(nullptr, nullptr, entryAddr, &size, &count);
    }
    if (ERROR_SUCCESS != ret)
    {
        return;
    }

    // Set proxy for each connectoid.
    for (DWORD i = 0; i < count; ++i)
    {
        list.pszConnection = entryAddr[i].szEntryName;
        if (!InternetSetOptionA(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &list, dwBufSize))
        {
            // error
        }
    }

    delete[] list.pOptions;
    InternetSetOptionA(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
    InternetSetOptionA(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
}

namespace proxy_manager {

// static
void ProxyManagerPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "proxy_manager",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<ProxyManagerPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

ProxyManagerPlugin::ProxyManagerPlugin() {}

ProxyManagerPlugin::~ProxyManagerPlugin() {}

void ProxyManagerPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("getPlatformVersion") == 0) {
    std::ostringstream version_stream;
    version_stream << "Windows ";
    if (IsWindows10OrGreater()) {
      version_stream << "10+";
    } else if (IsWindows8OrGreater()) {
      version_stream << "8";
    } else if (IsWindows7OrGreater()) {
      version_stream << "7";
    }
    result->Success(flutter::EncodableValue(version_stream.str()));
  }
  else if (method_call.method_name().compare("cleanSystemProxy") == 0) {
      cleanSystemProxy();
      result->Success();
  }
  else if (method_call.method_name().compare("setSystemProxy") == 0) {
      auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      setSystemProxy(arguments);
      result->Success();
  }
  else if (method_call.method_name().compare("getSystemProxyEnable") == 0){
      auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      bool enable = getSystemProxyEnable(arguments);
      result->Success(flutter::EncodableValue(enable ? "true" : "false"));
  }
  else {
    result->NotImplemented();
  }
}

}  // namespace proxy_manager
