# Calibrate and verify a projection

## Planar screen and camera

1. Set the projector to its native raster. Disable digital keystone and scaling in the projector if the exhibit will perform those corrections. Finish focus and placement and hold them fixed. Place the camera where all four screen corners are visible. Lock its focus, exposure, white balance and zoom. Darken other projectors during each capture.
2. Open the **Mapping** workspace and select the actual output. Choose **Camera calibration wizard**. Set the native width and height, projector desktop origin and camera index.
3. Choose an empty capture directory and click **Capture patterns**. Leave the camera and projector fixed until the sequence finishes. Escape cancels. **Open captures** accepts a previously recorded sequence.
4. On the white reference photograph, click the physical screen corners in top-left, top-right, bottom-right, bottom-left order. Choose **Solve and export**. The solver requires spatial coverage and independently photographed check marks.
5. In Studio select **Apply measured warp** for the same output. This replaces its manual mesh and corner pin. Other outputs retain their settings. Undo restores the prior calibration. Save the exhibit or its calibration profile, then reopen it and inspect the alignment grid at the real projector.
6. For site commissioning, project independent physical reference targets, measure their placement, record the fitted profile, equipment identities and photograph. Inspect seams, shadowing, focus, black level and brightness at the intended viewing positions.

For Ubuntu, the optional desktop packages are `python3-opencv python3-numpy python3-pil python3-pil.imagetk python3-tk`. Windows operators can install desktop Python with Tcl/Tk, then install NumPy, Pillow and a GUI-enabled OpenCV wheel. Set `OPENEXHIBIT_PYTHON` to that interpreter when needed. The embedded Windows interpreter runs contests. The camera wizard uses a desktop Python installation. For analysis of saved captures the headless OpenCV wheel also works. Transfer optional packages before going offline.

## What the solver measures

Black and white frames establish local dynamic range. Complementary binary Gray patterns identify projector columns and rows. Pixels with weak contrast or inconsistent complementary pairs are rejected. The solver estimates a planar camera-to-projector homography with RANSAC. Spatial tiles held out of fitting test the result. Regions near all four corners need decoded samples.

Twenty single-landmark frames follow the fitting sequence. Their imaged centres test the estimated transform independently of the Gray-code decode. Six visible marks spanning all four screen quadrants are required. The default gates are 60% decoded coverage, 1.5 projector pixels at the 95th percentile and 4.5 pixels maximum in both check sets. Tune the acceptance limit to the optics and exhibit requirements. The report records the chosen thresholds, observed residuals and sample counts. A failed solve returns an error and leaves any existing profile at the output path untouched.

The report’s `capture-validated` status describes its supplied images. A real site commissioning record requires separately observed physical targets. Lens distortion, camera motion, a curved screen or changes in focus can increase residuals. A planar solution is appropriate for a planar surface. The metric pose solver supports separately surveyed three-dimensional targets.

## Record and analyse from the command line

```sh
python3 tools/calibrate.py patterns patterns --size 1920 1080
python3 tools/calibrate.py capture photos --size 1920 1080 --origin 1920 0 --camera 0
python3 tools/calibrate.py solve photos --corners screen-corners.json --out measured-warp.json
python3 tools/calibrate.py pose survey.json --out measured-pose.json
python3 tools/calibrate.py photometry luminance.json --out measured-luminance.json
python3 tools/commission.py observations.json --photo after-install.jpg --profile measured-warp.json --out site-record.json
```

`patterns` creates unwarped, native-resolution PNG files and their manifest. For a camera operated separately, display each image unchanged, save the matching photograph with the same filename in a separate directory, and copy `patterns.json` into that directory. The wizard can mark corners on that set. A corner file is a four-item JSON array of camera pixel coordinates. Camera coordinates use pixel centres. The software converts the final projector locations into Godot’s edge-based normalized UV coordinates.

**Metric survey.** Supply `points_m` and corresponding `pixels` for at least eight non-coplanar targets, plus `check_points_m` and `check_pixels` for at least four different non-coplanar targets. Specify a 3 × 3 `intrinsics` matrix and optional OpenCV `distortion`. Use the installation’s metre-based right-handed world coordinate system. Adding `size` exports the projector position, aim, up, throw and lens shift for Studio. This import supports square pixels, negligible skew and upstream-corrected lens distortion.

**Luminance response.** Measure neutral patch luminance with a meter. Supply `fit` and `check` as arrays of `[drive fraction, measured luminance]`. The fit needs dark, white and at least three intermediate levels. Check at least three different low, mid and high levels. An optional `target_white` can reduce a brighter projector to a common level. Import the report through **Import surveyed pose or luminance response**. Per-channel colour measurement and automatic spatial photometric correction remain open. Optical black and brightness limits remain physical.

**Field measurements.** An observations file records `site`, `projector_serial`, `camera_id`, `operator`, `capture_time`, `physical_size_mm`, `camera_size`, the measured `screen_corners`, and a site-selected `limit_mm`. Supply at least nine `requested_uv` positions distributed over the screen and the corresponding `observed_camera_px` from the independent photograph. The tool returns per-target, p95 and maximum millimetre residuals, a pass/fail against the site limit, and SHA-256 digests for the evidence files. Verify each physical output, then measure shared seams with both projectors active. Keep the original photograph, report and exhibit together.

## Curved surfaces and overlap

The sphere and cylinder shaders trace projector rays into each surface’s local coordinate frame. Radius, physical cylinder height, orientation and the 360-degree seam affect the sampled coordinate. Spheres and domes support equirectangular content and horizontal 4 × 3 cube crosses. The middle row is left, front, right, back. The zenith and nadir sit above and below the front face. Use square tiles. The ideal coverage preview identifies uncovered polar regions. It does not measure a lens or a shadow.

Version 0.2 normalizes complementary blend weights at all exponents, so two equal matched white feeds sum to a constant across a nominal overlap. Older projects using a non-unit blend exponent may look brighter along that seam. Check them after updating. Black compensation can lift a level. Additive projectors cannot subtract light. Genlock, physical shutter timing and visitor shadows require their own hardware evaluation.

The capture method follows the complementary image and shadow-mask construction in the OpenCV structured-light documentation. [OpenCV Gray-code reference](https://docs.opencv.org/4.x/d1/dec/classcv_1_1structured__light_1_1GrayCodePattern.html)
