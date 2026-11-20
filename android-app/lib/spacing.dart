import 'package:material_ui/material_ui.dart';

abstract final class AppSpacing {
  static const double connected = 2;
  static const double tight = 4;
  static const double related = 8;
  static const double item = 12;
  static const double section = 16;
  static const double pageEnd = 24;

  static const page = EdgeInsets.fromLTRB(section, section, section, pageEnd);
  static const panel = EdgeInsets.all(section);
  static const compactPanel = EdgeInsets.all(item);
}
