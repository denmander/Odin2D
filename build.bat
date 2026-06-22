odin build src/main.odin -file -out:build/debug.exe -debug
odin build src/game -build-mode:dll -define:RAYLIB_SHARED=true -out:build/game.dll -debug