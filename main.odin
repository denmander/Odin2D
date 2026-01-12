#+feature dynamic-literals
package game

import "core:math"
import "core:mem"
import "core:fmt"
import "core:os"
import "core:encoding/json"
import rl "vendor:raylib"

Direction :: enum {
	SIDE,
	DOWN,
	UP
}
Player :: struct {
	position : rl.Vector2,
	old_position : rl.Vector2,
	velocity : rl.Vector2,
	size : rl.Vector2,
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

update_animation :: proc(a: ^Animation) {
	a.frame_timer += rl.GetFrameTime()
	for a.frame_timer > a.frame_length {
		a.current_frame += 1
		a.frame_timer -= a.frame_length
		if a.current_frame == a.frame_count {
			a.current_frame = 0
		}
	}
}

draw_animation :: proc(a: Animation, pos: rl.Vector2, dir_index: int, flip:bool){
	a_width := f32(a.texture.width)
	a_height := f32(a.texture.height)
	
	source := rl.Rectangle {
		x = f32(a.current_frame) * a_width / f32(a.frame_count),
		y = f32(dir_index) * a_height / f32(a.rows),
		width = a_width / f32(a.frame_count),
		height = a_height / f32(a.rows)
	}
	if flip do source.width = -source.width
	dest := rl.Rectangle {
		x = pos.x,
		y = pos.y,
		width = a_width / f32(a.frame_count),
		height = a_height / f32(a.rows)
	}
	rl.DrawTexturePro(a.texture,source,dest, {dest.width/2,dest.height},0,rl.WHITE)
}

PixelWindowHeight :: 180

Level :: struct {
	walls: [dynamic]rl.Vector2,
}
TileMap :: struct{
	columns : i32,
	rows : i32,
	tile_size : i32,
}

wall_collider :: proc(pos: rl.Vector2) -> rl.Rectangle {
	return {
		pos.x, pos.y,
		96,16,
	}
}


main :: proc() {
	track :mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	defer {
		for _, entry in track.allocation_map {
			fmt.eprintf("%v leaked %v bytes\n", entry.location, entry.size)
		}
		for entry in track.bad_free_array {
			fmt.eprintf("%v bad free\n", entry.location)
		}
		mem.tracking_allocator_destroy(&track)
	}

	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(1280,720,"Game")
	rl.SetWindowPosition(50,50)
	rl.SetWindowState({.WINDOW_RESIZABLE})
	rl.SetTargetFPS(60)

	rows : i32 = 9
	columns : i32 = 16
	tile_size : i32 = 16
	tile_map : [9][16]int = {
		{1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
		{1, 1, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1},
		{0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1},
		{1, 0, 1, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1},
		{1, 0, 0, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 1, 1, 1},
		{1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1},
		{1, 1, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 1, 1},
	}

	grassSprite : rl.Texture2D = rl.LoadTexture("assets\\tilesets\\spring.png")
	dirtSprite : rl.Texture2D = rl.LoadTexture("assets\\tilesets\\dirt.png")
	waterSprite : rl.Texture2D = rl.LoadTexture("assets\\tilesets\\water - spring.png")

	DT :: 1.0/60.0
	accumulated_time : f32
	P : Player = {
		size = {50,50},
		speed = 100}
		player_collider := rl.Rectangle{
			P.position.x,
			P.position.y,
		10,
		14,
	}
	player_walk := Animation {
		texture = rl.LoadTexture("assets\\character\\walk.png"),
		frame_count = 8,
		rows = 3,
		frame_length = 0.1,
		name = .walk
	}
	player_idle := Animation{
		texture = rl.LoadTexture("assets\\character\\idle.png"),
		frame_count = 4,
		rows = 3,
		frame_length = 0.2,
		name = .idle
	}

	current_anim := player_idle
	level : Level
	if level_data, ok := os.read_entire_file("level.json", context.temp_allocator);ok {
		if json.unmarshal(level_data, &level) != nil {
			append(&level.walls, rl.Vector2{-16,16})
		}
	} else {
		append(&level.walls, rl.Vector2{-16,16})
	}
		
	editing := false
	for !rl.WindowShouldClose() {
		accumulated_time += rl.GetFrameTime() //Fixed timestep
		for accumulated_time >= DT {
			dir : rl.Vector2
			P.old_position = P.position
			if rl.IsKeyDown(.UP) || rl.IsKeyDown(.W) {
				dir += {0,-1}
				P.dir = .UP
			}
			if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S) {
				dir += {0,1}
				P.dir = .DOWN
			}
			if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) {
				dir += {-1,0}
				P.flip = true
				P.dir = .SIDE
			}
			if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) {
				dir += {1,0}
				P.flip = false
				P.dir = .SIDE
			}
			if dir != {0,0} {
				P.velocity = math.lerp(P.velocity, dir * P.speed, f32(0.8))
				if current_anim.name != .walk {current_anim = player_walk}
			} else {
				P.velocity = math.lerp(P.velocity, rl.Vector2{0,0}, f32(0.8))
				if current_anim.name != .idle {current_anim = player_idle}
			}
			player_collider.x = P.position.x + P.velocity.x * DT - player_collider.width/2
			player_collider.y = P.position.y + P.velocity.y * DT - player_collider.height
			
			for wall in level.walls {
				wall_col := wall_collider(wall)
				if rl.CheckCollisionRecs(player_collider,wall_col) {
					if P.position.x + player_collider.width/2 < wall_col.x && P.velocity.x > 0 {P.velocity.x = 0}
					if P.position.x - player_collider.width/2 > wall_col.x + wall_col.width && P.velocity.x < 0 {P.velocity.x = 0}
					if P.position.y < wall_col.y && P.velocity.y > 0 {P.velocity.y = 0}
					if P.position.y - player_collider.height > wall_col.y + wall_col.height && P.velocity.y < 0 {P.velocity.y = 0}
				}
			}
			P.position += P.velocity * DT
			accumulated_time -= DT
		}
		blend := accumulated_time / DT
		player_render_pos := math.lerp(P.old_position, P.position, blend)
		
		rl.BeginDrawing()
		rl.ClearBackground({110, 184, 168, 255})
		
		update_animation(&current_anim)

		screen_height := f32(rl.GetScreenHeight())
		camera := rl.Camera2D {
			zoom = screen_height/PixelWindowHeight,
			offset = {f32(rl.GetScreenWidth()/2),screen_height/2},
			target = P.position,
		}
		
		rl.BeginMode2D(camera)
		for y : i32 =0; y<rows; y += 1 {
			for x : i32 =0; x<columns; x += 1 {
				if tile_map[y][x] == 1 {
					rl.DrawRectangle(x*tile_size,y*tile_size,tile_size,tile_size,{150, 200, 200, 255})
				}
				else {rl.DrawRectangle(x*tile_size,y*tile_size,tile_size,tile_size,rl.LIME)}
			}
		}
		for wall in level.walls {	rl.DrawRectangleRec(wall_collider(wall),rl.RED)}
		draw_animation(current_anim, player_render_pos, int(P.dir), P.flip)
		//rl.DrawCircleV(rl.GetMousePosition(),1,rl.RED)
		//rl.DrawRectangleRec(player_collider,{0,50,150,100}) //Debug Player Collider

		if rl.IsKeyPressed(.F2) {
			editing = !editing
		}
		if editing {
			mp := rl.GetScreenToWorld2D(rl.GetMousePosition(),camera)
			rl.DrawRectangleV(mp, {16,16}, rl.RED)
			if rl.IsMouseButtonPressed(.LEFT){
				append(&level.walls, mp)
			}
			if rl.IsMouseButtonPressed(.RIGHT){
				for w, idx in level.walls {
					if rl.CheckCollisionPointRec(mp, wall_collider(w)) {
						unordered_remove(&level.walls, idx)
						break
					}
				}
			}
		}

		rl.EndMode2D()
		rl.EndDrawing()
		free_all(context.temp_allocator)
	}

	rl.CloseWindow()
	if level_data, err := json.marshal(level, allocator = context.temp_allocator); err == nil{
		os.write_entire_file("level.json", level_data)
	}

	free_all(context.temp_allocator)
	delete(level.walls)
}