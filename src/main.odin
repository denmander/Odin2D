#+feature dynamic-literals
package game

import "core:c/libc"
import "core:path/slashpath"
import "core:path/filepath"
import "core:dynlib"
import "core:log"
import "core:mem"
import "core:fmt"
import "core:time"
import "core:os"

when ODIN_OS == .Windows {
	DLL_EXT :: ".dll"
} else when ODIN_OS == .Darwin {
	DLL_EXT :: ".dylib"
} else {
	DLL_EXT :: ".so"
}

GAME_DLL_DIR :: "build/"
GAME_DLL_PATH :: GAME_DLL_DIR + "game" + DLL_EXT

GameAPI :: struct{
	lib : dynlib.Library,
	init : App_Init_Proc,
	update : App_Update_Proc,
	quit : App_Quit_Proc,
	reload : App_Reload_Proc,
	modification_time : time.Time,
	version : int,
}
App_Init_Proc :: #type proc() -> rawptr
App_Update_Proc :: #type proc(app_memory: rawptr) -> (quit : bool, reload: bool)
App_Quit_Proc :: #type proc(app_memory: rawptr)
App_Reload_Proc :: #type proc(app_memory: rawptr)

copy_dll :: proc(to : string) -> bool {
	copy_err := os.copy_file(to, "game" + DLL_EXT)
	if copy_err != nil {
		fmt.printfln("Failed to copy " + "game" + DLL_EXT + " to {0}: %v", to, copy_err)
		return false
	}
	return true
}

LoadGameAPI :: proc(version: int) -> (api: GameAPI, ok: bool) {
	path := slashpath.join({fmt.tprintf("game%i.dll", version)}, context.temp_allocator)
	copy_dll(path) or_return
	load_library : bool
	api.lib, load_library = dynlib.load_library(path)
	fmt.println(path, "\n")
	if !load_library {
		fmt.eprintln(dynlib.last_error())
		return
	}
	fmt.println("DLL %q loaded successfully", path)
	api.init = auto_cast(dynlib.symbol_address(api.lib, "init"))
	if api.init == nil {
		fmt.eprint("symbol address('init') failed\n")
		return
	}
	api.update = auto_cast(dynlib.symbol_address(api.lib, "update"))
	if api.update == nil {
		fmt.eprint("symbol address('update') failed\n")
		return
	}
	api.quit = auto_cast(dynlib.symbol_address(api.lib, "quit"))
	if api.quit == nil {
		fmt.eprint("symbol address('quit') failed\n")
		return
	}
	api.reload = auto_cast(dynlib.symbol_address(api.lib, "reload"))
	if api.reload == nil {
		fmt.eprint("symbol address('reload') failed\n")
		return
	}
	
	api.version = version
	api.modification_time = time.now()
	return api, true
}

UnloadGameAPI :: proc(api: ^GameAPI) {
	if api.lib != nil {
		dynlib.unload_library(api.lib)
	}
}

ShouldReload :: proc(api: ^GameAPI) -> bool {
	path := slashpath.join({fmt.tprintf("game%i.dll", api.version + 1)}, context.temp_allocator)
	return os.exists(path)
}

main :: proc() {
	// set working directory to dir of executable
	exe_path := os.args[0]
	exe_dir := filepath.dir(string(exe_path))
	os.set_working_directory(exe_dir)
	fmt.println(exe_dir, "\n")
	context.logger = log.create_console_logger()

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

	game_api_version := 0
	game_api, game_api_ok := LoadGameAPI(game_api_version)
	assert(game_api_ok == true, "game api couldn't be loaded.")

	game_memory := game_api.init()
	quit := false
	reload := false
	for quit == false {
		quit, reload = game_api.update(game_memory)
		if ShouldReload(&game_api){
			reload = true
		}
		if reload {
			new_game_api, new_game_api_ok := LoadGameAPI(game_api.version + 1)
			if new_game_api_ok {
				game_api = new_game_api
				game_api.reload(game_memory)
			}
		}
		if len(tracking_allocator.bad_free_array) > 0 {
			for b in tracking_allocator.bad_free_array {
				log.errorf("Bad free at: %v", b.location)
			}
			libc.getchar()
			panic("Bad free detected")
		}
		free_all(context.temp_allocator)
	}
	free_all(context.temp_allocator)
	if reset_tracking_allocator(&tracking_allocator) {
		// Prevents the game from closing without showing memory leaks
		libc.getchar()
	}
	UnloadGameAPI(&game_api)
	game_api.quit(game_memory)
	log.warn("Quitting...")
	mem.tracking_allocator_destroy(&tracking_allocator)
}