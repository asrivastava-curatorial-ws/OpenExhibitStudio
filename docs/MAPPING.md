See the [0.2 calibration and on-site measurement guide](CALIBRATION.md) for camera capture, optical verification, metric pose and photometry.

# Physical layout and calibration

## Coordinate conventions

Surfaces use metres. The analytic cylinder and sphere are upright, with +Y up, longitude zero at +Z and positive longitude towards +X. Geographic input is an equirectangular 2:1 texture, north at the top, Greenwich halfway across. The project canvas, display pixels and normalized texture coordinates use a top-left origin. The ray model describes surface-based illumination. A visitor-centred CAVE perspective solution needs the viewer pose and off-axis frusta and remains outside this release.

Planar feeds crop a normalized **view** rectangle from a scene. The scene can be different for each output. Linear and vertical panorama presets generate neighbouring regions with shared margins and complementary linear ramps. Keep both projector feeds on the same colour pipeline. On a room preset the 4 × 3 cube-cross atlas has left/front/right/back across the middle row, ceiling above front, floor below front. The room sample assigns six independent scenes instead.

## Calibrate a feed

1. Extend the operating-system desktop across the projectors. Identify display indices in the operating system. In Studio choose **Mapping → Output settings** and set the index and native resolution. If an assigned screen is absent, Player opens a window and records the missing display in its trace.
2. Choose **Alignment grid** or **Colour bars** in the preview. In Player press F2 to cycle content, grid and bars. Window titles identify individual output IDs. Full-screen monitor placement requires a commissioning check in the local window manager.
3. Under **Warp handles**, select **Corner pin**. Move TL, TR, BR and BL to fit the surface. The renderer solves an inverse homography. Under **3 × 3 mesh**, adjust local control points. The renderer inverts eight triangles. Folded cells are rejected.
4. Set blend widths as fractions of a feed’s width or height. For example, left = 0.08 fades the leftmost 8%. The exponent changes the curve. Gamma and RGB gains shape brightness. Black lift increases the encoded image floor and cannot reduce a projector’s optical black level.
5. For a grayscale mask, import the PNG into the asset library and set the output’s **mask** to its asset ID in calibration JSON. The red channel sets transmission. Black suppresses the digital output. A named mask must also exist in any project that imports its calibration profile.
6. Save the profile, reopen it and verify the physical output. **Save preview PNG** renders a single corrected output at its assigned dimensions. Use the render tool for an AVI or numbered PNG sequence.

The output’s **position** and **aim** are world-space XYZ triples. **throw** is distance divided by projected width. Horizontal FOV is `2 atan(0.5 / throw)`. For analytic and mesh surfaces, **shift** is a fraction of full raster width and height. A plain planar panorama uses a manually calibrated view and warp. Moving its virtual projector aids design review but does not recompute the planar homography.

## Curved screens

Cylinder ray intersection computes longitude on the actual radius and height from the hit’s Y coordinate. The screen occupies −height/2 to +height/2 around its centre. Its arc is centred on +Z. A 360° ring wraps at ±180°. Test a periodic grid across the seam. Changing output count preserves the surface height when the new layout uses the same configured height.

Sphere outputs intersect a projector ray with the nearest positive point on the sphere. Longitude and latitude select the equirectangular texel. A numeric session variable named **longitude** rotates the texture in degrees. The supplied encoder sends absolute ticks, scaled to one degree per tick in the example. Set the gateway scale for a different encoder. Equatorial projectors leave polar blind regions. **Coverage analysis** maps ideal missing, single and overlapping illumination, weights spherical area by latitude and explicitly tests both poles. Change projector aim and position or add elevated projectors before physical calibration.

The dome preset samples an upper hemisphere with an equidistant fisheye preview. It is a content transform for a centred ideal dome. A real off-centre fisheye lens or spherical-mirror system needs a measured optical transform.

## Objects and relief maps

Select **Custom object** or **Relief map** and attach an embedded GLB, embedded glTF or UV-mapped OBJ surface in Installation. Use metres for geometry. Set the physical pose and scale on the surface and position/aim/throw on the output. The player places a textured mesh in an independent 3D viewport, projects it with a perspective frustum and depth-tests its triangles. It applies the feed’s corner/mesh warp, blend and correction afterward. The projected mesh feed is display-only. A separate touchscreen or hardware input controls the scene.

OBJ reads faces, UV indices and negative indices, and triangulates faces as fans. Triangulate concave polygons beforehand. Linked glTF textures and buffers must be embedded. The mesh viewer is an orbit preview and importer. Full 3D modelling, editing UV islands, arbitrary inter-object shadow volumes, lens-specific distortion fitting, measured optical black equalization and structured-light reconstruction remain engineering work.

No physical projector was available for these tests. Lens shift limits, brightness, throw, optical occlusion, black levels, seam alignment, physical page curvature and hardware frame synchronization require site measurement.
