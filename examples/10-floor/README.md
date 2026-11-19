# Wake the floor

Open project.oes.json in Studio and choose **Test exhibit**, or open it in the standalone Player.

Move the slider or inject motion_x = 0.2 and motion_y = 0.7 to reposition the origin. An optional overhead webcam sends the centroid of frame differences.

**Installation.** Overhead projector and ordinary webcam, or just a monitor for testing.

Run tools/vision.py motion with the local gateway. Camera coordinates start at top left; the planar homography option aligns them to the floor.


