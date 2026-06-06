odin build main.odin -file -out:build/debug.exe -debug
odin build game.odin -file -define:RAYLIB_SHARED=true -build-mode:dll -out:build/game.dll -debug
