package game

import "core:mem"
import "core:math"
import rl "vendor:raylib"
Memory : ^GameMemory
game_state : ^GameState
tilemap : ^TileMap

@(export)
game_init :: proc() {
    Memory = new(GameMemory)
	Memory.PermanentStorageSize = 64*mem.Megabyte
	Memory.TransientStorageSize = mem.Gigabyte
	assert(size_of(GameState) <= Memory.PermanentStorageSize)
	AllocatedMemory, _ := mem.alloc(int(Memory.PermanentStorageSize + Memory.TransientStorageSize))
	Memory.PermanentStorage = AllocatedMemory
	Memory.TransientStorage = mem.ptr_offset(cast(^u8)(Memory.PermanentStorage), Memory.PermanentStorageSize)
	game_state = cast(^GameState)Memory.PermanentStorage
	game_state.PlayerP = TileMapPosition{
		AbsTileX = 20,
		AbsTileY = 10,
		TileRelX = 5.0,
		TileRelY = 5.0
	}
	if !Memory.is_initialized
	{
		InitializeArena(&game_state.world_arena, uint(Memory.PermanentStorageSize - size_of(GameState)), mem.ptr_offset(cast(^u8)Memory.PermanentStorage, size_of(GameState)))

		game_state.world = cast(^World)(PushStruct(&game_state.world_arena, World))
		world : ^World = game_state.world
		world.tilemap = cast(^TileMap)(PushStruct(&game_state.world_arena, TileMap))

		tilemap = world.tilemap

		// Set to using 256x256 tile chunks
		tilemap.ChunkShift = 8
		tilemap.ChunkMask = (1 << tilemap.ChunkShift) - 1
		tilemap.ChunkDim = 1 << tilemap.ChunkShift
		tilemap.tileSideMeters = 1.4
		tilemap.tileSidePixels = 16
		tilemap.metersToPixels = f32(tilemap.tileSidePixels) / tilemap.tileSideMeters

		tilemap.tileChunkCountX = 128
		tilemap.tileChunkCountY = 128

		tilemap.tileChunks = cast(^TileChunk)PushArray(&game_state.world_arena,uint(tilemap.tileChunkCountX*tilemap.tileChunkCountY),TileChunk)
		
		for Y : u32 = 0; Y < tilemap.tileChunkCountY; Y += 1 {
			for X : u32 = 0; X < tilemap.tileChunkCountX; X += 1 {
				tilemap.tileChunks[Y*tilemap.tileChunkCountX + X].tiles = cast(^u32)PushArray(&game_state.world_arena,
																uint(tilemap.ChunkDim*tilemap.ChunkDim),u32)
			}
		}
		TilesPerWidth : u32 = 17
		TilesPerHeight : u32 = 9
		for ScreenY : u32 = 0; ScreenY < 32; ScreenY += 1 {
			for ScreenX : u32 = 0; ScreenX < 32; ScreenX += 1 {
				for TileY : u32 = 0; TileY < TilesPerHeight; TileY += 1 {
					for TileX : u32 = 0; TileX < TilesPerWidth; TileX += 1 {
						AbsTileX := ScreenX*TilesPerWidth + TileX
						AbsTileY := ScreenY*TilesPerHeight + TileY
						if (TileX == TileY && TileY%2 == 0) {
							setTileValue(world.tilemap,AbsTileX,AbsTileY,1)
						} else {
							setTileValue(world.tilemap,AbsTileX,AbsTileY,0)
						}
					}
				}
			}
		}
		Memory.is_initialized = true
	}
	world : ^World = game_state.world
	tilemap: ^TileMap = world.tilemap
	
	P = {
		speed = 4.0,
	}
	P.collider = rl.Rectangle{
		tilemap.tileSideMeters*tilemap.metersToPixels*f32(game_state.PlayerP.AbsTileX) + game_state.PlayerP.TileRelX,
		tilemap.tileSideMeters*tilemap.metersToPixels*f32(game_state.PlayerP.AbsTileY) + game_state.PlayerP.TileRelY,
		10,
		6,
	}
	player_walk = Animation {
		texture = rl.LoadTexture("assets\\character\\walk.png"),
		frame_count = 8,
		rows = 3,
		frame_length = 0.1,
		name = .walk
	}
	player_idle = Animation{
		texture = rl.LoadTexture("assets\\character\\idle.png"),
		frame_count = 4,
		rows = 3,
		frame_length = 0.2,
		name = .idle
	}
	current_anim = player_idle
	game_hot_reloaded(Memory)
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(1280,720,"Game")
	rl.SetWindowPosition(10,10)
	rl.SetWindowState({.WINDOW_RESIZABLE})
	rl.SetTargetFPS(60)
}

