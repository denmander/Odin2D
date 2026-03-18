#+feature dynamic-literals
package game

import "core:math"
import "core:mem"
import "core:fmt"
import "core:os"
import rl "vendor:raylib"

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

floorf32toint :: proc(value: f32) -> int {
	return int(math.floor(value))
}
roundf32toint :: proc(value: f32) -> int {
	return int(math.round(value))
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
	Memory : GameMemory
	Memory.PermanentStorageSize = 64*mem.Megabyte
	Memory.TransientStorageSize = mem.Gigabyte
	AllocatedMemory, _ := mem.alloc(int(Memory.PermanentStorageSize + Memory.TransientStorageSize))
	Memory.PermanentStorage = AllocatedMemory
	Memory.TransientStorage = mem.ptr_offset((^u8)(Memory.PermanentStorage), Memory.PermanentStorageSize)
	game_state : GameState
	InitializeArena(&game_state.world_arena, )

	game_state.world = PushStruct(&game_state.world_arena ,world)
	world : ^World = game_state.world
	world.tilemap = PushStruct(&game_state.world_arena, tilemap)

	tilemap : ^TileMap = world.tilemap

	// Set to using 256x256 tile chunks
	tilemap.ChunkShift = 8
	tilemap.ChunkMask = (1 << tilemap.ChunkShift) - 1
	tilemap.tileSideMeters = 1.4
	tilemap.tileSidePixels = 16
	tilemap.ChunkDim = 256
	tilemap.tileChunkCountX = 1
	tilemap.tileChunkCountY = 1

	tile_chunks : TileChunk
	chunk: [256][256]u32 = {}
	TilesPerWidth : u32 = 17
	TilesPerHeight : u32 = 9
	for ScreenY : u32 = 0; ScreenY < 32; ScreenY += 1 {
		for ScreenX : u32 = 0; ScreenX < 32; ScreenX += 1 {
			for TileY : u32 = 0; TileY < TilesPerHeight; TileY += 1{
				for TileX : u32 = 0; TileX < TilesPerWidth; TileX += 1{
					AbsTileX := ScreenX*TilesPerWidth + TileX
					AbsTileY := ScreenY*TilesPerHeight + TileY
					setTileValue(world.tilemap,AbsTileX,AbsTileY,0)
				}
			}
		}
	}
	/*temp_tiles:[][]u32 = {
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
	fill_chunk(2,2, &chunk, &temp_tiles)*/ // Fixed test initialization 
	tile_chunks.tiles = &chunk[0][0]
	tilemap.metersToPixels = f32(tilemap.tileSidePixels) / tilemap.tileSideMeters
	tilemap.tileChunks = &tile_chunks
	tileChunk : ^TileChunk = getTileChunk(tilemap,0,0)
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
		pos = TileMapPosition{
			AbsTileX = 20,
			AbsTileY = 10,
			TileRelX = 5.0,
			TileRelY = 5.0
		}
	}
	player_collider := rl.Rectangle{
		tilemap.tileSideMeters*tilemap.metersToPixels*f32(P.pos.AbsTileX) + P.pos.TileRelX,
		tilemap.tileSideMeters*tilemap.metersToPixels*f32(P.pos.AbsTileY) + P.pos.TileRelY,
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
			player_collider.x = tilemap.metersToPixels*(tilemap.tileSideMeters*f32(P.pos.AbsTileX) + P.pos.TileRelX + P.velocity.x) * DT - player_collider.width/2.0
			player_collider.y = tilemap.metersToPixels*(tilemap.tileSideMeters*f32(P.pos.AbsTileY) + P.pos.TileRelY + P.velocity.y) * DT - player_collider.height
			
			new_player_pos : TileMapPosition = P.pos
			new_player_pos.TileRelX += P.velocity.x * DT
			new_player_pos.TileRelY += P.velocity.y * DT
			new_player_pos = recanonicalizePosition(tilemap, new_player_pos)
			PlayerLeft : TileMapPosition = new_player_pos
			PlayerLeft.TileRelX -= 0.5*player_collider.width/tilemap.metersToPixels
			PlayerLeft = recanonicalizePosition(tilemap, PlayerLeft)
			PlayerRight : TileMapPosition = new_player_pos
			PlayerRight.TileRelX += 0.5*player_collider.width/tilemap.metersToPixels
			PlayerRight = recanonicalizePosition(tilemap, PlayerRight)
			if  isTileMapPointEmpty(tilemap, new_player_pos) &&
			isTileMapPointEmpty(tilemap, PlayerLeft) &&
			isTileMapPointEmpty(tilemap, PlayerRight){
				P.pos = new_player_pos
			}
			player_collider.x = tilemap.metersToPixels*(tilemap.tileSideMeters*f32(P.pos.AbsTileX) + P.pos.TileRelX) - player_collider.width/2.0
			player_collider.y = tilemap.metersToPixels*(tilemap.tileSideMeters*f32(P.pos.AbsTileY) + P.pos.TileRelY) - player_collider.height
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
			target = {f32(P.pos.AbsTileX)*f32(tilemap.tileSidePixels)+P.pos.TileRelX*tilemap.metersToPixels,f32(P.pos.AbsTileY)*f32(tilemap.tileSidePixels)+P.pos.TileRelY*tilemap.metersToPixels}
		}
		
		rl.BeginMode2D(camera)
		for RelRow :=-10; RelRow<10; RelRow += 1 {
			for RelColumn :=-20; RelColumn<+20; RelColumn += 1 {
				Row := int(P.pos.AbsTileY) + RelRow
				Column := int(P.pos.AbsTileX) + RelColumn
				tileID := getTileValue(tilemap, u32(Column), u32(Row))
				color : rl.Color
				StartX := i32(Column*tilemap.tileSidePixels) - i32(tilemap.tileSidePixels)/2
				StartY := i32(Row*tilemap.tileSidePixels) - i32(tilemap.tileSidePixels)/2
				
				if tileID == 1 {
					color = {150, 200, 200, 255}
					//rl.DrawRectangle(i32(Column*tilemap.tileSidePixels),i32(Row*tilemap.tileSidePixels),i32(tilemap.tileSidePixels),i32(tilemap.tileSidePixels),{150, 200, 200, 255})
				}
				else {
					if Column == int(P.pos.AbsTileX) && Row == int(P.pos.AbsTileY) {
						color = rl.BLACK
						//rl.DrawRectangle(i32(Column*tilemap.tileSidePixels),i32(Row*tilemap.tileSidePixels),i32(tilemap.tileSidePixels),i32(tilemap.tileSidePixels),rl.BLACK)	
					} else {
						color = rl.LIME
						//rl.DrawRectangle(i32(Column*tilemap.tileSidePixels),i32(Row*tilemap.tileSidePixels),i32(tilemap.tileSidePixels),i32(tilemap.tileSidePixels),rl.LIME)
					}
					rl.DrawRectangle(StartX,StartY,i32(tilemap.tileSidePixels),i32(tilemap.tileSidePixels),color)
				}
			}
		}
		draw_animation(current_anim, {upperLeftX + f32(tilemap.tileSidePixels*int(P.pos.AbsTileX)) + tilemap.metersToPixels*P.pos.TileRelX,
				upperLeftY + f32(tilemap.tileSidePixels*int(P.pos.AbsTileY)) + tilemap.metersToPixels*P.pos.TileRelY}, int(P.dir), P.flip)
		rl.DrawCircleV({f32(P.pos.AbsTileX)*f32(tilemap.tileSidePixels),f32(P.pos.AbsTileY)*f32(tilemap.tileSidePixels)},1,rl.RED)
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