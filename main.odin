#+feature dynamic-literals
package game

import "core:math"
import "core:mem"
import "core:fmt"
import "core:os"
import rl "vendor:raylib"

WorldPosition :: struct{
	//These are fixed point tile locations.
	//24 high bits for tile chunk index, 8 low bits for tile index within the chunk
	AbsTileX, AbsTileY: u32, 
	TileRelX, TileRelY: f32 "Tile relative X and Y"
}
TileChunkPosition :: struct{
	TileChunkX, TileChunkY : u32,
	RelTileX, RelTileY : u32
}
Direction :: enum {
	SIDE,
	DOWN,
	UP
}
Player :: struct {
	pos : WorldPosition,
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

fill_chunk :: proc(start_x, start_y: int, chunk: ^[256][256]u32, block: ^[][]u32){
	for y := 0; y < len(block); y += 1{
		for x := 0; x < len(block[0]); x += 1{
			if block[y][x] != 0 {
				chunk[y+start_y][x+start_x] = block[y][x]
			}
		}
	}
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

TileChunk :: struct{	//Represents a tilechunk as a Matrix of size [X x Y x Z]
	tiles : [^]u32		//Pointer address to the array of tilechunk data
}

World :: struct{
	ChunkShift: u32,
	ChunkMask: u32,

	tileSideMeters: f32,//Size of a tile in metric
	tileSidePixels: int,//Size of a tile in pixels
	metersToPixels: f32,
	ChunkDim : u32, 	//Dimension of a chunk
	layer: int,		//Depth of the tilemap
	
	tileChunkCountX : u32,//number X of the TileMaps array
	tileChunkCountY : u32,//number Y of the TileMaps array
	tileChunks : [^]TileChunk
}

floorf32toint :: proc(value: f32) -> int {
	return int(math.floor(value))
}
roundf32toint :: proc(value: f32) -> int {
	return int(math.round(value))
}

getTileChunk :: proc(world: ^World, tileChunkX, tileChunkY: u32) -> ^TileChunk{
	tile_chunk : ^TileChunk
	if tileChunkX >= 0 && tileChunkX < world.tileChunkCountX &&
		tileChunkY >= 0 && tileChunkY < world.tileChunkCountY 
	{
		tile_chunk = &world.tileChunks[tileChunkY*world.ChunkDim +tileChunkX]
	}
	return tile_chunk
}

getTileValueUnchecked :: proc(world: ^World, tile_chunk: ^TileChunk, tileX, tileY: u32) -> u32{
	assert(tile_chunk != nil)
	assert(tileX < world.ChunkDim)
	assert(tileY < world.ChunkDim)
	tile_chunk_value : u32 = tile_chunk.tiles[tileY*world.ChunkDim +tileX]
	return tile_chunk_value
}

isChunkTileEmpty :: proc(world: ^World, tile_chunk: ^TileChunk, testX, testY: u32) -> bool {
	empty : bool = false
	if tile_chunk != nil{
			tile_chunk_value := getTileValueUnchecked(world, tile_chunk, testX, testY)
			empty = tile_chunk_value == 0
		}
	return empty
}

canonicalizeCoord :: proc(world: ^World, Tile : ^u32, TileRel: ^f32)	{
	// divide/multiply method can round back to the same tile in an edge case
	// Bounds checking to prevent wrapping?
	Offset : int = roundf32toint(TileRel^ / f32(world.tileSideMeters))
	Tile^ += u32(Offset)
	TileRel^ -= f32(Offset)*world.tileSideMeters

	assert(TileRel^ >= -0.5*f32(world.tileSideMeters))
	assert(TileRel^ <= 0.5*f32(world.tileSideMeters))
}

recanonicalizePosition :: proc (world : ^World, pos: WorldPosition) -> WorldPosition {
	Result : WorldPosition = pos

	canonicalizeCoord(world, &Result.AbsTileX, &Result.TileRelX)
	canonicalizeCoord(world, &Result.AbsTileY, &Result.TileRelY)

	return Result
}

getChunkPos :: proc(world: ^World, AbsTileX, AbsTileY : u32) -> TileChunkPosition{
	Result : TileChunkPosition
	Result.TileChunkX = AbsTileX >> world.ChunkShift
	Result.TileChunkY = AbsTileY >> world.ChunkShift
	Result.RelTileX = AbsTileX & world.ChunkMask
	Result.RelTileY = AbsTileY & world.ChunkMask

	return Result
}

getChunkTileValue :: proc(world: ^World, tile_chunk: ^TileChunk, testX, testY: u32) -> u32 {
	chunk_tile_value: u32 = 0
	if tile_chunk != nil{
			chunk_tile_value = getTileValueUnchecked(world, tile_chunk, testX, testY)
		}
	return chunk_tile_value
}

getTileValue :: proc(world: ^World, AbsTileX, AbsTileY: u32) -> u32 { //Placeholder
	chunk_pos : TileChunkPosition = getChunkPos(world, AbsTileX, AbsTileY)
	tile_map : ^TileChunk = getTileChunk(world, chunk_pos.TileChunkX, chunk_pos.TileChunkY)
	tile_value : u32 = getChunkTileValue(world, tile_map, AbsTileX, AbsTileY)
	return tile_value
}

isWorldPointEmpty :: proc(world: ^World, CanPos: WorldPosition) -> bool {
	tile_chunk_value : u32 = getTileValue(world, CanPos.AbsTileX, CanPos.AbsTileY)	
	empty : bool = tile_chunk_value == 0
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

	tile_chunks : TileChunk
	world : World = {
		// Set to using 256x256 tile chunks
		ChunkShift = 8,
		ChunkMask = 0xFF,
		tileSideMeters = 1.4,
		tileSidePixels = 16,
		ChunkDim = 256,
		tileChunkCountX = 1,
		tileChunkCountY = 1,
	}
	chunk: [256][256]u32 = {}
	temp_tiles:[][]u32 = {
		{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1},
		{1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 1, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1}}
	fill_chunk(2,2, &chunk, &temp_tiles)
	tile_chunks.tiles = &chunk[0][0]
	world.metersToPixels = f32(world.tileSidePixels) / world.tileSideMeters
	world.tileChunks = &tile_chunks
	tileChunk : ^TileChunk = getTileChunk(&world,0,0)
	assert(tileChunk != nil, "Tilechunk Loaded Incorrectly")
	upperLeftX : f32
	upperLeftY : f32	//Origin
	
	grassSprite : rl.Texture2D = rl.LoadTexture("assets\\tilesets\\spring.png")
	dirtSprite : rl.Texture2D = rl.LoadTexture("assets\\tilesets\\dirt.png")
	waterSprite : rl.Texture2D = rl.LoadTexture("assets\\tilesets\\water - spring.png")
	defer rl.UnloadTexture(grassSprite)
	defer rl.UnloadTexture(dirtSprite)
	defer rl.UnloadTexture(waterSprite)
	DT :: 1.0/60.0
	accumulated_time : f32
	P : Player = {
		speed = 4.0,
		pos = WorldPosition{
			AbsTileX = 20,
			AbsTileY = 10,
			TileRelX = 5.0,
			TileRelY = 5.0
		}
	}
	player_collider := rl.Rectangle{
		world.tileSideMeters*world.metersToPixels*f32(P.pos.AbsTileX) + P.pos.TileRelX,
		world.tileSideMeters*world.metersToPixels*f32(P.pos.AbsTileY) + P.pos.TileRelY,
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
	
	editing := false
	for !rl.WindowShouldClose() {
		accumulated_time += rl.GetFrameTime() //Fixed timestep
		for accumulated_time >= DT {
			dir : rl.Vector2
			if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsGamepadButtonDown(0, rl.GamepadButton.RIGHT_FACE_RIGHT){
				P.speed = 10.0
			} else { P.speed = 4.0}
			if rl.IsKeyDown(.UP) || rl.IsKeyDown(.W) || (rl.GetGamepadAxisMovement(0, rl.GamepadAxis.LEFT_Y) < -0.1) {
				dir += {0,-1}
				P.dir = .UP
			}
			if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S) || (rl.GetGamepadAxisMovement(0, rl.GamepadAxis.LEFT_Y) > 0.1)  {
				dir += {0,1}
				P.dir = .DOWN
			}
			if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) || (rl.GetGamepadAxisMovement(0, rl.GamepadAxis.LEFT_X) < -0.1)  {
				dir += {-1,0}
				P.flip = true
				P.dir = .SIDE
			}
			if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) || (rl.GetGamepadAxisMovement(0, rl.GamepadAxis.LEFT_X) > 0.1)  {
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
			player_collider.x = world.metersToPixels*(world.tileSideMeters*f32(P.pos.AbsTileX) + P.pos.TileRelX + P.velocity.x) * DT - player_collider.width/2.0
			player_collider.y = world.metersToPixels*(world.tileSideMeters*f32(P.pos.AbsTileY) + P.pos.TileRelY + P.velocity.y) * DT - player_collider.height
			
			new_player_pos : WorldPosition = P.pos
			new_player_pos.TileRelX += P.velocity.x * DT
			new_player_pos.TileRelY += P.velocity.y * DT
			new_player_pos = recanonicalizePosition(&world, new_player_pos)
			PlayerLeft : WorldPosition = new_player_pos
			PlayerLeft.TileRelX -= 0.5*player_collider.width/world.metersToPixels
			PlayerLeft = recanonicalizePosition(&world, PlayerLeft)
			PlayerRight : WorldPosition = new_player_pos
			PlayerRight.TileRelX += 0.5*player_collider.width/world.metersToPixels
			PlayerRight = recanonicalizePosition(&world, PlayerRight)
			if  isWorldPointEmpty(&world, new_player_pos) &&
			isWorldPointEmpty(&world, PlayerLeft) &&
			isWorldPointEmpty(&world, PlayerRight){
				P.pos = new_player_pos
			}
			player_collider.x = world.metersToPixels*(world.tileSideMeters*f32(P.pos.AbsTileX) + P.pos.TileRelX) - player_collider.width/2.0
			player_collider.y = world.metersToPixels*(world.tileSideMeters*f32(P.pos.AbsTileY) + P.pos.TileRelY) - player_collider.height
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
			target = {f32(P.pos.AbsTileX)*f32(world.tileSidePixels)+P.pos.TileRelX*world.metersToPixels,f32(P.pos.AbsTileY)*f32(world.tileSidePixels)+P.pos.TileRelY*world.metersToPixels}
		}
		
		rl.BeginMode2D(camera)
		for RelRow :=-10; RelRow<10; RelRow += 1 {
			for RelColumn :=-20; RelColumn<+20; RelColumn += 1 {
				Row := int(P.pos.AbsTileY) + RelRow
				Column := int(P.pos.AbsTileX) + RelColumn
				tileID := getTileValue(&world, u32(Column), u32(Row))
				color : rl.Color
				StartX := i32(Column*world.tileSidePixels) - i32(world.tileSidePixels)/2
				StartY := i32(Row*world.tileSidePixels) - i32(world.tileSidePixels)/2
				
				if tileID == 1 {
					color = {150, 200, 200, 255}
					//rl.DrawRectangle(i32(Column*world.tileSidePixels),i32(Row*world.tileSidePixels),i32(world.tileSidePixels),i32(world.tileSidePixels),{150, 200, 200, 255})
				}
				else {
					if Column == int(P.pos.AbsTileX) && Row == int(P.pos.AbsTileY) {
						color = rl.BLACK
						//rl.DrawRectangle(i32(Column*world.tileSidePixels),i32(Row*world.tileSidePixels),i32(world.tileSidePixels),i32(world.tileSidePixels),rl.BLACK)	
					} else {
						color = rl.LIME
						//rl.DrawRectangle(i32(Column*world.tileSidePixels),i32(Row*world.tileSidePixels),i32(world.tileSidePixels),i32(world.tileSidePixels),rl.LIME)
					}
					rl.DrawRectangle(StartX,StartY,i32(world.tileSidePixels),i32(world.tileSidePixels),color)
				}
			}
		}
		draw_animation(current_anim, {upperLeftX + f32(world.tileSidePixels*int(P.pos.AbsTileX)) + world.metersToPixels*P.pos.TileRelX,
				upperLeftY + f32(world.tileSidePixels*int(P.pos.AbsTileY)) + world.metersToPixels*P.pos.TileRelY}, int(P.dir), P.flip)
		rl.DrawCircleV({f32(P.pos.AbsTileX)*f32(world.tileSidePixels),f32(P.pos.AbsTileY)*f32(world.tileSidePixels)},1,rl.RED)
		rl.DrawRectangleRec(player_collider,{0,50,150,100}) //Debug Player Collider
		
		if rl.IsKeyPressed(.F2) {
			editing = !editing
		}
		if editing {
		}

		rl.EndMode2D()
		rl.EndDrawing()
		//free_all(context.temp_allocator)
	}

	rl.CloseWindow()
	//free_all(context.temp_allocator)
}