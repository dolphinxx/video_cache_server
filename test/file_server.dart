import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:async';
import 'package:video_cache_server/video_cache_server.dart';

Future<HttpServer> serve(dynamic file) async {
  HttpServer server = await HttpServer.bind(
    '127.0.0.1',
    0,
  );
  server.listen((HttpRequest request) async {
    print('${request.method.toUpperCase()} ${request.uri}');
    print('Headers:');
    request.headers.forEach((name, values) {
      print('$name=${values.join(',')}');
    });
    HttpResponse response = request.response;
    Stream<List<int>> stream;
    try {
      response.headers.set('content-type', 'application/octet-stream');
      response.statusCode = 200;
      if (file is String && (file.startsWith('http://') || file.startsWith('https://'))) {
        http.Request _request = http.Request('GET', Uri.parse(file));
        http.StreamedResponse _response = await http.Client().send(_request);
        response.contentLength = _response.contentLength;
        stream = _response.stream;
      } else {
        if (file is! File) {
          file = File(file);
        }
        response.contentLength = (file as File).lengthSync();
        stream = file.openRead();
      }
      if (request.headers['range'] != null) {
        Match matcher = RegExp('bytes=(\\d+)-(\\d+)?').firstMatch(request.headers.value('range'));
        int begin = int.parse(matcher.group(1));
        int end = matcher.group(2) != null ? int.parse(matcher.group(2)) : null;
        stream = ByteRangeStream.range(stream, begin: begin, end: end == null ? null : end + 1);
        end = end ?? (response.contentLength - 1);
        response.statusCode = 206;
        response.headers.set('content-range', 'bytes $begin-$end/${response.contentLength}');
        response.contentLength = end - begin + 1;
      }
      await response.addStream(stream);
      await response.flush();
    } catch (e, s) {
      print('$e\n$s');
    } finally {
      try {
        await response.close();
      } catch (e, s) {
        print('Exception when close response.\n$e\n$s');
      }
    }
  });
  return server;
}
