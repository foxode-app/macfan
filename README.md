# MacFan

MacFan will be a menu bar app for controlling the fans of Apple silicon Macs. It is in early development; so far
the repository contains:

- **MacFan.app**, the menu bar app. It shows the CPU temperature in the menu bar — or, as chosen in Settings, the GPU
  temperature, fan speed, CPU usage and memory usage — and refreshes at an interval from 1 second to 5 minutes. Its
  fans are left to macOS by default; in Settings they can run at a constant speed or follow a temperature. The
  interface is in English and Japanese, switchable in Settings.
- **MacFanHelper**, a privileged helper (launchd daemon) inside the app that writes fan speeds as root.
- **MacFanKit**, a Swift package that reads and writes the System Management Controller (SMC), implements fan control
  and collects the readings the app displays.
- **`macfan`**, a command-line tool built on MacFanKit, used to check fan control on real hardware.

> [!WARNING]
> Fan control relies on undocumented SMC keys found through community reverse engineering and testing. Writing to
> the SMC requires root. Use at your own risk.

## Distribution

Download MacFan from [GitHub Releases](https://github.com/foxode-app/macfan/releases) as a Developer ID–signed disk
image notarized by Apple. The product page is [foxode.com/products/macfan](https://foxode.com/products/macfan/).
MacFan is not on the Mac App Store: changing fan speeds requires root privileges, which App Store apps may not request.

## Requirements

- macOS 14 or later on Apple silicon. Intel Macs are not supported yet.
- Xcode 16 or later. Development uses Xcode 27.1.

If `xcode-select -p` prints `/Library/Developer/CommandLineTools`, either switch to Xcode once with
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, or prefix the commands below with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Layout

| Path | Contents |
| --- | --- |
| `MacFan.xcodeproj`, `MacFan/` | Menu bar app (SwiftUI); strings in `MacFan/Localizable.xcstrings` (English, Japanese) |
| `MacFanHelper/` | Privileged helper: applies the fan settings it receives from the app over XPC |
| `LaunchDaemons/` | The helper's launchd property list, copied into `MacFan.app/Contents/Library/LaunchDaemons` |
| `MacFanKit/Sources/MacFanKit` | SMC access (`AppleSMC`), fan control (`FanController`), readings for the app (`SystemSampler`) |
| `MacFanKit/Sources/macfan` | Command-line tool |
| `MacFanKit/Tests/MacFanKitTests` | Unit tests (Swift Testing); fan control is tested against an in-memory fake SMC |

## Build, test and format

Open `MacFan.xcodeproj` in Xcode and run the MacFan scheme, or build from the command line:

```sh
xcodebuild -project MacFan.xcodeproj -scheme MacFan -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/MacFan.app
```

Both targets sign every configuration with the Developer ID certificate of team `UKKM3K9LF7`; Debug builds still get
the `get-task-allow` entitlement, so they can be debugged. The helper accepts connections only from
`com.foxode.MacFan` signed by its own team, so an ad hoc–signed build cannot control the fans. To build with your own
team, change `DEVELOPMENT_TEAM` in both targets.

Keep Debug and Release on the same kind of certificate. macOS records the helper's signing category (Development,
Developer ID, …) the first time the helper is registered, and from then on refuses to start a helper signed with
another kind: launchd reports `EX_CONFIG` and `launchctl print system/com.foxode.MacFan.FanHelper` shows the recorded
`validation-category`. Unregistering does not clear that record.

## Install and uninstall

```sh
xcodebuild -project MacFan.xcodeproj -scheme MacFan -configuration Release -derivedDataPath build build
ditto build/Build/Products/Release/MacFan.app /Applications/MacFan.app
```

Only one copy of the app should own the helper. Before running another copy, such as a Debug build, or before
deleting the app, unregister the helper and the login item from the copy that registered them:

```sh
/Applications/MacFan.app/Contents/MacOS/MacFan --unregister
```

The package has its own commands:

```sh
swift build --package-path MacFanKit
swift test --package-path MacFanKit
swift test --package-path MacFanKit --filter FanControllerTests   # a single suite
swift format lint --recursive MacFanKit                             # check formatting
swift format --in-place --recursive MacFanKit                       # apply formatting
```

## Fan control

Settings → Fan offers **Automatic (System)**, the default, and **Custom**:

- **Constant Speed** runs the fans at a percentage of their maximum speed.
- **Based on Temperature** leaves the fans to macOS until the temperature — by default the higher of the CPU and GPU
  temperatures — passes the start temperature.
  Above it, the speed rises linearly from the fan's minimum and reaches the maximum speed (a percentage of the fan's
  maximum) at the maximum temperature.

Choosing Custom registers the helper with `SMAppService`; macOS then asks for approval in System Settings → General →
Login Items & Extensions. The helper updates the fans every second. By default it changes the speed gradually, by
about 40 rpm per second, and when it takes over it starts from the fan's current speed (or macOS's target, if that is
higher), so the handover is not heard. "Change Speed Gradually" in Settings turns this off.

The helper hands the fans back to macOS when the app quits or crashes, when a write fails, when the temperature
cannot be read or passes 95 °C, and when the helper itself stops. Engaged fans return to macOS only after the
temperature falls 2 °C below the start temperature, so they do not flip back and forth.

For reference, on an M5 Pro Mac mini running macOS 27, macOS itself started raising the fan when the CPU average
reached about 80 °C. Under eight minutes of full CPU load it held about 84 °C with the fan at 3150 rpm, 64 % of the
4900 rpm maximum, and it raised and lowered the speed gradually over about a minute.

## Using `macfan`

```sh
swift build --package-path MacFanKit
cd MacFanKit

.build/debug/macfan fans                  # speed, range and mode of each fan
.build/debug/macfan temps                 # temperature sensors
.build/debug/macfan read F0Ac F0Tg F0md   # raw SMC keys
.build/debug/macfan keys F0               # every key starting with F0

sudo .build/debug/macfan test 0 3000 20   # hold fan 0 at 3000 rpm for 20 s, then restore automatic control
sudo .build/debug/macfan auto             # return all fans to automatic control
```

`test` restores automatic control when it finishes or is interrupted with Ctrl-C. If it is killed any other way, or
after `macfan set`, run `sudo macfan auto`.

## SMC keys

| Key | Meaning | Notes |
| --- | --- | --- |
| `Tp…`, `Te…` | CPU temperatures | the app shows their average; `Tp…` rose most under CPU load on an M5 Pro |
| `Tg…` | GPU temperatures | the app shows their average |
| `FNum` | number of fans | |
| `F<n>Ac`, `F<n>Mn`, `F<n>Mx` | actual, minimum and maximum speed (rpm) | `flt ` (little-endian float) on Apple silicon |
| `F<n>Tg` | target speed (rpm) | |
| `F<n>Md` | mode: 0 automatic, 1 manual | earlier Apple silicon |
| `F<n>md` | mode: 0 automatic, 1 manual | M5 Pro Mac mini on macOS 27, which has no `F<n>Md`; verified there |
| `Ftst` | releases the fans from macOS's thermal management on some chips | absent on the M5 Pro above |

## License

MacFan is released under the [MIT License](LICENSE).
