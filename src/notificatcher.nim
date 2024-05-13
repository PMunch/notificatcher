import dbus, dbus/loop, dbus/def, tables, strutils, times, os, osproc, nimPNG
import random

const NimblePkgVersion {.strdefine.} = ""

type NotificationFetcher = ref object
  id: uint32
  bus: Bus
  output: File
  fileFormat: string
  closeOutput: File
  closeFileFormat: string
  runFormat: string
  closeRunFormat: string
  closeFormat: string
  format: string
  iconPath: string
  capabilities: seq[string]

proc newNotificationFetcher(bus: Bus, output, closeOutput: File,
    format, closeFormat, fileFormat, closeFileFormat, runFormat, closeRunFormat,
    iconPath: string, capabilities: seq[string]): NotificationFetcher =
  new result
  result.id = 0
  result.bus = bus
  result.output = output
  result.format = format
  result.closeFormat = closeFormat
  result.closeOutput = closeOutput
  result.closeFileFormat = closeFileFormat
  result.fileFormat = fileFormat
  result.runFormat = runFormat
  result.closeRunFormat = closeRunFormat
  result.iconPath = iconPath
  result.capabilities = capabilities

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

template formatString(stringToFormat: string, withFile = true,
    withHints = true): string =
  var str = stringToFormat.multiReplace(("\\n", "\n"), ("\\t", "\t"),
    ("\\a", "\a"), ("\\b", "\b"), ("\\v", "\v"), ("\\f", "\f"),
    ("\\c", "\c"), ("\\e", "\e"), ("{appName}", appName),
    ("{replacesId}", $replacesId), ("{appIcon}", appIcon),
    ("{summary}", summary), ("{body}", body),
    ("{expireTimeout}", $expireTimeout),
    ("{id}", if closesId == 0: $self.id else: $closesId),
    ("{actions}", actions.join(", ")), ("{pid}", $pid))
  when withFile:
    str = str.replace("{file}", fileName)
  when withHints:
    let hintsStart = str.find("{hints")
    if hintsStart != -1:
      let
        hintsStop = str.find("}", hintsStart)
        value = str[hintsStart + 1 .. hintsStop - 1].splitColon
      if hints.hasKey value[1]:
        if savedIcons.hasKey value[1]:
          str = str.replace(str[hintsStart .. hintsStop], savedIcons[value[1]])
        else:
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

proc Notify(self: NotificationFetcher, appName: string, replacesId: uint32,
    appIcon, summary, body: string, actions: seq[string],
    hints: Table[string, DbusValue], expireTimeout: int32): uint32 =
  if replacesId == 0:
    inc self.id

  try:
    var savedIcons: Table[string, string]
    if self.iconPath != "nil":
      for keyName in ["image-data", "image_data", "icon_data"]:
        if hints.hasKey(keyName):
          let
            imageData = hints[keyName].variantValue.structValues
            width = imageData[0].int32Value
            height = imageData[1].int32Value
            rowStride = imageData[2].int32Value
            hasAlpha = imageData[3].boolValue
            bitsPerSample = imageData[4].int32Value
            channels = imageData[5].int32Value
            imageRaw = imageData[6].arrayValue
          var imageArray = newSeq[uint8](width*channels * height)
          for row in 0..<height:
            for column in 0..<width*channels:
              imageArray[row * rowStride + column] =
                imageRaw[row * rowStride + column].byteValue
          let name = rand(int).toHex() & ".png"
          if savePNG(self.iconPath & "/" & name, imageArray,
              if hasAlpha: LCT_RGBA else: LCT_RGB,
              bitsPerSample, width, height).isOk:
            savedIcons[keyName] = "file://" &
              expandFilename(self.iconPath & "/" & name)

    let
      closesId = 0
      fileHasPid = self.fileFormat.contains("{pid}")
      formatHasPid = self.format.contains("{pid}")
      hasPid = formatHasPid or fileHasPid

    template formatFile(): string =
      formatString(self.fileFormat, withFile = false)

    type Step = enum Output, Run, Done
    var
      pid = 0
      fileName = if fileHasPid: "" else: formatFile()
      step = if hasPid: Run else: Output

    while true:
      case step:
      of Output:
        # Write output
        let str = formatString(self.format)
        if fileHasPid: fileName = formatFile()
        if self.output == nil: createDir(fileName.splitFile.dir)
        let output =
          if self.output != nil: self.output
          else: open(fileName, fmAppend)
        output.writeLine str
        output.flushFile()
        if output != self.output:
          output.close()
        step = if hasPid: Done else: Run
      of Run:
        # Launch program
        let runCommand = formatString(self.runFormat)
        if self.runFormat != "nil":
          pid = startProcess(runCommand, options = {poDaemon, poEvalCommand}).processId
        step = if hasPid: Output else: Done
      of Done: break
  except Exception as e:
    stderr.writeLine e.name
    stderr.writeLine e.msg
    stderr.writeLine e.getStackTrace

  return self.id

