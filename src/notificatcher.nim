import dbus, dbus/loop, dbus/def, tables, strutils, times, os, osproc

const NimblePkgVersion {.strdefine.} = ""

type NotificationFetcher = ref object
  id: uint32
  bus: Bus
  output: File
  fileFormat: string
  runFormat: string
  format: string

proc newNotificationFetcher(bus: Bus, output: File, format, fileFormat, runFormat: string): NotificationFetcher =
  new result
  result.id = 0
  result.bus = bus
  result.output = output
  result.format = format
  result.fileFormat = fileFormat
  result.runFormat = runFormat

proc `$`*(val: DbusValue): string =
  case val.kind
  of dtArray:
    result.add($val.arrayValueType & " " & $val.arrayValue)
  of dtBool:
    result.add($val.boolValue)
  of dtDictEntry:
    result.add($val.dictKey & " " & $val.dictValue)
  of dtDouble:
    result.add($val.doubleValue)
  of dtSignature:
    result.add($cast[string](val.signatureValue))
  of dtUnixFd:
    result.add($val.fdValue)
  of dtInt32:
    result.add($val.int32Value)
  of dtInt16:
    result.add($val.int16Value)
  of dtObjectPath:
    result.add($cast[string](val.objectPathValue))
  of dtUint16:
    result.add($val.uint16Value)
  of dtString:
    result.add($val.stringValue)
  of dtStruct:
    result.add($val.structValues)
  of dtUint64:
    result.add($val.uint64Value)
  of dtUint32:
    result.add($val.uint32Value)
  of dtInt64:
    result.add($val.int64Value)
  of dtByte:
    result.add($val.byteValue)
  of dtVariant:
    result.add($val.variantType & " " & $val.variantValue)
  of dtNull:
    discard
  of dtDict:
    discard

proc toInt(val: DbusValue): uint =
  case val.kind
  of dtBool:
    return val.boolValue.uint
  of dtDouble:
    return val.doubleValue.uint
  of dtInt32:
    return val.int32Value.uint
  of dtInt16:
    return val.int16Value.uint
  of dtUint16:
    return val.uint16Value
  of dtUint64:
    return val.uint64Value.uint
  of dtUint32:
    return val.uint32Value
  of dtInt64:
    return val.int64Value.uint
  of dtByte:
    return val.byteValue
  else:
    return 0

proc splitColon(str: string): seq[string] =
  result.add ""
  var escape = false
  for c in str:
    case c:
    of ':':
      if escape:
        result[^1].add c
        escape = false
      else:
        result.add ""
    of '\\':
      if escape:
        result[^1].add c
        escape = false
      else:
        escape = true
    else:
      result[^1].add c
      escape = false

template formatString(stringToFormat: string, withFile = true): string =
  var str = stringToFormat.multiReplace(("\\n", "\n"), ("\\t", "\t"),
    ("\\a", "\a"), ("\\b", "\b"), ("\\v", "\v"), ("\\f", "\f"),
    ("\\c", "\c"), ("\\e", "\e"), ("{appName}", appName),
    ("{replacesId}", $replacesId), ("{appIcon}", appIcon),
    ("{summary}", summary), ("{body}", body),
    ("{expireTimeout}", $expireTimeout), ("{assignedId}", $self.id),
    ("{actions}", actions.join(", ")))
  when withFile:
    str = str.replace("{file}", fileName)
  let hintsStart = str.find("{hints")
  if hintsStart != -1:
    let
      hintsStop = str.find("}", hintsStart)
      value = str[hintsStart + 1 .. hintsStop - 1].splitColon
    if hints.hasKey value[1]:
      let
        replacement = if value.len == 2:
          $hints[value[1]].variantValue
        else:
          value[min(2 + hints[value[1]].variantValue.toInt, value.high.uint)]
      str = str.replace(str[hintsStart .. hintsStop], replacement)
    else:
      str = str.replace(str[hintsStart .. hintsStop], "")
  let timeStart = str.find("{time")
  if timeStart != -1:
    let
      timeStop = str.find("}", timeStart)
      format = str[timeStart + 1 .. timeStop - 1].splitColon
      time = getTime()
    if format.len > 1:
      str = str.replace(str[timeStart .. timeStop], time.format(format[1]))
    else:
      str = str.replace(str[timeStart .. timeStop], "")
  str = str.unescape("", "")
  str

