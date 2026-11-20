# Green-screen photo booth

Visitors stand in front of a green cloth. A camera films them, the green is replaced live by a
background video or picture, and they can take a photo or a short video home by scanning a QR
code with their phone. Everything stays on the local network: the booth computer keeps the files
for a limited time and nothing is uploaded to the internet.

Example: **16 · Green-screen photo booth** on Studio's start screen (three small drawn sample
backgrounds — replace them with your own).

## What you need

- A matte green cloth or painted wall, lit evenly by its own lamps, and separate lights for people.
- A webcam or HDMI capture card on the booth computer, and a screen or projector for the booth.
- Chrome, Edge or Firefox on the booth computer. Python 3.10 or newer runs the booth service
  (included in the Windows installer; standard on Ubuntu, Kubuntu, Debian and Fedora).
- For downloads: phones on the same Wi-Fi or LAN as the booth computer. Guest networks that keep
  devices apart do not work.

## Set it up in Studio

1. Open (or create) an exhibit and go to **Green screen** in the RUN group.
2. **Backgrounds → Add video or picture…** for each background, or drop files onto Studio while
   the Green screen workspace is open. Rename, reorder, and choose **Fill the screen** (crop to fit)
   or **Show the whole picture** (letterbox) for each.
3. Optionally **Choose overlay picture…**: a PNG the size of the screen (1920 × 1080) with
   transparency, for a frame or logo. It is drawn over the booth picture and every photo and video.
4. Under **For visitors** set the title, photos and/or videos, countdown, video length, how long
   files are kept, idle background changes and mirroring.
5. Under **Booth** choose the network under **Who can download** and press **Start booth** (or
   **Start with setup**). The booth opens in the browser on this computer; allow the camera.

## Calibrate on the booth

Press **Ctrl+Shift+S** on the booth (or use **Booth setup** in Studio).

| Control | What it does |
| --- | --- |
| Camera | Which camera to use; remembered by name. |
| Mirror | Selfie view (people see themselves as in a mirror). |
| Key colour | The cloth's colour. **Detect from edges** samples the left, right and top edges with nobody in front; **Pick on picture** samples where you click; **Green**/**Blue** are presets. |
| Tolerance | How different from the key colour a pixel may be and still be removed. Raise it until the cloth disappears everywhere, including shadows. |
| Softness | Width of the transition at edges; higher gives softer hair edges, too high makes people translucent. |
| Spill removal | Removes the green glow the cloth throws onto hair and shoulders. |
| Show matte | Black and white view of the result: aim for white people on a black cloth with no grey speckles. |
| Placement | Size and position of the camera picture on the background (bottom centre anchored). |
| Trim | Cuts away the edges of the camera picture where the cloth ends. |

**Save** keeps the calibration in the running booth; in Studio, **Save booth settings into this
exhibit** stores it in the project (then save the project).

Tips: fix the camera's exposure and white balance if its software allows; keep people one or two
metres in front of the cloth; avoid green clothing; avoid creases and shadows on the cloth.

## Backgrounds and formats

- Videos: **WebM** (VP9 or VP8) or **MP4** (H.264). They loop silently.
- Pictures: **PNG**, **JPEG** or **WebP**.
- 16:9 at 1920 × 1080 fills the booth exactly; other shapes are cropped or letterboxed.
- Browsers cannot play Ogg Theora (.ogv), the format the Player uses. Convert with FFmpeg:

```sh
ffmpeg -i input.mov -c:v libvpx-vp9 -b:v 0 -crf 32 -an background.webm      # WebM
ffmpeg -i input.mov -c:v libx264 -crf 20 -pix_fmt yuv420p -an background.mp4  # MP4
```

## Visitors' photos and videos

- After the countdown, a **photo** is a 1920 × 1080 JPEG of exactly what the screen shows,
  overlay included. A **video** is 1280 × 720, recorded as MP4 (H.264) where the browser can (Chrome
  and Edge), otherwise WebM (Firefox). Booth videos have no sound.
- The booth shows a QR code for about a minute. It opens a download page on the booth computer's
  local address with the picture or video and a **Save** button.
- Files are kept in the Studio data folder (`~/.local/share/OpenExhibitStudio/greenscreen/captures`
  on Linux, `%APPDATA%\OpenExhibitStudio\greenscreen\captures` on Windows) and deleted after the
  set time (30 minutes by default). **Delete visitor photos and videos now** removes them at once.
  Each file is reachable only through its random 72-bit code; there is no list of files.
- Put up a notice that the booth takes pictures, and follow your organisation's policy on
  photographing visitors, especially children.

## Controls on the booth

Touch or mouse: background buttons at the bottom left, **Take a photo** and **Record a video** at the
bottom right. Keyboard: **←/→** background, **Space**/**Enter** photo, **R** video, **Esc** close the
QR panel, **F** full screen, **Ctrl+Shift+S** setup. USB arcade buttons work through a keyboard
encoder that sends these keys. When nobody is in front of the cloth, the booth shows “Step in front
of the green screen” and changes background every few seconds if that is switched on.

## Running a booth without Studio

Export the exhibit (**Publish**) and start the booth service directly. `--kiosk` opens Chrome,
Chromium or Edge full screen (the default browser otherwise); allow the camera once, the browser
remembers it for the booth address. `--settings FILE` keeps calibration from the setup panel
across restarts.

```sh
# Linux AppImage
./OpenExhibit-Studio-0.3.0-x86_64.AppImage greenscreen /opt/exhibits/booth.oex --bind 192.168.1.20 --kiosk \
  --settings ~/booth-calibration.json
# Source folder
python3 tools/greenscreen.py --project /opt/exhibits/booth.oex --bind 192.168.1.20 --kiosk \
  --settings ~/booth-calibration.json
```

On Windows (installer):

```bat
"%LOCALAPPDATA%\Programs\OpenExhibit Studio\bin\python\python.exe" "%LOCALAPPDATA%\Programs\OpenExhibit Studio\tools\greenscreen.py" --project C:\Exhibits\booth.oex --bind 192.168.1.20 --kiosk --settings C:\Exhibits\booth-calibration.json
```

Ports: **8788** on the chosen network address serves only the download pages; **8789** on 127.0.0.1
serves the booth page and its service calls (with the token in the booth address). On Windows,
allow Python on private networks when the firewall asks; with ufw on Linux:
`sudo ufw allow 8788/tcp`.

## How it works

The keying runs in the browser on the booth computer, in WebGL: for each camera pixel, the distance
from the key colour in the CbCr colour plane (BT.709) is averaged over its 3 × 3 neighbourhood and
turned into transparency with a soft threshold (tolerance, softness). Spill removal limits the key
colour's strongest channel to the larger of the other two. The canvas draws the background, then
the keyed camera picture, then the overlay; photos and videos are taken from that same canvas.
The service (`tools/greenscreen.py`, Python standard library only) serves the page and media,
stores captures with their expiry, and serves the download pages (`tools/booth/`).

## Status and limits

- Tested in Chrome 153 with Chrome's simulated camera (a generated clip of a figure in front of
  green) and software WebGL: keyed colours, picture, video and overlay layers, photo and MP4 video
  capture, downloads, matte view, colour detection and saved calibration
  ([test results](TEST-RESULTS.md)).
- Not yet tested: a real webcam or capture card under real lighting, phones (Android, iPhone),
  Firefox and Edge, and Windows.
- One camera picture; no AI person segmentation or hair-detail matting — quality depends on the
  cloth and lighting.
- The booth is a browser window. It is not drawn through the Player's projection mapping, so it
  cannot be warped or edge-blended across projectors.
