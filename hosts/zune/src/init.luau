--!strict
--- spektr/zune_host. The program is `Server.luau`; this exists so the package
--- has a named entry point, and because a directory require would resolve
--- Server's relative paths from the CALLER's folder (ms-52 M3).
--- `@self/X`, NOT `./X` (ms-53 D8). From an INIT file `./` means the PACKAGE
--- FOLDER -- in Roblox, because Rojo collapses `src/init.luau` into a ModuleScript
--- named `src`, and in lune too, measured. `@self/X` names a child in both.
return require("@self/Server")
