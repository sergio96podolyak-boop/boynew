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
    final tileWidth = size.width * 1.02;
    final tileHeight = size.height * 0.62;
    final wallRoom = size.height * 0.22;
    return IsoProjection(
      origin: Offset(size.width / 2, wallRoom),
      tileWidth: tileWidth,
      tileHeight: tileHeight,
      unitHeight: size.height * 0.22,
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

  /// Inverse of [project] on the ground plane (z = 0).
  ///
  /// Turns a screen tap back into play-field coordinates so touch control
  /// matches the isometric view — without this the player walks to a rotated,
  /// unrelated spot and control feels broken.
  Offset unproject(Offset screen) {
    final dx = screen.dx - origin.dx;
    final dy = screen.dy - origin.dy;
    final xMinusY = 2 * dx / tileWidth;
    final xPlusY = 2 * dy / tileHeight;
    return Offset((xPlusY + xMinusY) / 2, (xPlusY - xMinusY) / 2);
  }

  /// Painter's-algorithm key. Larger draws later, i.e. nearer the camera.
  static double depthOf(double x, double y) => x + y;

  /// The ground diamond, used for clipping and for the floor fill.
  Path groundPath() => extendedGroundPath(0);

  /// A ground diamond grown by [margin] world units on every side.
  ///
  /// The shopping field is only 0..1, but the room is drawn larger so the floor
  /// reaches the frame edges instead of floating as a small tile in a void.
  Path extendedGroundPath(double margin) {
    final lo = -margin;
    final hi = 1 + margin;
    return Path()
      ..moveTo(project(lo, lo).dx, project(lo, lo).dy)
      ..lineTo(project(hi, lo).dx, project(hi, lo).dy)
      ..lineTo(project(hi, hi).dx, project(hi, hi).dy)
      ..lineTo(project(lo, hi).dx, project(lo, hi).dy)
      ..close();
  }

  /// How far the drawn room extends past the play field on each side.
  static const roomMargin = 0.30;
}
