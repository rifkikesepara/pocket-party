#include "PocketPartyBLE.hpp"

#include <gdextension_interface.h>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

static PocketPartyBLE *ble_singleton = nullptr;

void initialize_pocket_party_ble(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	ClassDB::register_class<PocketPartyBLE>();
	ble_singleton = memnew(PocketPartyBLE);
	Engine::get_singleton()->register_singleton("PocketPartyBLE", ble_singleton);
}

void uninitialize_pocket_party_ble(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	if (ble_singleton) {
		Engine::get_singleton()->unregister_singleton("PocketPartyBLE");
		memdelete(ble_singleton);
		ble_singleton = nullptr;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT pocket_party_ble_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_pocket_party_ble);
	init_obj.register_terminator(uninitialize_pocket_party_ble);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
