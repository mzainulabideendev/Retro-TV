import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:retro_tv/main.dart';

void main() {
  testWidgets('App boots and shows RETRO TV title', (WidgetTester tester) async {
    await tester.pumpWidget(const RetroTvApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
