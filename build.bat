odin build src/main.odin -file -out:build/debug.exe -debug
odin build src/game -define:RAYLIB_SHARED=true -build-mode:dll -out:build/game.dll -debug