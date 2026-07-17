class_name SoundBank
extends RefCounted
## Procedurally synthesized sound effects (SPEC.md §M6). No audio asset files are
## bundled, so engine/skid/impact are generated as AudioStreamWAV buffers at
## startup. Engine and skid loop seamlessly (integer harmonics over the buffer).

const MIX_RATE := 22050


static func engine() -> AudioStreamWAV:
	var length := 735  # base period -> 30 Hz fundamental cell
	var samples := PackedFloat32Array()
	samples.resize(length)
	for i in range(length):
		var ph := TAU * float(i) / float(length)
		# Even harmonics for a low rumble, plus a touch of noise.
		var v := 0.5 * sin(ph * 2.0) + 0.3 * sin(ph * 4.0) + 0.18 * sin(ph * 6.0) + 0.10 * sin(ph * 8.0)
		v += (randf() * 2.0 - 1.0) * 0.05
		samples[i] = v * 0.5
	return _wav(samples, true)


static func skid() -> AudioStreamWAV:
	var length := 4410  # 0.2 s
	var samples := PackedFloat32Array()
	samples.resize(length)
	var prev := 0.0
	for i in range(length):
		var n := randf() * 2.0 - 1.0
		prev = lerpf(prev, n, 0.4)  # low-passed noise
		var screech := sin(TAU * float(i) * 120.0 / float(length))  # ~600 Hz tonal
		samples[i] = (prev * 0.6 + screech * 0.22) * 0.45
	return _wav(samples, true)


static func impact() -> AudioStreamWAV:
	var length := 3307  # ~0.15 s one-shot
	var samples := PackedFloat32Array()
	samples.resize(length)
	for i in range(length):
		var env := exp(-float(i) / float(length) * 6.0)
		samples[i] = (randf() * 2.0 - 1.0) * env * 0.7
	return _wav(samples, false)


static func warning() -> AudioStreamWAV:
	var length := 11025  # 0.5 s — a repeating beep
	var tone_len := 3307  # 0.15 s of tone, then silence
	var samples := PackedFloat32Array()
	samples.resize(length)
	for i in range(length):
		if i < tone_len:
			var env := sin(PI * float(i) / float(tone_len))  # fade to avoid clicks
			samples[i] = sin(TAU * 880.0 * float(i) / float(MIX_RATE)) * env * 0.5
		else:
			samples[i] = 0.0
	return _wav(samples, true)


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav
