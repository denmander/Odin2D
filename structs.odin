package game

import rl "vendor:raylib"



World :: struct{
	tilemap : ^TileMap
}
Direction :: enum {
	SIDE,
	DOWN,
	UP
}
GameState :: struct {
	world_arena : MemoryArena,
	world: ^World,
	PlayerP : TileMapPosition
}
GameMemory :: struct{
	is_initialized : bool,
	PermanentStorageSize : u64,
	PermanentStorage : rawptr,
	TransientStorageSize : u64,
	TransientStorage : rawptr
}

MemoryArena :: struct {
	Size : uint,
	Base : ^u8,
	Used : uint
}

Player :: struct {
	old_pos : rl.Vector2,
	velocity : rl.Vector2,
	speed : f32,
	dir : Direction,
	flip: bool
}

Animation_Name :: enum {
	walk,
	run,
	idle,
	jump,
}

Animation :: struct {
	texture : rl.Texture2D,
	frame_count : int,
	rows : int,
	frame_timer : f32,
	current_frame : int,
	frame_length : f32,
	name : Animation_Name
}