proc GetCapabilities(self: NotificationFetcher): seq[string] =
  return self.capabilities

proc CloseNotification(self: NotificationFetcher, closesId: uint32) =
  try:
    let
      appName = ""
      replacesId = 0
      appIcon = ""
      summary = ""
      body = ""
      actions: seq[string] = @[]
      expireTimeout = 0
      pid = 0
      fileName =
        formatString(self.fileFormat, withFile = false, withHints = false)
      closeFileName =
        formatString(self.closeFileFormat, withFile = false, withHints = false)
      str = formatString(self.closeFormat, withHints = false)
      output =
        if self.closeOutput != nil: self.closeOutput
        elif self.closeFileFormat != "nil": open(closeFileName, fmAppend)
        else:
          if self.output != nil: self.output
          else: open(fileName, fmAppend)

    output.writeLine str
    output.flushFile()
    if output != self.output:
      output.close()
    if self.closeRunFormat != "nil":
      let closeRunCommand = formatString(self.closeRunFormat, withHints = false)
      discard startProcess(closeRunCommand, options = {poDaemon, poEvalCommand})
  except Exception as e:
    stderr.writeLine e.name
    stderr.writeLine e.msg
    stderr.writeLine e.getStackTrace

proc GetServerInformation(self: NotificationFetcher): tuple[name: string,
    url: string, version: string, number: string] =
  return ("notificatcher", "https://peterme.net", NimblePkgVersion, "1")

proc closeNotification(self: NotificationFetcher, id, reason: uint32) =
  var msg = makeSignal("/org/freedesktop/DBus", "org.freedesktop.Notifications",
    "NotificationClosed")
  msg.append(id)
  msg.append(reason)
  discard self.bus.sendMessage msg

proc invokeAction(self: NotificationFetcher, id: uint32, action: string) =
  var msg = makeSignal("/org/freedesktop/DBus", "org.freedesktop.Notifications",
    "ActionInvoked")
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

template setup(output: File, closeOutput: File = nil, format = "nil",
    closeFormat = "nil", fileFormat = "nil", closeFileFormat = "nil",
    run = "nil", closeRun = "nil", iconPath = "nil",
    capabilities = @["body", "actions", "action-icons"]) =
  let bus {.inject.} = getBus(dbus.DBUS_BUS_SESSION)

  let notificationFetcher {.inject.} = newNotificationFetcher(bus, output,
    closeOutput, format, closeFormat, fileFormat, closeFileFormat, run,
    closeRun, iconPath, capabilities)

proc sendClose(id, reason: uint32) =
  setup(stdout)
  notificationFetcher.closeNotification(id, reason)

proc sendAction(id: uint32, actionKey: string) =
  setup(stdout)
  notificationFetcher.invokeAction(id, actionKey)

