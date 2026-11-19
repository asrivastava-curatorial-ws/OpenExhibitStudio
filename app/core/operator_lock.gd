extends RefCounted
## Password for the Player's operator panel (F10).
##
## A site can supply OPENEXHIBIT_OPERATOR_KEY (16+ characters) through its service manager.
## Otherwise the first person to open the panel on that computer sets a password, stored only as
## a salted, iterated SHA-256 hash in the Player's user data folder.

const FILE := "user://operator.json"
const ITERATIONS := 60000
const MIN_LENGTH := 8


static func from_environment() -> String:
	var key := OS.get_environment("OPENEXHIBIT_OPERATOR_KEY")
	return key if key.length() >= 16 else ""


static func configured() -> bool:
	return from_environment() != "" or _stored() is Dictionary


static func verify(password: String) -> bool:
	var key := from_environment()
	if key:
		return Crypto.new().constant_time_compare(key.to_utf8_buffer(), password.to_utf8_buffer())
	var stored = _stored()
	if not stored is Dictionary:
		return false
	var expected := Marshalls.base64_to_raw(str(stored.get("hash", "")))
	var actual := _derive(
		password, Marshalls.base64_to_raw(str(stored.get("salt", ""))), int(stored.get("iterations", ITERATIONS))
	)
	return expected.size() == 32 and Crypto.new().constant_time_compare(expected, actual)


## Stores a new password; returns an error message or "".
static func set_password(password: String) -> String:
	if password.length() < MIN_LENGTH:
		return "Use at least %d characters." % MIN_LENGTH
	var salt := Crypto.new().generate_random_bytes(16)
	var record := {
		"salt": Marshalls.raw_to_base64(salt),
		"iterations": ITERATIONS,
		"hash": Marshalls.raw_to_base64(_derive(password, salt, ITERATIONS))
	}
	var file := FileAccess.open(FILE, FileAccess.WRITE)
	if file == null:
		return "Could not save the password."
	file.store_string(JSON.stringify(record))
	return ""


static func _stored():
	if not FileAccess.file_exists(FILE):
		return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	return data if data is Dictionary and data.has("hash") and data.has("salt") else null


static func _derive(password: String, salt: PackedByteArray, rounds: int) -> PackedByteArray:
	var digest := salt + password.to_utf8_buffer()
	for i in rounds:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(digest)
		ctx.update(salt)
		digest = ctx.finish()
	return digest
