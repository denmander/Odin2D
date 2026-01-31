#+feature dynamic-literals
package game

import "core:math"
import "core:mem"
import "core:fmt"
import "core:os"
import "core:encoding/json"
import rl "vendor:raylib"

CanonicalPosition :: struct{
	TileMapX, TileMapY: int,
	TileX, TileY: int,
	X, Y: f32 "Tile relative X and Y"
}
Direction :: enum {
	SIDE,
	DOWN,
	UP
}
Player :: struct {
	pos : CanonicalPosition,
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
	rl.DrawTexturePro(a.texture, source, dest, {dest.width/2.0,dest.height},0,rl.WHITE)
}

PixelWindowHeight :: 180

Level :: struct {
	walls: [dynamic]rl.Vector2,
}
TileMap :: struct{		//Represents a tilemap as a Matrix of size [X x Y x Z]
	tiles : []u32		//Pointer address to the array of tilemap data
}

World :: struct{
	tileSideMeters: f32,//Size of a tile in metric
	tileSidePixels: int,//Size of a tile in pixels
	countX : int,  		//Columns of the tilemap
	countY : int,		//Rows of the tilemap
	countZ: int,		//Depths of the tilemap
	upperLeftX : f32,
	upperLeftY : f32,	//Origin
	
	tileMapCountX : int,//number X of the TileMaps array
	tileMapCountY : int,//number Y of the TileMaps array
	tileMaps : []TileMap
}

wall_collider :: proc(pos: rl.Vector2) -> rl.Rectangle {
	return {
		pos.x, pos.y,
		96,16,
	}
}

floorf32toint :: proc(value: f32) -> int {
	return int(math.floor(value))
}
truncatef32toint :: proc(value: f32) -> int {
	return int(value + 0.5)
}

getTileMap :: proc(world: ^World, tileMapX, tileMapY: int) -> ^TileMap{
	tile_map : ^TileMap
	if tileMapX >= 0 && tileMapX < world.tileMapCountX &&
		tileMapY >= 0 && tileMapY < world.tileMapCountY 
	{
		tile_map = &world.tileMaps[tileMapY * world.tileMapCountX + tileMapX]
	}
	return tile_map
}

getTileValue :: proc(world: ^World, tile_map: ^TileMap, tileX, tileY: int) -> u32{
	tile_map_value : u32 = tile_map.tiles[tileY * world.countX + tileX]
	return tile_map_value
}

isTileEmpty :: proc(world: ^World, tile_map: ^TileMap, testX, testY: int) -> bool {
	empty : bool = false
	if tile_map != nil{
		if testX >= 0 && testX < world.countX &&
		   testY >= 0 && testY < world.countY 
		{
			tile_map_value := tile_map.tiles[testY * world.countX + testX]
			empty = getTileValue(world, tile_map, testX, testY) == 0
		}
	}
	return empty
}

canonicalizeCoord :: proc(world: ^World, TileCount : int, TileMap, Tile : ^int, TileRel: ^f32)	{
	Offset : int = floorf32toint(TileRel^ / f32(world.tileSidePixels))
	Tile^ += Offset
	TileRel^ -= f32(Offset*world.tileSidePixels)

	assert(TileRel^ >= 0)
	assert(TileRel^ < f32(world.tileSidePixels))

	if Tile^ < 0 {
		Tile^ = TileCount + Tile^
		TileMap^ -= 1
	}
	if Tile^ >= TileCount {
		Tile^ = Tile^ - TileCount
		TileMap^ += 1
	}
}

recanonicalizePosition :: proc (world : ^World, pos: CanonicalPosition) -> CanonicalPosition {
	Result : CanonicalPosition = pos

	canonicalizeCoord(world, world.countX, &Result.TileMapX, &Result.TileX, &Result.X)
	canonicalizeCoord(world, world.countY, &Result.TileMapY, &Result.TileY, &Result.Y)

	return Result
}

