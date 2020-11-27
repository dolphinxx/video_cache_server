// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// This file is modified from `package:http/src/io_streamed_response.dart`.

import 'dart:io';

// ignore: implementation_imports
import 'package:http/src/base_request.dart';

// ignore: implementation_imports
import 'package:http/src/streamed_response.dart';

typedef Abort = void Function();

///
/// Added the getter [requestUri] to get the last requested uri.
/// When we get a relative Uri from a response content, we may want to resolve it to an absolute one.
/// To archive this we need to add ability to get the actual uri this response is associated with, no matter how many redirects are performed.
/// Since the url returned from [BaseRequest] is the start url not the latest one.
///
/// Added [abort] to call [HttpClientRequest.abort] from this response, because the `http` package does not expose it, and it's more difficult to get the [HttpClientRequest] instance.
///
///
///
/// An HTTP response where the response body is received asynchronously after
/// the headers have been received.
class IOStreamedResponse extends StreamedResponse {
  final HttpClientResponse _inner;
  List<dynamic> _redirects;

  List<dynamic> get redirects {
    if (_redirects != null) {
      return _redirects;
    }
    if (_inner.redirects == null) {
      _redirects = [];
    } else {
      Uri u = request.url;
      _redirects = _inner.redirects.map((_) {
        Uri _u = _.location;
        if (!_u.isAbsolute) {
          _u = u.resolveUri(_u);
        }
        u = _u;
        return {'statusCode': _.statusCode, 'method': _.method, 'location': _u};
      }).toList();
    }
    return _redirects;
  }

  Uri get requestUri => redirects?.isNotEmpty == true ? redirects.last['location'] : request.url;

  /// This Function transparently call [HttpClientRequest.abort]
  final Abort abort;

  /// Creates a new streaming response.
  ///
  /// [stream] should be a single-subscription stream.
  IOStreamedResponse(
    Stream<List<int>> stream,
    int statusCode, {
    int contentLength,
    BaseRequest request,
    Map<String, String> headers = const {},
    bool isRedirect = false,
    bool persistentConnection = true,
    String reasonPhrase,
    this.abort,
    HttpClientResponse inner,
  })  : _inner = inner,
        super(
          stream,
          statusCode,
          contentLength: contentLength,
          request: request,
          headers: headers,
          isRedirect: isRedirect,
          persistentConnection: persistentConnection,
          reasonPhrase: reasonPhrase,
        );

  /// Detaches the underlying socket from the HTTP server.
  Future<Socket> detachSocket() async => _inner.detachSocket();
}
