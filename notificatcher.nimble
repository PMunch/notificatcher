# Package

version       = "0.5.1"
author        = "PMunch"
description   = "Small program to read freedesktop notifications and format them as strings"
license       = "MIT"
srcDir        = "src"
bin           = @["notificatcher"]



# Dependencies

requires "nim >= 1.2.6"
requires "dbus"
requires "docopt"
requires "nimPNG"
