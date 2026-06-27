odin build src/main.odin -file -out:debug.exe -debug
odin build src/game -build-mode:dll -define:RAYLIB_SHARED=true -out:game.dll -debug
