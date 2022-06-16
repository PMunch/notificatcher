# Package

version       = "0.4.0"
author        = "PMunch"
description   = "Small program to read freedesktop notifications and format them as strings"
license       = "MIT"
srcDir        = "src"
bin           = @["notificatcher"]



# Dependencies

requires "nim >= 1.2.6"
requires "https://github.com/PMunch/nim-dbus#newernim"
requires "https://github.com/PMunch/docopt.nim#dispatch"
requires "nimPNG"
