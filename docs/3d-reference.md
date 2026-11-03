# Capsule Elite 3D reference

Notes behind `Shared/Mic3DView.swift`. Photos are linked, not copied (no license to redistribute).

## Sources

- ocinside.de review, photo set (white version, incl. lit LEDs): https://www.ocinside.de/review/nzxt_capsule_elite/2/
  - full photos: `https://www.ocinside.de/media/uploads/nzxt_capsule_elite_N.jpg`, N = 1…12.
    Best ones: 4 (side), 5 (front ¾), 10 (underside), 11 (rear + front LEDs lit), 12 (top/front edge).
- Black version product photo: https://www.pccasegear.com/products/71607/nzxt-capsule-elite-microphone-black
- White version: https://www.pccasegear.com/products/71608/nzxt-capsule-elite-microphone-white
- Specs (NZXT, via retailers): 241 × 97 × 97 mm with stand, 292 g mic only, 561 g with stand, 3/8" thread.
- Reviews describing the lighting: https://basic-tutorials.com/reviews/peripherals/nzxt-capsule-elite-review/ ,
  https://www.windowscentral.com/hardware/nzxt-capsule-elite-review , https://www.thumbculture.co.uk/nzxt-capsule-elite-microphone-review

## Shape (body height 17 cm; measured on photo 4, a true side view, and photo 5)

- **Body**: upright rounded slab, 6.4 wide × 17 tall × 4.4 deep including the grille. The shell
  (matte plastic, white or black) is 3.0 deep; below the grille it steps forward to 3.7 for the knob panel.
- **Front grille**: steel mesh with fine staggered holes, a domed cap 12.9 tall over the upper front.
  It stands 1.5 proud of the shell, its front is gently crowned across the width, and all its edges
  are rounded (radius ~1), so from the side you see a mesh strip in front of the plastic.
- **Lower front panel**: below the grille: knurled gain knob (Ø 1.4) left, "NZXT" logo right.
- **Sides**: two staggered columns of round holes (Ø ~0.45) in the rear half of each side, 19 rows;
  knurled headphone roller (Ø 1.8) in the right side, 3 cm above the bottom.
- **Rear**: perforated plate, large round holes on a 9-column grid (~0.58 pitch) over almost the whole back.
- **Underside**: pivot screw (3/8"), 3.5 mm jack, USB-C.
- **Stand**: square base 9.4 × 9.4 × 0.55 with rounded edges, round post Ø 1.4 just behind the body,
  knuckle joint (screw caps on both sides) 3.5 above the body's bottom; ground is 6.4 below the body.
  Aluminium on white, black on black. The body tilts on the joint; the model leans it back ~9°.

## LEDs

- **Front, 7 LEDs**: a thin horizontal light bar behind the bottom of the front mesh, just above the
  lower panel, ~70 % of the grille width. They blend into one bar (photo 11, right). Mute turns it red.
- **Rear, 9 LEDs**: the top row of the rear perforation grid, one LED per hole (photo 11, left: a rainbow
  wave across 9 holes, rows below stay dark).

## Model choices

- Built procedurally in SceneKit, no assets. The grille is a custom crowned rounded-slab mesh
  (`MicGeometry.crownedSlab`; `SCNBox` doesn't expose its chamfered vertices, so it can't be deformed).
- Mesh and rear perforations = generated hole textures used as transparency, with a dark inner body behind
  them so the holes read as depth. Side holes = dark discs with a lighter lip.
- Front LEDs = 7 emissive bars between the inner body and the mesh, close enough to read as one bar;
  rear LEDs = 9 emissive discs behind the top row of rear holes. HDR camera bloom plus additive glow sprites.
- Studio environment map, key light with soft shadows, rim light; clear-coated plastic, knurl normal map.
- Interaction (`Motion` in `MicModel.swift`): drag spins (and tilts ±20°), release coasts on a critically damped
  spring aimed exactly where its momentum carries it, click flips, a change of focus or lighting turns back to the edited side.

## Checking it

`docs/mic3d-render/main.swift` renders the model offscreen and self-checks LED colors and the motion
(command at the top of the file). Results in `docs/mic3d-renders/`: `sheet.png` (black front/rear,
white front/rear, white side like photo 4, transparent, all off), single renders, and `live-drag.png`: the real
view in a window over a gradient: front, mid-drag, after momentum, after a click, focus rear, white.
`Mic3DView.swift` also has a `#Preview`.