proc default(format, file, run, closeRun, iconPath, closeFormat, closeFile: string, capabilities: seq[string]) =
  var
    fmt =
      if format == "nil": "{appName}: {summary} ({hints:urgency:low:normal:critical})"
      else: format
    closeFmt =
      if closeFormat == "nil": "{closesId}"
      else: closeformat
    isFileFormat = (file.multiReplace(("{appName}", ""), ("{replacesId}", ""),
      ("{appIcon}", ""), ("{summary}", ""), ("{body}", ""),
      ("{expireTimeout}", ""), ("{id}", ""), ("{actions}", "")).len != file.len)
    isCloseFileFormat = (closeFile.multiReplace(("{id}", "")).len != closeFile.len)
    output =
      if isFileFormat or file.find("{hints") != -1 or file.find("{time") != -1:
        nil
      else:
        if file == "nil": stdout
        else: open(file, fmAppend)
    closeOutput =
      if isCloseFileFormat or closeFile.find("{hints") != -1 or closeFile.find("{time") != -1:
        nil
      else:
        if closeFile == "nil": output
        else: open(closeFile, fmAppend)
  setup(output, closeOutput, fmt, closeFmt, file, closeFile, run, closeRun, iconPath, capabilities)
  let notificationFetcherObj = newObjectImpl(bus)
  notificationFetcherObj.addInterface("org.freedesktop.Notifications", notificationFetcherDef, notificationFetcher)

  bus.requestName("org.freedesktop.Notifications")
  bus.registerObject("/org/freedesktop/Notifications".ObjectPath, notificationFetcherObj)
  let mainLoop = MainLoop.create(bus)
  mainLoop.runForever()

let doc = """
Notificatcher """ & NimblePkgVersion & """

Freedesktop notifications interface. When run without arguments it will simply
output all notifications to the terminal one notification per line. If supplied
with arguments it can also send signals indicating that a notification was
closed, or if an action was performed on the notification. By specifying a
closeFormat it will also output notification closed messages, if you're
listening to these you should also use the send close functionality of
notificatcher to report back to the parent notification that this was indeed
closed. The same applies if you close messages based on their timeout.

Usage:
  notificatcher [options] [<format>]
  notificatcher send <id> (close <reason> | action <action_key>)

Options:
  -h --help                  Show this screen
  -v --version               Show the version
  -f --file <file>           File to output messages to
  -m --closeFile <file>      File to output close messages to
  -r --run <program>         Program to run for each notification
  -x --closeRun <program>    Program to run for each close message
  -d --closeFormat <format>  How to format notifications that have been closed
  -i --iconPath <path>       The path to store icons in
  -c --capabilities <cap>    A list of capabilities to declare

If a filename with a replacement pattern is passed, the replacements will be
done for every notification and the notification will be written into that
file. Otherwise the file will be opened right away and be continously written
to as the program runs. If no file is specified, output will go to stdout.
Error messages will always be written to stderr.

The run parameter can be used to specify a program to be run for every
notification. The program string can contain a replacement pattern.

The close parameter can be used to specify a pattern for notification close
events. This pattern only supports the id, file, and time replacements.

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
{id} -> The ID assigned to this notification, or in the case of a closed
  notification the ID of the notification to close.
{actions} -> The list of actions, separated by commas
{hints:<hint name>} -> A named hint from the table of hints, after the hint
  name you can also supply a list of strings separated by colons which will be
  selected by the hint as an integer, e.g. {hints:urgency:low:normal:critical}.
  For any of the image-data hints you will get a file URI to a PNG as the
  output instead of a buffer. The icon will be stored in the iconPath, if no
  icon path is set the image-data won't return anything.
{time:<format>} -> The time of the notification as recorded upon receival,
  format is a string to format by, as specified in the Nim times module.
{file} -> The name of the output file (this is not available when formatting a
  file name for obvious reasons).
{pid} -> The process ID if a program was run with --run or --closeRun. Useful if
  you want to kill a program later.

If no format is specified, this format is used for notifications, and nothing is
used for close messages:
  {appName}: {summary} ({hints:urgency:low:normal:critical})

If {pid} is supplied as part of the output filter AND the file filter, then the
program will be launched first (and {file} will be empty in the program filter)
and then the filename will be generated and the output will be done.
If {pid} is supplied as part of the output filter but not the file filter, then
the filename will be generated, the program run (and {file} in the program
filter will now point to a yet to be made file) and then the output will be
written to the file.
If {pid} is supplied as part of the file filter but not the output filter, then
it behaves the same as if appeared in both.
"""
when isMainModule:
  import docopt
  import docopt/dispatch
  import strutils, sequtils

  let args = docopt(doc, version = "Notificatcher " & NimblePkgVersion)
  if not args.dispatchProc(sendClose, "send", "close") or
    args.dispatchProc(sendAction, "send", "action"):
    default($args["<format>"], $args["--file"], $args["--run"],
    $args["--closeRun"], $args["--iconPath"], $args["--closeFormat"],
    $args["--closeFile"], ($(args["--capabilities"])).split(","))
