// Slice 034: GDExtension wrapper class exposing the native/wgnetstack Go
// bridge (Slice 032) to GDScript as a RefCounted class. This header declares
// no bridge logic of its own — start()/stop() call straight through to the
// C-exported wgnetstack_start/wgnetstack_stop symbols statically linked from
// build/libwgnetstack.a (see ../SConstruct). See
// docs/slices/034-wgnetstack-godot-gdextension-tunnel-integration-linux.md.
#ifndef WG_NETSTACK_H
#define WG_NETSTACK_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class WgNetstack : public RefCounted {
	GDCLASS(WgNetstack, RefCounted)

protected:
	static void _bind_methods();

public:
	WgNetstack();
	~WgNetstack();

	// Validates and forwards `config` to wgnetstack_start as JSON. Returns the
	// loopback port on success, or -1 on any failure (logged by the bridge).
	// Every field is untrusted external input; no default or fabricated
	// private-key path is ever substituted here.
	int start(const Dictionary &config);

	// Tears down the process-wide active bridge, if any. Safe to call when no
	// bridge is running.
	void stop();
};

} // namespace godot

#endif // WG_NETSTACK_H
