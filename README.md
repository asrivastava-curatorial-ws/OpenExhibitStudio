# OpenExhibit Studio 0.2.0

OpenExhibit Studio authors and plays offline museum installations. This release adds a local audience quiz system, camera-assisted projector calibration and more field-device protocols. Fourteen editable exhibits ship with Studio and the standalone Player.

## Start on your computer

| Distribution | Authoring and playback |
| --- | --- |
| Windows x64 Setup.exe | Run the per-user installer, then choose **OpenExhibit Studio → Studio** in Start. The engine, quiz interpreter, fonts and examples are included. The installer is unsigned. |
| Windows portable | Extract the complete folder. Open **Studio.cmd** or **Player.cmd**. Drop a packaged exhibit on Player.cmd. |
| Ubuntu x86-64 .deb | Install with `sudo apt install ./OpenExhibit-Studio-0.2.0-linux-amd64.deb`. Launch `openexhibit-studio` or `openexhibit-player`. A fully offline installation needs the ordinary distribution dependencies already installed or cached. |
| Complete ZIP on Ubuntu | Extract, enter **OpenExhibitStudio** and run `bash studio.sh`. To run the example scoreboard, use `bash player.sh examples/14-live-quiz/project.oes.json`. |
| Compact source ZIP | Includes both platform packs, sources, examples and verification material. Install Godot 4.6.3 or set OPENEXHIBIT_GODOT and use the launchers. Run Windows setup with your existing Godot executable. Python 3.10 or newer is needed for the quiz service. |

**For a contest**, choose **View → Live quiz contest**, select the classroom or venue network interface and press **Start new contest**. Open **Edit contest** before beginning, or run the included ten-round science quiz. Participants scan the local QR. The host controls answers, timing and results. A scoreboard component can appear on any calibrated exhibit surface. [Contest guide](docs/LIVE-QUIZ.md)

**For projection**, open **Mapping**, select the output, and choose **Camera calibration wizard**. The solver checks independent optical landmarks before exporting a measured warp. The real-projector commissioning procedure records error in physical millimetres. [Calibration guide](docs/CALIBRATION.md)

Start with **Orbital atlas**. Press **Test exhibit**, choose **Mars**, and watch the planet name and orbital period change. Press **F5** to return to editing. Choose **File → Save as** and create a project directory before making your own exhibit.

## Player-only installation

On Linux, copy **player.sh**, **bin/godot**, **bin/player.pck** and **licenses/** into the same relative folder structure. Include **examples/** if the operator needs the sample library. Supply a project path or use the player’s Open exhibit button. On Windows, run `Setup-Windows.cmd -PlayerOnly` from the full ZIP to install the included player and engine. The player pack contains the content renderer, event engine and output manager. It has no Studio scripts.

The bundled Linux executable is the upstream Godot engine distribution, which also contains Godot’s development tools. The launchers run an independent compiled OpenExhibit pack. The native export command in the build guide produces smaller template-based executables.

## Find your starting point

| I want to… | Read |
| --- | --- |
| Design an exhibit without programming | [User manual](docs/USER-MANUAL.md) |
| Set up a panorama, sphere, cylinder or book | [Installation and mapping](docs/MAPPING.md) |
| Connect an Arduino, ESP32, webcam or existing program | [Hardware guide](docs/HARDWARE.md) and [wiring drawings](docs/wiring.svg) |
| Install updates, start automatically or synchronize players | [Deployment](docs/DEPLOYMENT.md) |
| Find out exactly what works | [Capability matrix](docs/CAPABILITIES.md) and [actual test results](docs/TEST-RESULTS.md) |
| Modify or rebuild the programs | [Architecture and plan](docs/ARCHITECTURE.md), [build and reproducibility](docs/BUILD.md) |
| Extend an exhibit | [Plugin interfaces](docs/PLUGINS.md), [device protocol](docs/PROTOCOL.md), [project format](docs/FORMAT.md), [JSON Schema](docs/project.schema.json) |
| Redistribute the software or assets | [Dependency and licence inventory](docs/DEPENDENCIES.md) |

## Repository layout

| Directory | Contents |
| --- | --- |
| app/core | Version checks, atomic recovery, event engine, component rendering, mappings, authenticated clock and gateway client |
| app/studio | Authoring shell, editable canvas, inspector, pin planner, calibration pad and workspaces |
| app/player | Standalone entry point, output windows and operator controls |
| app/qa, tests | Native integration checks, gateway tests, C++ protocol fixture and measured reports |
| gateway | Headless hardware service, transport adapters and installation-specific example profiles |
| firmware | Uno/Nano/Mega sketch, ESP32 sketch, shared watchdog protocol and optional Blockly editor |
| examples | Fourteen independent project folders, each with its local assets and setup notes |
| tools | Pack builds, media preparation, PDF book import, camera adapter, show clock, offline updates and soak monitor |
| packaging, bin | Install scripts, compiled Studio/player packs and the bundled Linux and Windows engines in the complete release |
| docs, licenses | Operator and developer guides, licences and attribution |

Source and original example content carry the MIT licence. Redistributed engines, fonts and geographic data have the terms listed in the dependency inventory.
