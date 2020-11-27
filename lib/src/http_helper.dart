// Copyright (c) 2020, dolphinxx <bravedolphinxx@gmail.com>. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:collection';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// A wrapper of the [HttpRequest].
class ProxyRequest {
  String method;
  Uri requestedUri;
  String protocolVersion;
  Headers _headers;
  Stream<Uint8List> _body;
  final HttpRequest httpRequest;

  ProxyRequest.fromHttpRequest(HttpRequest httpRequest) : httpRequest = httpRequest {
    Map<String, List<String>> headers = Map();
    httpRequest.headers.forEach((k, v) {
      headers[k] = v;
    });
    this.method = httpRequest.method;
    this.requestedUri = httpRequest.requestedUri;
    this.protocolVersion = httpRequest.protocolVersion;
    this._headers = Headers.from(headers);
    this._body = httpRequest;
  }

  Map<String, String> get headers => _headers.singleValues;

  Stream<List<int>> read() => _body;
}

/// Unmodifiable, key-case-insensitive header map.
class Headers {
  Map<String, String> _singleValues;
  Map<String, List<String>> _data = Map();

  Headers.from(Map<String, List<String>> values) {
    if (values != null && values.isNotEmpty) {
      values.forEach((key, value) {
        _data[key.toLowerCase()] = List.of(value);
      });
    }
  }

  Map<String, String> get singleValues => _singleValues ??= UnmodifiableMapView(
        _data.map((key, value) => MapEntry(key, _joinHeaderValues(value))),
      );

  /// Multiple header values are joined with commas.
  /// See http://tools.ietf.org/html/draft-ietf-httpbis-p1-messaging-21#page-22
  String _joinHeaderValues(List<String> values) {
    if (values == null || values.isEmpty) return null;
    if (values.length == 1) return values.single;
    return values.join(',');
  }
}

/// Parse and hold a range header value. If more than one range set present, only the first one is used.
///
/// https://tools.ietf.org/html/rfc7233
///
///  https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Range
class RequestRange {
  /// inclusive
  int begin;

  /// inclusive
  int end;

  /// <unit>=-<suffix-length>
  int suffixLength;
  bool specified = false;

  RequestRange.parse(String raw) {
    if (raw == null) {
      return;
    }
    RegExpMatch matcher = RegExp('bytes=(\\d+)?-(\\d+)?').firstMatch(raw);
    if (matcher != null) {
      this.specified = true;
      this.begin = matcher.group(1) == null ? null : int.parse(matcher.group(1));
      this.end = matcher.group(2) == null ? null : int.parse(matcher.group(2));
      if (this.begin == null) {
        this.suffixLength = this.end;
        this.end = null;
      }
    }
  }

  RequestRange.unspecified();

  void suffixLengthToRange(int total) {
    if (!specified) {
      throw StateError('This RequestRange instance is not a specified one, it cannot be converted to range one.');
    }
    this.end = total - 1;
    this.begin = total - suffixLength;
    this.suffixLength = null;
  }

  bool isSameRange(int begin, int end) {
    if (!this.specified) {
      return begin == 0 && end == null;
    }
    return (this.begin == begin || (this.begin == null && begin == 0)) && this.end == end;
  }

  bool equals(RequestRange another) {
    if (another == null) {
      return false;
    }
    return this.specified == another.specified && this.begin == another.begin && this.end == another.end && this.suffixLength == another.suffixLength;
  }
}

/// Parse and hold a content-range header value. Care unit in bytes only, and `<unit> */<size>` is not supported(416 Range Not Satisfiable)
///
/// https://tools.ietf.org/html/rfc7233
///
/// https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Range
class ResponseRange {
  /// inclusive
  int begin;

  /// inclusive
  int end;
  int size;
  bool specified = false;

  ResponseRange.unspecified();

  ResponseRange.parse(String raw) {
    if (raw == null) {
      return;
    }
    RegExpMatch matcher = RegExp('bytes *(\\d+)-(\\d+)/(\\d+|\\*)').firstMatch(raw);
    if (matcher != null) {
      this.specified = true;
      this.begin = int.parse(matcher.group(1));
      this.end = int.parse(matcher.group(2));
      if (matcher.group(3) != '*') {
        this.size = int.parse(matcher.group(3));
      }
    }
  }

  bool isSameRange(int begin, int end) {
    if (!this.specified) {
      return begin == 0 && end == null;
    }
    return (this.begin == begin || (this.begin == null && begin == 0)) && this.end == end;
  }

  bool equals(ResponseRange another) {
    if (another == null) {
      return null;
    }
    return this.specified == another.specified && this.begin == another.begin && this.end == another.end && this.size == another.size;
  }
}

http.Request cloneRequest(http.Request request) {
  http.Request req = http.Request(request.method, request.url);
  req.bodyBytes = request.bodyBytes;
  req.encoding = request.encoding;
  req.headers.addAll(request.headers);
  req.followRedirects = request.followRedirects;
  return req;
}