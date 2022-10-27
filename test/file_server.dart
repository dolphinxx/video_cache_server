import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:async';
import 'dart:developer' show log;
import 'package:video_cache_server/video_cache_server.dart';

Future<HttpServer> serve(dynamic file) async {
  HttpServer server = await HttpServer.bind(
    '127.0.0.1',
    0,
  );
  server.listen((HttpRequest httpRequest) async {
    // print('${httpRequest.method.toUpperCase()} ${httpRequest.uri}');
    // print('Headers:');
    // httpRequest.headers.forEach((name, values) {
    //   print('$name=${values.join(',')}');
    // });
    log('request range: ${httpRequest.headers['range']}');
    HttpResponse httpResponse = httpRequest.response;
    Stream<List<int>> stream;
    try {
      httpResponse.headers.set('content-type', 'application/octet-stream');
      httpResponse.statusCode = 200;
      if (file is String && ((file as String).startsWith('http://') || (file as String).startsWith('https://'))) {
        http.Request request = http.Request('GET', Uri.parse(file as String));
        http.StreamedResponse response = await http.Client().send(request);
        httpResponse.contentLength = response.contentLength??-1;
        stream = response.stream;
      } else {
        if (file is! File) {
          file = File(file as String);
        }
        httpResponse.contentLength = (file as File).lengthSync();
        stream = (file as File).openRead();
      }
      if (httpRequest.headers['range'] != null) {
        Match matcher = RegExp('bytes=(\\d+)-(\\d+)?').firstMatch(httpRequest.headers.value('range')!)!;
        int begin = int.parse(matcher.group(1)!);
        int? end = matcher.group(2) != null ? int.parse(matcher.group(2)!) : null;
        stream = ByteRangeStream.range(stream, begin: begin, end: end == null ? null : end + 1);
        end = end ?? (httpResponse.contentLength - 1);
        httpResponse.statusCode = 206;
        httpResponse.headers.set('content-range', 'bytes $begin-$end/${httpResponse.contentLength}');
        httpResponse.contentLength = end - begin + 1;
      }
      await httpResponse.addStream(stream);
      await httpResponse.flush();
    } catch (e, s) {
      log('$e\n$s');
    } finally {
      try {
        await httpResponse.close();
      } catch (e, s) {
        log('Exception when close response.\n$e\n$s');
      }
    }
  });
  return server;
}
