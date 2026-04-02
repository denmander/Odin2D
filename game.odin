package game

import "core:mem"
import rl "vendor:raylib"
Memory : ^GameMemory

@(export)
game_init :: proc() {
    Memory = new(GameMemory)
	Memory.PermanentStorageSize = 64*mem.Megabyte
	Memory.TransientStorageSize = mem.Gigabyte
	assert(size_of(GameState) <= Memory.PermanentStorageSize)
	AllocatedMemory, _ := mem.alloc(int(Memory.PermanentStorageSize + Memory.TransientStorageSize))
	Memory.PermanentStorage = AllocatedMemory
	Memory.TransientStorage = mem.ptr_offset(cast(^u8)(Memory.PermanentStorage), Memory.PermanentStorageSize)
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(1280,720,"Game")
	rl.SetWindowPosition(10,10)
	rl.SetWindowState({.WINDOW_RESIZABLE})
	rl.SetTargetFPS(60)
}

@(export)
game_update :: proc() -> bool {

	free_all(context.temp_allocator)
	return true
}

@(export)
game_shutdown :: proc() {

}

@(export)
game_memory :: proc() -> rawptr {
	return Memory
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	Memory = (^GameMemory)(mem)
}