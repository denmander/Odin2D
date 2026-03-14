package game

TileMapPosition :: struct{
	//These are fixed point tile locations.
	//24 high bits for tile chunk index, 8 low bits for tile index within the chunk
	AbsTileX, AbsTileY: u32, 
	TileRelX, TileRelY: f32 "Tile relative X and Y"
}
TileChunkPosition :: struct{
	TileChunkX, TileChunkY : u32,
	RelTileX, RelTileY : u32
}
TileChunk :: struct{	//Represents a tilechunk as a Matrix of size [X x Y x Z]
	tiles : [^]u32		//Pointer address to the array of tilechunk data
}
TileMap :: struct{
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

getTileChunk :: proc(tilemap: ^TileMap, tileChunkX, tileChunkY: u32) -> ^TileChunk{
	tile_chunk : ^TileChunk
	if tileChunkX >= 0 && tileChunkX < tilemap.tileChunkCountX &&
		tileChunkY >= 0 && tileChunkY < tilemap.tileChunkCountY 
	{
		tile_chunk = &tilemap.tileChunks[tileChunkY*tilemap.ChunkDim +tileChunkX]
	}
	return tile_chunk
}

getTileValueUnchecked :: proc(tilemap: ^TileMap, tile_chunk: ^TileChunk, tileX, tileY: u32) -> u32{
	assert(tile_chunk != nil)
	assert(tileX < tilemap.ChunkDim)
	assert(tileY < tilemap.ChunkDim)
	tile_chunk_value : u32 = tile_chunk.tiles[tileY*tilemap.ChunkDim +tileX]
	return tile_chunk_value
}

getTileValue :: proc(tilemap: ^TileMap, AbsTileX, AbsTileY: u32) -> u32 { //Placeholder
	chunk_pos : TileChunkPosition = getChunkPos(tilemap, AbsTileX, AbsTileY)
	tile_map : ^TileChunk = getTileChunk(tilemap, chunk_pos.TileChunkX, chunk_pos.TileChunkY)
	tile_value : u32 = getChunkTileValue(tilemap, tile_map, AbsTileX, AbsTileY)
	return tile_value
}

getChunkTileValue :: proc(tilemap: ^TileMap, tile_chunk: ^TileChunk, testX, testY: u32) -> u32 {
    chunk_tile_value: u32 = 0
    if tile_chunk != nil{
            chunk_tile_value = getTileValueUnchecked(tilemap, tile_chunk, testX, testY)
        }
    return chunk_tile_value
}

getChunkPos :: proc(tilemap: ^TileMap, AbsTileX, AbsTileY : u32) -> TileChunkPosition{
	Result : TileChunkPosition
	Result.TileChunkX = AbsTileX >> tilemap.ChunkShift
	Result.TileChunkY = AbsTileY >> tilemap.ChunkShift
	Result.RelTileX = AbsTileX & tilemap.ChunkMask
	Result.RelTileY = AbsTileY & tilemap.ChunkMask

	return Result
}

isChunkTileEmpty :: proc(tilemap: ^TileMap, tile_chunk: ^TileChunk, testX, testY: u32) -> bool {
	empty : bool = false
	if tile_chunk != nil{
			tile_chunk_value := getTileValueUnchecked(tilemap, tile_chunk, testX, testY)
			empty = tile_chunk_value == 0
		}
	return empty
}

isTileMapPointEmpty :: proc(tilemap: ^TileMap, CanPos: TileMapPosition) -> bool {
	tile_chunk_value : u32 = getTileValue(tilemap, CanPos.AbsTileX, CanPos.AbsTileY)	
	empty : bool = tile_chunk_value == 0
	return empty
}

canonicalizeCoord :: proc(tilemap: ^TileMap, Tile : ^u32, TileRel: ^f32)	{
	// divide/multiply method can round back to the same tile in an edge case
	// Bounds checking to prevent wrapping?
	Offset : int = roundf32toint(TileRel^ / f32(tilemap.tileSideMeters))
	Tile^ += u32(Offset)
	TileRel^ -= f32(Offset)*tilemap.tileSideMeters

	assert(TileRel^ >= -0.5*f32(tilemap.tileSideMeters))
	assert(TileRel^ <= 0.5*f32(tilemap.tileSideMeters))
}

recanonicalizePosition :: proc (tilemap : ^TileMap, pos: TileMapPosition) -> TileMapPosition {
	Result : TileMapPosition = pos

	canonicalizeCoord(tilemap, &Result.AbsTileX, &Result.TileRelX)
	canonicalizeCoord(tilemap, &Result.AbsTileY, &Result.TileRelY)

	return Result
}