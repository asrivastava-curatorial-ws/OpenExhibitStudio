extends Node
signal status_changed(text)
var session
var tcp: StreamPeerTCP
var status = "Disconnected · physical outputs disarmed"
var buffer = ""
var elapsed = 0.0
var ready_link = false
var token = ""
var ports = {}
var armed = false
var requested = false
var active_port = 18440
var last_rx = 0


func attach(s):
	if session:
		if session.output_requested.is_connected(send_output):
			session.output_requested.disconnect(send_output)
		if session.disarm_requested.is_connected(disarm):
			session.disarm_requested.disconnect(disarm)
	disarm()
	session = s
	s.output_requested.connect(send_output)
	s.disarm_requested.connect(disarm)


func announce(msg: String):
	status = msg
	status_changed.emit(msg)
	if session:
		session.log_line(msg)


func connect_local(password: String, port = 18440):
	close()
	if password.length() < 16:
		announce("Gateway needs its local access token (at least 16 characters).")
		return
	token = password
	active_port = port
	tcp = StreamPeerTCP.new()
	requested = true
	last_rx = Time.get_ticks_msec()
	if tcp.connect_to_host("127.0.0.1", port) != OK:
		close()
		announce("Gateway connection failed.")
	else:
		announce("Connecting to the local gateway…")


func send(data: Dictionary):
	if tcp and tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		tcp.put_data((JSON.stringify(data) + "\n").to_utf8_buffer())


func disarm():
	armed = false
	if ready_link:
		send({"op": "disarm"})


func arm():
	if ready_link:
		send({"op": "arm"})


func send_output(channel, value):
	if ready_link and armed:
		send({"op": "out", "channel": channel, "value": value})


func close():
	disarm()
	if tcp:
		tcp.disconnect_from_host()
	tcp = null
	ready_link = false
	requested = false
	ports.clear()
	buffer = ""
	announce("Disconnected · physical outputs disarmed")


func _process(dt):
	if not tcp:
		return
	tcp.poll()
	var state = tcp.get_status()
	if state == StreamPeerTCP.STATUS_CONNECTED:
		if requested:
			send({"op": "hello", "v": 1, "token": token})
			requested = false
		var avail = tcp.get_available_bytes()
		if avail > 0:
			buffer += tcp.get_utf8_string(avail)
			if buffer.length() > 131072:
				close()
				return
		var split = buffer.find("\n")
		while split >= 0:
			var v = JSON.parse_string(buffer.left(split))
			buffer = buffer.substr(split + 1)
			if v is Dictionary:
				receive(v)
			split = buffer.find("\n")
		elapsed += dt
		if elapsed >= 0.35 and ready_link:
			send({"op": "heartbeat"})
			elapsed = 0
		if Time.get_ticks_msec() - last_rx > 3500:
			close()
			announce("Gateway heartbeat expired · disarmed")
	elif state in [StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE]:
		close()
		announce("Gateway unavailable · physical outputs disarmed")


func receive(v: Dictionary):
	last_rx = Time.get_ticks_msec()
	match v.get("op"):
		"hello":
			ready_link = true
			announce("Gateway online · physical outputs disarmed")
		"input":
			if session:
				session.sensor(str(v.get("channel", "")), v.get("value", 0))
		"state":
			ports = v.get("devices", {})
			armed = v.get("armed", false)
			var next = "Gateway online · " + ("ARMED" if armed else "disarmed") + " · " + JSON.stringify(ports)
			if next != status:
				announce(next)
		"error":
			announce("Gateway: " + str(v.get("message", "error")))
