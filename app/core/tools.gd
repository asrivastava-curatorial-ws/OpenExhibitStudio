extends RefCounted
## Finds the release folders and starts the optional Python services (live audience,
## hardware gateway, calibration wizard). Studio and the Player work without them.

const Paths := preload("res://core/paths.gd")


## The release root: the folder that holds examples/, tools/, gateway/ and firmware/.
static func root() -> String:
	var examples := Paths.examples()
	if examples:
		return examples.get_base_dir()
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path()


static func path(relative: String) -> String:
	return root().path_join(relative)


## [executable, leading arguments] for Python 3. The project's .venv wins because
## setup --hardware installs pyserial and paho-mqtt there.
static func python() -> Array:
	var preferred := OS.get_environment("OPENEXHIBIT_PYTHON")
	if preferred:
		return [preferred, []]
	var windows := OS.get_name() == "Windows"
	var venv := path(".venv/Scripts/python.exe" if windows else ".venv/bin/python")
	if FileAccess.file_exists(venv):
		return [venv, []]
	if windows:
		for embedded in ["bin/python/python.exe", "bin/windows/python/python.exe"]:
			if FileAccess.file_exists(path(embedded)):
				return [path(embedded), []]
		return ["py", ["-3"]]
	return ["python3", []]


## Starts `script` (relative to the release root) in the background.
## Returns the process ID, -1 when Python could not start, -2 when the script is missing.
static func spawn(script: String, args: Array) -> int:
	if not FileAccess.file_exists(path(script)):
		return -2
	var py := python()
	return OS.create_process(py[0], PackedStringArray(py[1] + [path(script)] + args))


## Runs `script` to completion and returns its exit code; `output` receives stdout.
static func run(script: String, args: Array, output: Array) -> int:
	var py := python()
	return OS.execute(py[0], PackedStringArray(py[1] + [path(script)] + args), output, true)


static func random_token() -> String:
	return Crypto.new().generate_random_bytes(24).hex_encode()


## Private IPv4 addresses of this computer, as [address, human label] pairs, loopback first.
static func lan_addresses() -> Array:
	var result := [["127.0.0.1", "This computer only — for rehearsal"]]
	for ip in IP.get_local_addresses():
		if not ip.is_valid_ip_address() or ":" in ip or ip == "127.0.0.1":
			continue
		var octets := ip.split(".")
		var second := int(octets[1]) if octets.size() == 4 else -1
		var private := (
			ip.begins_with("10.")
			or ip.begins_with("192.168.")
			or (octets[0] == "172" and second >= 16 and second <= 31)
		)
		if private:
			result.append([ip, "Local network — phones on this Wi-Fi/LAN can join (%s)" % ip])
	return result


## Kills a background service if it is still running.
static func stop(pid: int) -> void:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
