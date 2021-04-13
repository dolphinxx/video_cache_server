// Copyright (c) 2020, dolphinxx <bravedolphinxx@gmail.com>. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

const String MIME_TYPE_M3U8_1 = 'x-mpegurl';
const String MIME_TYPE_M3U8_2 = 'vnd.apple.mpegurl';

bool isM3u8MimeType(String? mimeType) {
  return mimeType?.contains(MIME_TYPE_M3U8_1) == true || mimeType?.contains(MIME_TYPE_M3U8_2) == true;
}

final RegExp _tagURIRegex = RegExp('URI="([^"]+)"');

/// Determines if it is a m3u8 resource.
bool isM3u8(String? contentType, Uri? uri) {
  return isM3u8MimeType(contentType?.toLowerCase()) || (uri?.path.toLowerCase().endsWith('.m3u8') ?? false);
}

class M3u8 {
  final String raw;
  String? proxied;

  /// true if the m3u8 file contains a decryption tag(`EXT-X-KEY`, `EXT-X-SESSION-KEY`)
  bool encrypted = false;

  /// true if the m3u8 is not a master file and does not contain a `EXT-X-ENDLIST` tag.
  bool endless = false;

  /// true if the m3u8 contains any master playlist tag(`EXT-X-MEDIA`, `EXT-X-STREAM-INF`, `EXT-X-I-FRAME-STREAM-INF`, `EXT-X-SESSION-DATA`, `EXT-X-SESSION-KEY`)
  bool master = false;

  /// playlists appeared in this m3u8 file
  final List<String> playlists = [];

  M3u8(this.raw);
}

/// According to the [rfc8216](https://tools.ietf.org/html/rfc8216)
/// [URI] attribute values in `#EXT-X-I-FRAME-STREAM-INF` or `#EXT-X-MEDIA` tags are replaced by the absolute and proxied ones.
///
/// [URI] attribute values in `#EXT-X-KEY`, `#EXT-X-SESSION-KEY`, `#EXT-X-SESSION-DATA` or `#EXT-X-MAP` tags are replace by the absolute ones.
///
/// The contents of `#EXT-X-STREAM-INF` tags are replaced by the absolute and proxied ones.
///
/// The contents of `#EXTINF` tags are replaced by the absolute ones, if the m3u8 file contains a `#EXT-X-ENDLIST`, then the contents are also proxied at the same time.
///
M3u8 proxyM3u8Content(String content, String Function(String raw) proxy, Uri uri) {
  bool isLive = !content.contains('#EXT-X-ENDLIST');
  String? tagName;
  M3u8 m3u8 = M3u8(content);
  String proxied = content.split('\n').map((line) {
    line = line.trim();
    if (line.startsWith('#EXT')) {
      int colonPos = line.indexOf(':');
      if (colonPos == -1) {
        tagName = line;
        return line;
      }
      tagName = line.substring(0, colonPos);
      if (tagName == '#EXT-X-KEY' || tagName == '#EXT-X-SESSION-KEY') {
        m3u8.encrypted = true;
      }
      if (tagName == '#EXT-X-MEDIA' ||
          tagName == '#EXT-X-STREAM-INF' ||
          tagName == '#EXT-X-I-FRAME-STREAM-INF' ||
          tagName == '#EXT-X-SESSION-DATA' ||
          tagName == '#EXT-X-SESSION-KEY') {
        m3u8.master = true;
      }
      if (tagName == '#EXT-X-I-FRAME-STREAM-INF' || tagName == '#EXT-X-MEDIA') {
        // m3u8 links
        // to absolute and proxy the URI
        return line.replaceFirstMapped(_tagURIRegex, (match) {
          String playlist = uri.resolve(match.group(1)!).toString();
          m3u8.playlists.add(playlist);
          return 'URI="${proxy(playlist)}"';
        });
      }
      if (tagName == '#EXT-X-KEY' || tagName == '#EXT-X-SESSION-KEY' || tagName == '#EXT-X-SESSION-DATA' || tagName == '#EXT-X-MAP') {
        // to absolute the URI
        return line.replaceFirstMapped(_tagURIRegex, (match) {
          return 'URI="${uri.resolve(match.group(1)!).toString()}"';
        });
      }
      return line;
    }
    if (line.isEmpty) {
      tagName = null;
      return line;
    }

    if (tagName == '#EXT-X-STREAM-INF') {
      tagName = null;
      // to absolute and proxy
      String playlist = uri.resolve(line).toString();
      m3u8.playlists.add(playlist);
      return proxy(playlist);
    }
    if (tagName == '#EXTINF') {
      tagName = null;
      // to absolute
      line = uri.resolve(line).toString();
      m3u8.playlists.add(line);
      if (isLive) {
        return line;
      }
      // proxy
      return proxy(line);
    }
    tagName = null;
    return line;
  }).join('\n');
  m3u8.proxied = proxied;
  if (!m3u8.master) {
    m3u8.endless = isLive;
  }
  return m3u8;
}
