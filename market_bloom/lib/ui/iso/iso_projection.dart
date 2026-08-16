import 'dart:math' as math;
import 'dart:ui';

/// Isometric camera over the normalised 0..1 play field.
///
/// The gameplay layer already thinks in normalised coordinates, so the renderer
/// consumes them directly instead of maintaining a second visual coordinate
/// space. World `(0,0)` is the far corner and `(1,1)` is the corner nearest the
/// player; `+x` runs down-right on screen and `+y` runs down-left.
class IsoProjection {
  const IsoProjection({
    required this.origin,
    required this.tileWidth,
    required this.tileHeight,
    required this.unitHeight,
    required this.scale,
  });

  /// Fits the diamond into [size], reserving head-room at the top for the back
  /// walls and the fixtures standing against them.
  factory IsoProjection.fit(Size size) {
    // The diamond is as wide as the board and a little over half as tall, which
    // leaves the upper band free for wall height without cropping the front
    // corner.
    final tileWidth = size.width * 1.04;
    final tileHeight = size.height * 0.68;
    final wallRoom = size.height * 0.17;
    return IsoProjection(
      origin: Offset(size.width / 2, wallRoom),
      tileWidth: tileWidth,
      tileHeight: tileHeight,
      unitHeight: size.height * 0.30,
      scale: math.min(size.width, size.height) / 380,
    );
  }

  /// Screen position of world `(0,0)` at ground level.
  final Offset origin;

  /// Screen width spanned by the full diamond.
  final double tileWidth;

  /// Screen height spanned by the full diamond.
  final double tileHeight;

  /// Screen height of one unit of world `z`.
  final double unitHeight;

  /// Multiplier for stroke widths and small details.
  final double scale;

  Offset project(double x, double y, [double z = 0]) => Offset(
    origin.dx + (x - y) * tileWidth / 2,
    origin.dy + (x + y) * tileHeight / 2 - z * unitHeight,
  );

  Offset projectOffset(Offset world, [double z = 0]) =>
      project(world.dx, world.dy, z);

  /// Painter's-algorithm key. Larger draws later, i.e. nearer the camera.
  static double depthOf(double x, double y) => x + y;

  /// The ground diamond, used for clipping and for the floor fill.
  Path groundPath() => Path()
    ..moveTo(project(0, 0).dx, project(0, 0).dy)
    ..lineTo(project(1, 0).dx, project(1, 0).dy)
    ..lineTo(project(1, 1).dx, project(1, 1).dy)
    ..lineTo(project(0, 1).dx, project(0, 1).dy)
    ..close();
}
