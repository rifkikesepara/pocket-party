#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class PocketPartyBLE : public Object {
	GDCLASS(PocketPartyBLE, Object)

private:
	static PocketPartyBLE *singleton;
	void *ble_delegate = nullptr;

protected:
	static void _bind_methods();

public:
	static PocketPartyBLE *get_singleton();

	PocketPartyBLE();
	~PocketPartyBLE();

	void start_ble();
	void stop_ble();
	void send_ble_packet(const PackedByteArray &p_packet);

	void _emit_packet_deferred(const PackedByteArray &p_packet);
	void _emit_peer_deferred(int64_t p_id, const String &p_name, int64_t p_rssi);
};

} // namespace godot
