extends Node
const Model = preload("res://core/project.gd")
var udp = PacketPeerUDP.new()
var key = ""
var session
var nonce = ""
var sent_at = 0
var last_ok = 0
var epoch = ""
var active = false
var stopped = false
var rtt_ms = 0.0
var drift_ms = 0.0


func start(s, host: String, port: int, secret: String):
	session = s
	key = secret
	if key.length() < 32 or udp.connect_to_host(host, port) != OK:
		s.log_line("LAN clock unavailable. Check the clock address and shared key.")
		s.playing = false
		return
	s.disarm()
	s.playing = false
	active = true
	last_ok = Time.get_ticks_msec()


func sign_msg(body: String) -> String:
	return (
		Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key.to_utf8_buffer(), body.to_utf8_buffer()).hex_encode()
	)


func _process(_dt):
	if not active:
		return
	var now = Time.get_ticks_msec()
	while udp.get_available_packet_count() > 0:
		var packet = udp.get_packet()
		if packet.size() > 512:
			continue
		var fields = packet.get_string_from_ascii().split("|")
		if fields.size() != 9 or fields[0] != "OEC1" or fields[1] != "S" or fields[2] != nonce or nonce == "":
			continue
		var body = "|".join(fields.slice(0, 8))
		if not Crypto.new().constant_time_compare(sign_msg(body).to_utf8_buffer(), fields[8].to_utf8_buffer()):
			continue
		rtt_ms = now - sent_at
		nonce = ""
		if rtt_ms > 350:
			continue
		var t = Model.lookup(session.project.timelines, fields[4])
		if t.is_empty():
			continue
		var playing = fields[7] == "1"
		var at = clampf(float(fields[5]) / 1000.0 + (rtt_ms / 2000.0 if playing else 0.0), 0, t.duration)
		drift_ms = (at - session.head) * 1000
		var run_id = fields[3] + "/" + fields[6]
		if epoch != run_id or session.timeline != t.id or absf(drift_ms) > 100 or stopped:
			session.timeline = t.id
			session.seek(at)
			session.log_line("LAN clock · RTT %.1f ms · drift %.1f ms" % [rtt_ms, drift_ms])
		epoch = run_id
		session.playing = playing
		stopped = false
		last_ok = now
	if now - sent_at >= 250:
		nonce = Crypto.new().generate_random_bytes(12).hex_encode()
		var body = "OEC1|P|" + nonce
		udp.put_packet((body + "|" + sign_msg(body)).to_utf8_buffer())
		sent_at = now
	if now - last_ok > 2500 and not stopped:
		stopped = true
		session.playing = false
		session.disarm()
		session.log_line("LAN clock lost · show cues paused, outputs disarmed.")
