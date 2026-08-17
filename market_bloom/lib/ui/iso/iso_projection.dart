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
    // Camera. The previous framing used a diamond taller than it was wide,
    // which is a near-overhead angle: it reads as a floor plan rather than a
    // place you stand in. This is a true 2:1 isometric — the diamond is twice
    // as wide as it is tall — with a large unit height so fixtures, walls and
    // people have real vertical presence instead of lying flat on the plane.
    // The camera is zoomed *into* the shop rather than framing the whole
    // diamond. Fitting the field to the frame width left it as a small raised
    // island in a sea of apron; overscanning crops the two side corners — which
    // are wall, not shopping space — and lets the sales floor fill the screen.
    //
    // Nothing becomes unreachable: movement is tap-to-move and taps can only
    // land inside the frame, so the player cannot be sent off-camera.
    final tileWidth = size.width * 1.26;
    return IsoProjection(
      origin: Offset(
        size.width / 2,
        // The room sits low so the back wall, its fascia and the hanging light
        // rig occupy the upper third, which used to be empty sky.
        size.height * 0.30,
      ),
      tileWidth: tileWidth,
      tileHeight: tileWidth * 0.76,
      unitHeight: tileWidth * 0.33,
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

  /// The room's floor: asymmetric on purpose.
  ///
  /// The far side stops at the walls, because beyond a wall there is nothing to
  /// see. The near side runs well past the play field so the floor carries all
  /// the way to the bottom of the frame — the camera is standing on that side,
  /// so there is no wall to end it. A symmetric room forced a choice between
  /// visible walls and a floor that reached the frame edge; this gets both.
  Path roomPath() => _diamond(-farMargin, 1 + nearMargin);

  /// A ground diamond grown by [margin] world units on every side.
  Path extendedGroundPath(double margin) => _diamond(-margin, 1 + margin);

  Path _diamond(double lo, double hi) {
    return Path()
      ..moveTo(project(lo, lo).dx, project(lo, lo).dy)
      ..lineTo(project(hi, lo).dx, project(hi, lo).dy)
      ..lineTo(project(hi, hi).dx, project(hi, hi).dy)
      ..lineTo(project(lo, hi).dx, project(lo, hi).dy)
      ..close();
  }

  /// How far the floor runs past the play field toward the back walls.
  static const farMargin = 0.24;

  /// How far the floor runs past the play field toward the camera.
  static const nearMargin = 1.10;

  /// Legacy alias: the far margin is where the walls stand.
  static const roomMargin = farMargin;

  /// Height of the shop's walls, in world units.
  static const wallHeight = 1.45;

  /// Height at which the ceiling rig hangs.
  static const ceilingHeight = 1.30;
}
