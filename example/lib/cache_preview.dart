import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_cache_server/video_cache_server.dart';
import 'dart:ui' as ui;

class CachePreview extends StatefulWidget {
  final _Store _store;
  final double height;

  CachePreview(String indexUrl, VideoCacheServer cacheServer, this.height):_store = _Store(indexUrl, cacheServer);

  @override
  State createState() => CachePreviewState(_store);
}

class CachePreviewState extends State<CachePreview> {
  final _Store store;

  CachePreviewState(this.store);


  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((timeStamp) => _prepareCacheData());
  }

  Future<void> _prepareCacheData() async {
    await this.store.prepareCacheData();
    if(this.mounted) {
      this.setState(() {
      });
      Future.delayed(Duration(milliseconds: 500), _prepareCacheData);
    }
  }

  void update() {
    if(this.mounted) {
      this.setState(() {
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: widget.height,
      child: CustomPaint(
        painter: CachePreviewPainter(store),
      ),
    );
  }
}

class _Store {
  final GlobalKey<CachePreviewState> cachePreviewKey = GlobalKey();
  final String indexUrl;
  final VideoCacheServer cacheServer;
  int lastPaintTimestamp = 0;
  int total;
  int received;
  List<List<int>> ranges;
  bool readyToPaint = false;

  _Store(this.indexUrl, this.cacheServer);

  Future<void> prepareCacheData() async {
    CacheInfo cacheInfo = cacheServer.caches[indexUrl];
    if(cacheInfo != null) {
      // a single file cache
      int total = cacheInfo.total??0;
      int received = 0;
      List<List<int>> ranges = cacheInfo.fragments.map((e) {
        received += e.received;
        return [e.begin, e.end];
      }).toList();
      if(total > 0 && !equals(ranges, this.ranges)) {
        this.total = total;
        this.received = received;
        this.ranges = ranges;
        this.readyToPaint = true;
      }
    } else {
      Iterable<CacheInfo> cacheInfoList = cacheServer.caches.values.where((element) => element.belongTo == indexUrl);
      if(cacheInfoList.isEmpty) {
        return;
      }
      int total = 0;
      // List<List<int>> ranges = List();
      for(CacheInfo cacheInfo in cacheInfoList) {
        total += cacheInfo.total??0;
        // cacheInfo.fragments.forEach((element) => ranges.add([element.begin, element.end]));
      }
      if(total > 0 && total != this.total) {
        this.total = total;
        // this.ranges = ranges;
        this.readyToPaint = true;
      }
    }
  }

  bool equals(List<List<int>> a, List<List<int>> b) {
    if(a == null || b == null) {
      return false;
    }
    if(a.length != b.length) {
      return false;
    }
    for(int i = 0;i < a.length;i++) {
      if(a[i][0] != b[i][0] || a[i][1] != b[i][1]) {
        return false;
      }
    }
    return true;
  }
}

class CachePreviewPainter extends CustomPainter {
  final _Store store;
  final Paint _paint = Paint();
  static Color backgroundColor = Colors.blueGrey;
  static Color cacheColor = Colors.blue[700];

  CachePreviewPainter(this.store);

  @override
  void paint(Canvas canvas, Size size) {
    _paint.style = PaintingStyle.fill;
    _paint.color = backgroundColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _paint);
    if(store.total == null) {
      return;
    }
    _paint.color = cacheColor;
    if(store.ranges != null) {
      double ratio = size.width / store.total;
      store.ranges.forEach((element) {
        canvas.drawRect(Rect.fromLTRB(element[0] * ratio, 0, element[1] * ratio, size.height), _paint);
      });
      ui.ParagraphBuilder paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 16.0));
      paragraphBuilder.addText('Cached:${store.received~/1024}K/${store.total~/1024}K');
      ui.Paragraph paragraph = paragraphBuilder.build();
      paragraph.layout(ui.ParagraphConstraints(width: size.width));
      canvas.drawParagraph(paragraph, Offset((size.width - paragraph.width)/2, (size.height - paragraph.height)/2));
    } else {
      ui.ParagraphBuilder paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 16.0));
      paragraphBuilder.addText('Cached:${store.total~/1024}K');
      ui.Paragraph paragraph = paragraphBuilder.build();
      paragraph.layout(ui.ParagraphConstraints(width: size.width));
      canvas.drawParagraph(paragraph, Offset((size.width - paragraph.width)/2, (size.height - paragraph.height)/2));
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    if(store.readyToPaint == true) {
      store.readyToPaint = false;
      return true;
    }
    return false;
  }
}

// class CachePreview2 extends StatelessWidget {
//   final CacheInfo data;
//
//   CachePreview(this.data);
//
//   @override
//   Widget build(BuildContext context) {
//     Widget body;
//     double width = MediaQuery.of(context).size.width - 32.0;
//     if (data == null || data.total == null || data.total == 0) {
//       body = Container();
//     } else {
//       double ratio = width / data.total;
//       List<Widget> children = List();
//       data.fragments.forEach((f) => children.add(Positioned(
//             left: f.begin * ratio,
//             child: Container(
//               width: Math.max(f.received * ratio, 2.0),
//               height: 64.0,
//               decoration: BoxDecoration(
//                 color: f == data.fragments.last ? Colors.blueAccent[400] : Colors.blueAccent[700],
//               ),
//             ),
//           )));
//       children.add(Center(
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.center,
//           mainAxisAlignment: MainAxisAlignment.center,
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Text(
//               '${data.current}/${data.total}',
//               style: TextStyle(color: Colors.white),
//             ),
//             Text(
//               'fragments:${data.fragments.length}',
//               style: TextStyle(color: Colors.white),
//             ),
//             Text(
//               data.url.substring(data.url.lastIndexOf('/') + 1),
//             ),
//           ],
//         ),
//       ));
//       body = Stack(
//         children: children,
//       );
//     }
//     return Container(
//       color: Colors.blueGrey,
//       width: width,
//       height: 64.0,
//       child: body,
//     );
//   }
// }
