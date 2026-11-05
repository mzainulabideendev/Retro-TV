import 'package:flutter/widgets.dart';

import 'channel_logo_stub.dart'
    if (dart.library.js_interop) 'channel_logo_web.dart'
    as impl;

/// Displays a channel logo.
///
/// On the web this renders a real `<img>` element through a platform view
/// whose view type is unique per channel + URL. Flutter's built-in
/// `Image.network(webHtmlElementStrategy: ...)` uses ONE shared view type and
/// only applies `src` when the platform view is first created; when a list is
/// filtered/reordered the reused platform view keeps the previous row's image,
/// which is why search could show another cartoon's logo. A unique view type
/// per channel forces the correct `<img src>` every time.
class ChannelLogo extends StatelessWidget {
  final String channelId;
  final String url;
  final double width;
  final double height;
  final double borderRadius;

  const ChannelLogo({
    super.key,
    required this.channelId,
    required this.url,
    required this.width,
    required this.height,
    this.borderRadius = 6,
  });

  @override
  Widget build(BuildContext context) {
    return impl.buildChannelLogo(
      channelId: channelId,
      url: url,
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }
}
