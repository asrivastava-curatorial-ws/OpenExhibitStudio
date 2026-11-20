# Deployment and operations

Export an exhibit under **Publish**. Open a single output with **player.sh --project exhibit.oex --output out_2 --fullscreen** on Linux, or pass the same arguments to **Player.cmd** on Windows. Omitting the output ID opens every configured feed on the local computer. Two windows may share a visitor session. Independent computers run separate visitor sessions.

## Offline updates and recovery

Run these commands on the playback computer with Python 3.10 or newer. Use absolute paths for unattended operation.

```sh
python3 tools/deploy.py verify exhibit.oex
python3 tools/deploy.py install /path/to/exhibit-releases exhibit.oex
bash player.sh --deployment /path/to/exhibit-releases --kiosk
python3 tools/deploy.py status /path/to/exhibit-releases
python3 tools/deploy.py rollback /path/to/exhibit-releases
```

Install verifies the archive before atomically replacing the activation pointer. Concurrent update operations use an OS file lock. An interrupted copy leaves the previous pointer usable. The player checks the selected archive hash and tries the previous archive if the active file is missing or damaged. Restart the Player after an update or rollback. Boot begins at the project’s starting scene and designated startup timeline. Physical outputs require a new operator arm.

Set **OPENEXHIBIT_OPERATOR_KEY** to a private password of at least 16 characters in the kiosk account’s environment. Press **F10** to unlock operator controls. Kiosk mode routes the normal full-screen and quit keys through operator access. **F12** always disarms the software outputs. Configure OS account restrictions separately for a public kiosk. Local operating-system administrators can access the files and terminate the process.

## Startup after login

On Ubuntu install the .deb, copy **packaging/openexhibit-player.service** to the kiosk user’s systemd user directory and edit its exhibit path for the installed site. Enable it with **systemctl --user enable --now openexhibit-player.service** from the graphical desktop. Its restart policy recovers an unexpected process failure. On desktops without graphical-session.target, use the desktop’s Startup Applications entry with the same command. The display server and active desktop session must already exist.

With the AppImage, add an autostart entry for the kiosk account (paths are examples):

```sh
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/openexhibit-player.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=OpenExhibit Player
Exec=/opt/exhibits/OpenExhibit-Studio-0.3.0-x86_64.AppImage player /opt/exhibits/exhibit.oex --kiosk
EOF
```

On Windows, the installer's *OpenExhibit Player* Start-menu shortcut shows the full command (`bin\godot.exe --main-pack bin\player.pck -- --examples …`); append `--project <package> --kiosk`. Add it to the kiosk account’s Task Scheduler at logon with **Restart on failure** enabled. Working directory, examples path, package path and environment must point to the local installation. Use the headless gateway as a separate background process if required.

## Synchronized shows over a private LAN

The optional clock server publishes a named timeline. Followers measure request/response round-trip time and estimate playhead drift. Nonces bind replies to current requests, and both directions use HMAC-SHA-256. The protocol carries show identifiers and timing in cleartext over the site LAN. Distribute a random clock key of at least 32 characters privately in **OES_CLOCK_KEY**. Visitors cannot select a server through project data.

```sh
python3 tools/show_clock.py --bind 192.168.1.10 --timeline sequence --duration 12 --repeat --console
bash player.sh --project examples/13-shows/project.oes.json --clock-host 192.168.1.10 --output out_1 --fullscreen
```

The console accepts **pause**, **resume** and **restart**. Use the same exhibit on all followers. The default UDP port is 18442. Followers poll four times per second, reject stale replies and stop cue advancement after a 2.5-second loss. The operator panel shows the most recent RTT and estimated playhead error. A correction samples the show’s presentation state and disarms outputs. Remote-clock followers cannot arm physical outputs through the operator panel. Media decoders remain locally timed. Cue synchronization is software-based and does not implement video genlock, frame-lock or sample-accurate multichannel audio.

The gateway binds its TCP control socket to loopback only. Its token is separate from the clock key and the operator password. SQLite recording of sensor samples starts only with **--record**. The default system sends no telemetry and stores no visitor images. The drawing-wall example keeps submissions in memory until reset. Host and site backups must include the authoring project, deployment copies, calibration profile and local gateway configuration.


## Operator password

The Player's operator panel (F10) arms hardware outputs, resets the visit and closes the Player.
The first time it is opened on a computer it asks for a new password (8+ characters), stored as a
salted, iterated SHA-256 hash in the Player's user-data folder
(`~/.local/share/OpenExhibitStudio/operator.json` on Linux,
`%APPDATA%\OpenExhibitStudio\operator.json` on Windows). Delete that file to reset it. A site can
instead set `OPENEXHIBIT_OPERATOR_KEY` (16+ characters) in the service environment.

## Green-screen booths

A booth runs without Studio from an exported package: `python3 tools/greenscreen.py --project booth.oex --bind 192.168.1.20 --kiosk --settings booth-calibration.json` (AppImage: `… greenscreen booth.oex …`). See [GREEN-SCREEN.md](GREEN-SCREEN.md#running-a-booth-without-studio) for Windows, ports and the one-time camera permission.

## Live audience sessions on a show computer

Sessions need Python 3.10+ (installed by setup on Linux; `Setup-Windows.cmd` offers winget on
Windows). See [LIVE-AUDIENCE.md](LIVE-AUDIENCE.md) for ports, firewall and resuming after a
power cut.
