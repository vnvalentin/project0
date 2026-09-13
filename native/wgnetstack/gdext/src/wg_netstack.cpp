// Slice 034: see wg_netstack.h. start()/stop() are a thin, allocation-safe
// marshaling layer over the C ABI in ../../build/libwgnetstack.h
// (wgnetstack_start/wgnetstack_stop), statically linked from
// build/libwgnetstack.a. No bridge logic lives here.
#include "wg_netstack.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cstdlib>
#include <cstring>
#include <string>

// Declared in the Go-generated header produced by
// `make cgoarchive` (native/wgnetstack/build/libwgnetstack.h). Declared
// directly here (rather than #included) because that header emits its own
// cgo prologue typedefs that are unnecessary noise for this translation
// unit; the two exported symbols are all this file needs.
extern "C" {
int wgnetstack_start(char *configJSON);
void wgnetstack_stop();
}

using namespace godot;

namespace {

// Escapes `value` for embedding as a JSON string literal body (between the
// surrounding quotes). Config values here are operator-supplied endpoints
// and file paths, not attacker-controlled network input, but every value is
// still escaped defensively before being placed in the JSON payload the Go
// side parses.
std::string json_escape(const String &value) {
	std::string out;
	CharString utf8 = value.utf8();
	const char *data = utf8.get_data();
	for (const char *p = data; *p != '\0'; ++p) {
		unsigned char c = static_cast<unsigned char>(*p);
		switch (c) {
			case '"':
				out += "\\\"";
				break;
			case '\\':
				out += "\\\\";
				break;
			case '\n':
				out += "\\n";
				break;
			case '\r':
				out += "\\r";
				break;
			case '\t':
				out += "\\t";
				break;
			default:
				if (c < 0x20) {
					char buf[8];
					snprintf(buf, sizeof(buf), "\\u%04x", c);
					out += buf;
				} else {
					out += static_cast<char>(c);
				}
		}
	}
	return out;
}

// Builds the exact JSON shape native/wgnetstack/bridge.Config expects
// (client_private_key_path, client_address, mtu, server_public_key,
// server_endpoint, persistent_keepalive_interval, game_host). Every field
// comes from the caller-supplied Dictionary; unset numeric fields fall back
// to 0 so the Go-side ParseConfig applies its own documented defaults
// (mtu=1420, persistent_keepalive_interval=25) rather than this wrapper
// guessing a value.
std::string build_config_json(const Dictionary &config) {
	std::string json = "{";
	json += "\"client_private_key_path\":\"" + json_escape(String(config.get("client_private_key_path", ""))) + "\",";
	json += "\"client_address\":\"" + json_escape(String(config.get("client_address", ""))) + "\",";
	json += "\"mtu\":" + std::to_string(static_cast<int>(config.get("mtu", 0))) + ",";
	json += "\"server_public_key\":\"" + json_escape(String(config.get("server_public_key", ""))) + "\",";
	json += "\"server_endpoint\":\"" + json_escape(String(config.get("server_endpoint", ""))) + "\",";
	json += "\"persistent_keepalive_interval\":" + std::to_string(static_cast<int>(config.get("persistent_keepalive_interval", 0))) + ",";
	json += "\"game_host\":\"" + json_escape(String(config.get("game_host", ""))) + "\"";
	json += "}";
	return json;
}

} // namespace

void WgNetstack::_bind_methods() {
	ClassDB::bind_method(D_METHOD("start", "config"), &WgNetstack::start);
	ClassDB::bind_method(D_METHOD("stop"), &WgNetstack::stop);
}

WgNetstack::WgNetstack() {}

WgNetstack::~WgNetstack() {}

int WgNetstack::start(const Dictionary &config) {
	std::string json = build_config_json(config);

	// wgnetstack_start's C signature takes a mutable char*, even though the Go
	// side only reads it; copy into a heap buffer we own and free rather than
	// handing it a pointer into our std::string/CharString storage.
	char *buf = static_cast<char *>(std::malloc(json.size() + 1));
	if (buf == nullptr) {
		UtilityFunctions::push_error("WgNetstack.start: allocation failure building config JSON");
		return -1;
	}
	std::memcpy(buf, json.c_str(), json.size() + 1);

	int port = wgnetstack_start(buf);
	std::free(buf);

	if (port <= 0) {
		UtilityFunctions::push_error("WgNetstack.start: bridge failed to start (see native log)");
		return -1;
	}
	return port;
}

void WgNetstack::stop() {
	wgnetstack_stop();
}