DT :: 1.0/60.0
accumulated_time : f32
P : Player
current_anim : Animation
player_idle : Animation
player_walk : Animation
update :: proc() {
	accumulated_time += rl.GetFrameTime() //Fixed timestep
	for accumulated_time >= DT {
		dir : rl.Vector2
		if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsGamepadButtonDown(0, rl.GamepadButton.RIGHT_FACE_RIGHT){
			P.speed = 10.0
		} else { P.speed = 4.0}
		if rl.IsKeyDown(.UP) || rl.IsKeyDown(.W) || (rl.GetGamepadAxisMovement(0, rl.GamepadAxis.LEFT_Y) < -0.1) {
			dir += {0,-1}
			P.dir = Direction.UP
		}
		if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S) || (rl.GetGamepadAxisMovement(0, rl.GamepadAxis.LEFT_Y) > 0.1)  {
			dir += {0,1}
			P.dir = Direction.DOWN
		}
		if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) || (rl.GetGamepadAxisMovement(0, rl.GamepadAxis.LEFT_X) < -0.1)  {
			dir += {-1,0}
			P.flip = true
			P.dir = Direction.SIDE
		}
		if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) || (rl.GetGamepadAxisMovement(0, rl.GamepadAxis.LEFT_X) > 0.1)  {
			dir += {1,0}
			P.flip = false
			P.dir = Direction.SIDE
		}
		if dir != {0,0} {
			P.velocity = math.lerp(P.velocity, dir * P.speed, f32(0.8))
			if current_anim.name != .walk {current_anim = player_walk}
		} else {
			P.velocity = math.lerp(P.velocity, rl.Vector2{0,0}, f32(0.8))
			if current_anim.name != .idle {current_anim = player_idle}
		}
		P.collider.x = tilemap.metersToPixels*(tilemap.tileSideMeters*f32(game_state.PlayerP.AbsTileX) + game_state.PlayerP.TileRelX + P.velocity.x) * DT - P.collider.width/2.0
		P.collider.y = tilemap.metersToPixels*(tilemap.tileSideMeters*f32(game_state.PlayerP.AbsTileY) + game_state.PlayerP.TileRelY + P.velocity.y) * DT - P.collider.height
		
		new_player_pos : TileMapPosition = game_state.PlayerP
		new_player_pos.TileRelX += P.velocity.x * DT
		new_player_pos.TileRelY += P.velocity.y * DT
		new_player_pos = recanonicalizePosition(tilemap, new_player_pos)
		PlayerLeft : TileMapPosition = new_player_pos
		PlayerLeft.TileRelX -= 0.5*P.collider.width/tilemap.metersToPixels
		PlayerLeft = recanonicalizePosition(tilemap, PlayerLeft)
		PlayerRight : TileMapPosition = new_player_pos
		PlayerRight.TileRelX += 0.5*P.collider.width/tilemap.metersToPixels
		PlayerRight = recanonicalizePosition(tilemap, PlayerRight)
		if  isTileMapPointEmpty(tilemap, new_player_pos) &&
		isTileMapPointEmpty(tilemap, PlayerLeft) &&
		isTileMapPointEmpty(tilemap, PlayerRight){
			game_state.PlayerP = new_player_pos
		}
		P.collider.x = tilemap.metersToPixels*(tilemap.tileSideMeters*f32(game_state.PlayerP.AbsTileX) + game_state.PlayerP.TileRelX) - P.collider.width/2.0
		P.collider.y = tilemap.metersToPixels*(tilemap.tileSideMeters*f32(game_state.PlayerP.AbsTileY) + game_state.PlayerP.TileRelY) - P.collider.height
		accumulated_time -= DT
	}
	//blend := accumulated_time / DT
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground({110, 184, 168, 255})
	
	update_animation(&current_anim)
	
	screen_height := f32(rl.GetScreenHeight())
	camera := rl.Camera2D {
		zoom = screen_height/PixelWindowHeight,
		offset = {f32(rl.GetScreenWidth()/2),screen_height/2},
		target = {f32(game_state.PlayerP.AbsTileX)*f32(tilemap.tileSidePixels)+game_state.PlayerP.TileRelX*tilemap.metersToPixels,f32(game_state.PlayerP.AbsTileY)*f32(tilemap.tileSidePixels)+game_state.PlayerP.TileRelY*tilemap.metersToPixels}
	}
	
	rl.BeginMode2D(camera)
	for RelRow :=-10; RelRow<10; RelRow += 1 {
		for RelColumn :=-20; RelColumn<+20; RelColumn += 1 {
			Row := int(game_state.PlayerP.AbsTileY) + RelRow
			Column := int(game_state.PlayerP.AbsTileX) + RelColumn
			tileID := getTileValue(tilemap, u32(Column), u32(Row))
			color : rl.Color
			StartX := i32(Column*tilemap.tileSidePixels) - i32(tilemap.tileSidePixels)/2
			StartY := i32(Row*tilemap.tileSidePixels) - i32(tilemap.tileSidePixels)/2
			
			if tileID == 1 {
				color = {150, 200, 200, 255}
			}
			else {
				if Column == int(game_state.PlayerP.AbsTileX) && Row == int(game_state.PlayerP.AbsTileY) {
					color = rl.BLACK
				} else {
					color = rl.LIME
				}
			}
			rl.DrawRectangle(StartX,StartY,i32(tilemap.tileSidePixels),i32(tilemap.tileSidePixels),color)
		}
	}
	draw_animation(current_anim, {f32(tilemap.tileSidePixels*int(game_state.PlayerP.AbsTileX)) + tilemap.metersToPixels*game_state.PlayerP.TileRelX,
			f32(tilemap.tileSidePixels*int(game_state.PlayerP.AbsTileY)) + tilemap.metersToPixels*game_state.PlayerP.TileRelY}, int(P.dir), P.flip)
	rl.DrawCircleV({f32(game_state.PlayerP.AbsTileX)*f32(tilemap.tileSidePixels),f32(game_state.PlayerP.AbsTileY)*f32(tilemap.tileSidePixels)},1,rl.RED)
	rl.DrawRectangleRec(P.collider,{0,50,150,100}) //Debug Player Collider

	rl.EndMode2D()
	rl.EndDrawing()
}

@(export)
game_update :: proc() -> bool {
	update()
	draw()

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

@(export)
game_should_run :: proc() -> bool {
	if rl.WindowShouldClose() {
		return false
	}
	return Memory.run
}