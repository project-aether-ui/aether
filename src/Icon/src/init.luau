--!strict
--- spektr/icon. Implementation in Icon.luau.
---
--- ms-51 M19: split out because requiring a package DIRECTORY makes lune resolve
--- init.luau's own relative requires from the CALLER's folder — so this module's
--- path to Aether's sibling host depended on who reached it, and four candidate
--- paths all failed for some caller. Requiring the named module by path resolves
--- its siblings normally. Same shape as spektr/controls, spektr/window_topbar and
--- spektr/mouse.
return require("./Icon")
