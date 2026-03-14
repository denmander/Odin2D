package game

import rl "vendor:raylib"



Direction :: enum {
	SIDE,
	DOWN,
	UP
}
Player :: struct {
	pos : TileMapPosition,
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

World :: struct{
	tile_map : ^TileMap
}