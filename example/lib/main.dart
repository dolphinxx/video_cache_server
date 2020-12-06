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
        'url': 'https://www.sample-videos.com/video123/mp4/240/big_buck_bunny_240p_30mb.mp4',
      },
      {
        'name': 'mp4 - 2',
        'url': 'http://vfx.mtime.cn/Video/2019/03/13/mp4/190313094901111138.mp4',
      },
      {
        'name': 'flv',
        'url': 'https://www.sample-videos.com/video123/flv/240/big_buck_bunny_240p_30mb.flv',
      },
      {
        'name': 'mkv',
        'url': 'https://www.sample-videos.com/video123/mkv/240/big_buck_bunny_240p_30mb.mkv',
      },
      {
        'name': '3gp',
        'url': 'https://www.sample-videos.com/video123/3gp/240/big_buck_bunny_240p_30mb.3gp',
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
