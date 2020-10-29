![Notificatcher logo](https://github.com/PMunch/notificatcher/blob/master/notificatcher.png)

Want to integrate notifications into your Desktop Environment-less Linux
set-up? Look no further!

# What is Notificatcher
Notificatcher is a very simple program that interfaces with dbus to read
Freedesktop notifications and output them in whatever format you specify and run
any program or script you desire.  Whether you want to simply dump them to a
file, or display them in a status bar or use a third-party program to make them
pop up on screen is entirely up to you. Notificatcher is built to do a single
task, and to do it well.

# But why?
It all started when I switched to using Nimdow as my Window Manager. Previously
I've been using i3 and dunst to display notifications, but I was never really
happy with how my notifications appeared with dunst, and I could never remember
the shortcut to read notifications after they were gone. Nimdow, similarily to
dwm and some other light-weight window managers have a status bar that supports
reading the name of the root window and displaying it as a way of being able
to add custom information to the bar. Nimdow also supports ANSI colours for
this bar, so it's easy to customise it with some proper flare. While writing my
status bar script I figured it could be cool if it could simply flash any
recent notification instead of showing system data. This would mean that I no
longer had any annoying pop ups to deal with from dunst, and it would still be
able to grab my attention by blinking. But there was one problem, by simply
using bash I couldn't find any obvious way of getting notifications. There
simply didn't exist an easy and clean solution for just getting notifications
as text. And thus Notificatcher was born! In my set-up I have it set to dump
all notifications to a file, then my status bar bash script will see if the
notifications file is empty, and if not it will flash the last line of the file
along with a count of notifications if there are more than one. I then have two
simple ZSH aliases to clear and read notifications, the latter simply a command
to run `less -r` with the notifications file before clearing it with
`: > /tmp/notifications`.

# Sounds cool, how do I use it?
Easiest way to figure it out is by checking out the help message:

```
Notificatcher 0.3.0
Freedesktop notifications interface. When run without arguments it will simply
output all notifications to the terminal one notification per line. If supplied
with arguments it can also send signals indicating that a notification was
closed, or if an action was performed on the notification. This program will
not do anything in particular with the CloseNotification message.

Usage:
  notificatcher [options] [<format>]
  notificatcher send <id> (close <reason> | action <action_key>)

Options:
  -h --help           Show this screen
  -v --version        Show the version
  -f --file <file>    File to output messages to
  -r --run <program>  Program to run for each notification

If a filename with a replacement pattern is passed, the replacements will be
done for every notification and the notification will be written into that
file. Otherwise the file will be opened right away and be continously written
to as the program runs. If no file is specified, output will go to stdout.
Error messages will always be written to stderr.

The run parameter can be used to specify a program to be run for every
notification. The program string can contain a replacement pattern.

The format that can be supplied is a fairly simple replacement pattern for how
to output the notifications. It will perform these replacements:
{appName} -> The name of the app
{replacesId} -> ID of the notification this notification replaces
{appIcon} -> The name of the icon to use
{summary} -> The summary of the notification
{body} -> The body text of the notification, be warned that this can contain
  newlines so should be somehow wrapped if you want to split the output into
  individual notifications.
{expireTimeout} -> Expiry timeout
{assignedId} -> The ID assigned to this notification
{actions} -> The list of actions, separated by commas
{hints:<hint name>} -> A named hint from the table of hints, after the hint
  name you can also supply a list of string separated by colons which will be
  selected by the hint as an integer, e.g. {hints:urgency:low:normal:critical}.
{time:<format>} -> The time of the notification as recorded upon receival,
  format is a string to format by, as specified in the Nim times module.
{file} -> The name of the output file (this is not available when formatting a
  file name for obvious reasons).

If no format is specified, this format is used:
  {appName}: {summary} ({hints:urgency:low:normal:critical})
```
