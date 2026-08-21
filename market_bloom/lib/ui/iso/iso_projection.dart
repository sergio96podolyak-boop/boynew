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
  /// Fits the room to the frame.
  ///
  /// [band] is the vertical slice actually free of chrome. The board paints
  /// full-bleed so the floor runs behind the HUD and dock, but the room is
  /// *composed* for the band — otherwise the camera centres the shop on the
  /// whole screen while a quarter of it is covered, which is what left a wedge
  /// of empty apron above the dock and pushed the shop off centre.
  factory IsoProjection.fit(Size size, {({double top, double bottom})? band}) {
    // True isometric, per the 45-45 rule: yaw 45 degrees, pitch 35.264 degrees
    // (the angle whose sine is 1/sqrt(3)). Work the projection through and both
    // the diamond's height and the vertical axis come out at 0.577 of its
    // width — and crucially they are *equal*, which is what makes a world cube
    // render as a cube.
    const isoRatio = 0.5774;

    final top = band?.top ?? 0;
    final bottom = band?.bottom ?? size.height;
    final bandHeight = math.max(120.0, bottom - top);
    final bandCentre = (top + bottom) / 2;

    // Overscans the frame so the two side corners of the field — wall, not
    // shopping space — fall outside it. A fully visible diamond reads as a
    // model on a table. Movement is tap-to-move and taps can only land inside
    // the frame, so nothing becomes unreachable.
    //
    // Capped by the band's height as well as driven by width: a width-only
    // zoom made the field taller than a short or landscape frame, so the player
    // saw a fragment of one aisle and no shop at all.
    final tileWidth = math.min(size.width * 1.72, bandHeight / isoRatio * 1.06);
    final tileHeight = tileWidth * isoRatio;

    return IsoProjection(
      origin: Offset(
        size.width / 2,
        // World (0,0) is the far corner, so the field runs a full tileHeight
        // below the origin. Placing the origin half a field above the band's
        // centre puts the shop in the middle of the space the player can
        // actually see.
        bandCentre - tileHeight / 2,
      ),
      tileWidth: tileWidth,
      tileHeight: tileHeight,
      unitHeight: tileWidth * isoRatio,
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
  ///
  /// The sales floor is twelve metres across, so a world unit is twelve metres
  /// and a 3.4 m wall is 0.283 of one. The old value of 1.45 was a seventeen
  /// metre wall, which is why nothing in the room related to anything else.
  static const wallHeight = 3.4 / 12;

  /// Height the ceiling rig hangs at.
  static const ceilingHeight = 2.9 / 12;
}