proc Notify(self: NotificationFetcher, appName: string, replacesId: uint32, appIcon, summary, body: string, actions: seq[string], hints: Table[string, DbusValue], expireTimeout: int32): uint32 =
  if replacesId == 0:
    inc self.id

  try:
    let
      fileName = formatString(self.fileFormat, withFile = false)
      str = formatString(self.format)
    if self.output == nil: createDir(fileName.splitFile.dir)
    let output =
      if self.output != nil: self.output
      else: open(fileName, fmAppend)
    output.writeLine str
    output.flushFile()
    if output != self.output:
      output.close()
    if self.runFormat.len != 0:
      let runCommand = formatString(self.runFormat)
      discard startProcess(runCommand, options = {poDaemon, poEvalCommand})
  except Exception as e:
    stderr.writeLine e.name
    stderr.writeLine e.msg
    stderr.writeLine e.getStackTrace

  return self.id

proc GetCapabilities(self: NotificationFetcher): seq[string] =
  return @["body", "actions"]

proc CloseNotification(self: NotificationFetcher, id: uint32) =
  self.output.writeLine "id: ", id
  self.output.flushFile()

proc GetServerInformation(self: NotificationFetcher): tuple[name: string, url: string, version: string, number: string] =
  return ("notificatcher", "https://peterme.net", "0.1.0", "1")

proc closeNotification(self: NotificationFetcher, id, reason: uint32) =
  var msg = makeSignal("/org/freedesktop/Notifications", "org.freedesktop.Notifications", "NotificationClosed")
  msg.append(id)
  msg.append(reason)
  discard self.bus.sendMessage msg

proc invokeAction(self: NotificationFetcher, id: uint32, action: string) =
  var msg = makeSignal("/org/freedesktop/Notifications", "org.freedesktop.Notifications", "ActionInvoked")
  msg.append(id)
  msg.append(action)
  discard self.bus.sendMessage msg

proc asNative*(value: DbusValue, native: typedesc[DbusValue]): DbusValue = value

proc getAnyDbusType(native: typedesc[DbusValue]): DbusType = dtVariant

let notificationFetcherDef = newInterfaceDef(NotificationFetcher)

notificationFetcherDef.addMethod(Notify, [("appName", string), ("notificationId", uint32), ("appIcon", string), ("summary", string), ("body", string), ("actions", seq[string]), ("hints", Table[string, DbusValue]), ("expireTimeout", int32)], [("id", uint32)])
notificationFetcherDef.addMethod(GetCapabilities, [], [("capabilities", seq[string])])
notificationFetcherDef.addMethod(CloseNotification, [("id", uint32)], [])
notificationFetcherDef.addMethod(GetServerInformation, [], [("name", string), ("url", string), ("version", string), ("number", string)])

template setup(output: File, format = "nil", fileFormat, run = "") =
  let bus {.inject.} = getBus(dbus.DBUS_BUS_SESSION)

  let notificationFetcher {.inject.} = newNotificationFetcher(bus, output, format, fileFormat, run)
  let notificationFetcherObj = newObjectImpl(bus)
  notificationFetcherObj.addInterface("org.freedesktop.Notifications", notificationFetcherDef, notificationFetcher)

  bus.requestName("org.freedesktop.Notifications")
  bus.registerObject("/org/freedesktop/Notifications".ObjectPath, notificationFetcherObj)

proc sendClose(id, reason: uint32) =
  setup(stdout)
  notificationFetcher.closeNotification(id, reason)

proc sendAction(id: uint32, actionKey: string) =
  setup(stdout)
  notificationFetcher.invokeAction(id, actionKey)

proc default(format, file, run: string) =
  var
    fmt =
      if format == "nil": "{appName}: {summary} ({hints:urgency:low:normal:critical})"
      else: format
    isFileFormat = (file.multiReplace(("{appName}", ""), ("{replacesId}", ""),
      ("{appIcon}", ""), ("{summary}", ""), ("{body}", ""),
      ("{expireTimeout}", ""), ("{assignedId}", ""), ("{actions}", "")).len != file.len)
    output =
      if isFileFormat or file.find("{hints") != -1:
        nil
      else:
        if file == "nil": stdout
        else: open(file, fmAppend)
  setup(output, fmt, file, run)
  let mainLoop = MainLoop.create(bus)
  mainLoop.runForever()

let doc = """
Notificatcher """ & NimblePkgVersion & """

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
"""
when isMainModule:
  import docopt
  import docopt/dispatch
  import strutils, sequtils

  let args = docopt(doc, version = "Notificatcher " & NimblePkgVersion)
  if not args.dispatchProc(sendClose, "send", "close") or
    args.dispatchProc(sendAction, "send", "action"):
    default($args["<format>"], $args["--file"], $args["--run"])