isWorldPointEmpty :: proc(world: ^World, CanPos: CanonicalPosition) -> bool {
	empty : bool = false
	tile_map : ^TileMap = getTileMap(world, CanPos.TileMapX, CanPos.TileMapY)
	empty = isTileEmpty(world, tile_map, CanPos.TileX, CanPos.TileY)
	return empty
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

	tile_maps : [4]TileMap
	tile_maps[0] = {
		tiles ={1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
				1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1,
				1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 1, 1,
				1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1,
				1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0,
				1, 0, 1, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1,
				1, 0, 0, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 1, 0, 1,
				1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1,
				1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1},
	}
	tile_maps[1] = {
		tiles ={1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
				1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1,
				1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 1,
				1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
				0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
				1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1,
				1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
				1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1,
				1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1},
	}
	tile_maps[2] = {
		tiles ={1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1,
				1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1,
				1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
				1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
				1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
				1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
				1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1,
				1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	}
	tile_maps[3] = {
		tiles ={1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1,
				1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1,
				1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1,
				1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1,
				0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1,
				1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 1, 1,
				1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
				1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
				1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	}
	world : World = {
		tileSideMeters = 1.4,
		tileSidePixels = 16,
		countX = 16,
		countY = 9,
		tileMapCountX = 2,
		tileMapCountY = 2,
	}
	world.tileMaps = tile_maps[0:4]
	tilemap : ^TileMap = getTileMap(&world,0,0)
	assert(tilemap != nil, "Tilemap Loaded Incorrectly")
	
	grassSprite : rl.Texture2D = rl.LoadTexture("assets\\tilesets\\spring.png")
	dirtSprite : rl.Texture2D = rl.LoadTexture("assets\\tilesets\\dirt.png")
	waterSprite : rl.Texture2D = rl.LoadTexture("assets\\tilesets\\water - spring.png")
	DT :: 1.0/60.0
	accumulated_time : f32
	P : Player = {
		speed = 100,
		pos = CanonicalPosition{
			TileMapX = 0,
			TileMapY = 0,
			TileX = 3,
			TileY = 2,
			X = 5.0,
			Y = 5.0
		}
	}
	player_collider := rl.Rectangle{
		f32(world.tileSidePixels*P.pos.TileX) + P.pos.X,
		f32(world.tileSidePixels*P.pos.TileY) + P.pos.Y,
		10,
		6,
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
			player_collider.x = f32(world.tileSidePixels*P.pos.TileX) + P.pos.X + P.velocity.x * DT - player_collider.width/2.0
			player_collider.y = f32(world.tileSidePixels*P.pos.TileY) + P.pos.Y + P.velocity.y * DT - player_collider.height
			
			for wall in level.walls {
				wall_col := wall_collider(wall)
				if rl.CheckCollisionRecs(player_collider,wall_col) {
					if P.pos.X + player_collider.width/2 < wall_col.x && P.velocity.x > 0 {P.velocity.x = 0}
					if P.pos.X - player_collider.width/2 > wall_col.x + wall_col.width && P.velocity.x < 0 {P.velocity.x = 0}
					if P.pos.Y < wall_col.y && P.velocity.y > 0 {P.velocity.y = 0}
					if P.pos.Y - player_collider.height > wall_col.y + wall_col.height && P.velocity.y < 0 {P.velocity.y = 0}
				}
			}
			new_player_pos : CanonicalPosition = P.pos
			new_player_pos.X += P.velocity.x * DT
			new_player_pos.Y += P.velocity.y * DT
			new_player_pos = recanonicalizePosition(&world, new_player_pos)
			PlayerLeft : CanonicalPosition = new_player_pos
			PlayerLeft.X -= 0.5*player_collider.width
			PlayerLeft = recanonicalizePosition(&world, PlayerLeft)
			PlayerRight : CanonicalPosition = new_player_pos
			PlayerRight.X += 0.5*player_collider.width
			PlayerRight = recanonicalizePosition(&world, PlayerRight)

			if  isWorldPointEmpty(&world, new_player_pos) &&
				isWorldPointEmpty(&world, PlayerLeft) &&
				isWorldPointEmpty(&world, PlayerRight){
					P.pos = new_player_pos
			}
			player_collider.x = f32(world.tileSidePixels*P.pos.TileX) + P.pos.X - player_collider.width/2.0
			player_collider.y = f32(world.tileSidePixels*P.pos.TileY) + P.pos.Y - player_collider.height
			accumulated_time -= DT
		}
		blend := accumulated_time / DT
		//player_render_pos := math.lerp(P.old_pos, P.pos, blend)
		
		rl.BeginDrawing()
		rl.ClearBackground({110, 184, 168, 255})
		
		update_animation(&current_anim)

		screen_height := f32(rl.GetScreenHeight())
		camera := rl.Camera2D {
			zoom = screen_height/PixelWindowHeight,
			offset = {f32(rl.GetScreenWidth()/2),screen_height/2},
			target = {f32(world.countX*(world.tileSidePixels)/2),f32(world.countY*world.tileSidePixels/2)}
		}
		
		rl.BeginMode2D(camera)
		tilemap = getTileMap( &world, P.pos.TileMapX, P.pos.TileMapY)
		for row :=0; row<world.countY; row += 1 {
			for column :=0; column<world.countX; column += 1 {
				tileID := getTileValue(&world, tilemap, column, row)
				if tilemap.tiles[row*world.countX+column] == 1 {
					rl.DrawRectangle(i32(column*world.tileSidePixels),i32(row*world.tileSidePixels),i32(world.tileSidePixels),i32(world.tileSidePixels),{150, 200, 200, 255})
				}
				else {rl.DrawRectangle(i32(column*world.tileSidePixels),i32(row*world.tileSidePixels),i32(world.tileSidePixels),i32(world.tileSidePixels),rl.LIME)}
			}
		}
		for wall in level.walls {	rl.DrawRectangleRec(wall_collider(wall),rl.RED)}
		draw_animation(current_anim, {world.upperLeftX + f32(world.tileSidePixels*P.pos.TileX) + P.pos.X,
									  world.upperLeftY + f32(world.tileSidePixels*P.pos.TileY) + P.pos.Y}, int(P.dir), P.flip)
		rl.DrawCircleV({f32(world.countX*(world.tileSidePixels)/2),f32(world.countY*world.tileSidePixels/2)},1,rl.RED)
		rl.DrawRectangleRec(player_collider,{0,50,150,100}) //Debug Player Collider

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