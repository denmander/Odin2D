package game

import "core:path/slashpath"
import "core:dynlib"
import "core:log"
import "core:fmt"
import "core:time"
import "core:os"

GameAPI :: struct{
	lib : dynlib.Library,
	init : App_Init_Proc,
	init_window : App_Init_Window,
	update : App_Update_Proc,
	quit : App_Quit_Proc,
	shutdown_window : App_Shutdown_Window,
	reload : App_Reload_Proc,
	modification_time : time.Time,
	version : i32,
}
App_Init_Proc :: proc() -> rawptr
App_Init_Window :: proc()
App_Update_Proc :: proc() -> bool
App_Quit_Proc :: proc(app_memory: rawptr)
App_Shutdown_Window :: proc()
App_Reload_Proc :: proc(app_memory: rawptr)

copy_dll :: proc(to : string) -> bool {
	copy_err := os.copy_file(to, "game.dll")
	if copy_err != nil {
		fmt.printfln("Failed to copy " + "game.dll to {0}: %v", to, copy_err)
		return false
	}
	return true
}

LoadGameAPI :: proc(version: i32) -> (api: GameAPI, ok: bool) {
	mod_time, mod_time_err := os.last_write_time_by_name("game.dll")
	if mod_time_err != os.ERROR_NONE {
		fmt.printfln("Failed getting last write time of game.dll, error code: {1}", mod_time_err,)
		return
	}
	path := slashpath.join({fmt.tprintf("game%i.dll", version)}, context.temp_allocator)
	load_library : bool
	copy_dll(path) or_return
	api.lib, load_library = dynlib.load_library(path)
	if !load_library {
		fmt.eprintln(dynlib.last_error())
		return
	}
	//fmt.println("DLL %q loaded successfully", path)
	_, ok = dynlib.initialize_symbols(&api, path, "game_", "lib")
	if !ok {
		fmt.printfln("Failed initializing symbols: {0}", dynlib.last_error())
	}
	/*
	api.init = auto_cast(dynlib.symbol_address(api.lib, "game_init"))
	if api.init == nil {
		fmt.eprint("symbol address('init') failed\n")
		return
	}
	api.init_window = auto_cast(dynlib.symbol_address(api.lib, "game_init_window"))
	if api.init_window == nil {
		fmt.eprint("symbol address('init_window') failed\n")
		return
	}
	api.update = auto_cast(dynlib.symbol_address(api.lib, "game_update"))
	if api.update == nil {
		fmt.eprint("symbol address('update') failed\n")
		return
	}
	api.quit = auto_cast(dynlib.symbol_address(api.lib, "game_quit"))
	if api.quit == nil {
		fmt.eprint("symbol address('quit') failed\n")
		return
	}
	api.shutdown_window = auto_cast(dynlib.symbol_address(api.lib, "game_shutdown_window"))
	if api.shutdown_window == nil {
		fmt.eprint("symbol address('shutdown_window') failed\n")
		return
	}
	api.reload = auto_cast(dynlib.symbol_address(api.lib, "game_reload"))
	if api.reload == nil {
		fmt.eprint("symbol address('reload') failed\n")
		return
	}
	*/
	api.version = version
	api.modification_time = mod_time
	return api, true
}

UnloadGameAPI :: proc(api: ^GameAPI) {
	if api.lib != nil {
		dynlib.unload_library(api.lib)
	}
}

ShouldReload :: proc(api: ^GameAPI) -> bool {
	game_dll_mod, game_dll_mod_err := os.last_write_time_by_name("game.dll")
	if game_dll_mod_err == os.ERROR_NONE && api.modification_time != game_dll_mod {
		return true
	}
	return false
	//path := slashpath.join({fmt.tprintf("game%i.dll", api.version + 1)}, context.temp_allocator)
	//return os.exists(path)
}

main :: proc() {
	/*context.logger = log.create_console_logger()

	default_alocator := context.allocator
	tracking_allocator :mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, context.allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)

	reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> bool{
		err := false
		for _, value in a.allocation_map {
			log.errorf("%v leaked %v bytes\n", value.location, value.size)
			err = true
		}
		mem.tracking_allocator_clear(a)
		return err
	}
	*/
	game_api_version : i32 = 0
	game_api, game_api_ok := LoadGameAPI(0)
	assert(game_api_ok == true, "game api couldn't be loaded.")
	//game_api.modification_time, _ = os.last_write_time_by_name("game.dll")
	game_api.init_window()
	game_memory := game_api.init()
	quit := false
	reload := false
	for quit == false {
		quit = game_api.update()
		if ShouldReload(&game_api){
			reload = true
		}
		if reload {
			new_game_api, new_game_api_ok := LoadGameAPI(game_api.version + 1)
			if new_game_api_ok {
				fmt.printf("Game Reloaded")
				game_api = new_game_api
				game_api.reload(game_memory)
			}
		}
		/*if len(tracking_allocator.bad_free_array) > 0 {
			for b in tracking_allocator.bad_free_array {
				log.errorf("Bad free at: %v", b.location)
			}
			libc.getchar()
			panic("Bad free detected")
		}*/
		free_all(context.temp_allocator)
	}
	free_all(context.temp_allocator)
	/*if reset_tracking_allocator(&tracking_allocator) {
		// Prevents the game from closing without showing memory leaks
		libc.getchar()
	}*/
	game_api.quit(game_memory)
	game_api.shutdown_window()
	UnloadGameAPI(&game_api)
	log.warn("Quitting...")
	//mem.tracking_allocator_destroy(&tracking_allocator)
}