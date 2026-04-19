import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:socks5_proxy/socks.dart';

/// Returns a SOCKS5-proxied [http.Client] when [socksAddr] is non-null and
/// well-formed ("host:port"), otherwise returns a plain [http.Client].
///
/// The caller is responsible for closing the returned client.
http.Client buildTorAwareClient(String? socksAddr) {
  if (socksAddr == null) return http.Client();
  final parts = socksAddr.split(':');
  if (parts.length != 2) return http.Client();
  final host = parts[0];
  final port = int.tryParse(parts[1]);
  if (port == null) return http.Client();

  final httpClient = HttpClient();
  SocksTCPClient.assignToHttpClient(httpClient, [
    ProxySettings(InternetAddress(host), port),
  ]);
  return IOClient(httpClient);
}
