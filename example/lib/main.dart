import 'package:flutter/material.dart';

import 'package:video_cache_server_example/player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  List data;

  @override
  void initState() {
    super.initState();
    data = [
      {
        'name': 'mp4',
        'url': 'https://gss3.baidu.com/6LZ0ej3k1Qd3ote6lo7D0j9wehsv/tieba-smallvideo/3_4fc40e51b9b1feaf5bd9a02f935405e4.mp4',
      },
      {
        'name': 'M3U8',
        'url': 'http://devimages.apple.com/iphone/samples/bipbop/bipbopall.m3u8',
      },
    ];
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: Theme.of(context).canvasColor,
        appBar: AppBar(title: const Text('Plugin example app')),
        body: Builder(
          builder: (context) {
            return SingleChildScrollView(
              child: Column(
                children: data.map((item) {
                  return Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    margin: EdgeInsets.only(bottom: 12.0),
                    color: Theme.of(context).cardColor,
                    child: Row(
                      children: [
                        Expanded(child: Text(item['name'])),
                        Container(
                          child: IconButton(
                            icon: Icon(Icons.play_arrow_sharp),
                            onPressed: () {
                              Navigator.of(context)
                                  .push(PageRouteBuilder(pageBuilder: (context, animation, nextAnimation) => PlayerWidget(item['name'], item['url'])));
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            );
          },
        ),
      ),
    );
  }
}
