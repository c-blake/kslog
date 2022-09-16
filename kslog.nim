import posix, times, strUtils, parseUtils, tables, cligen

const LOG_PRIMASK = 0x07                #mask to extract priority
const LOG_FACMASK = 0x03f8              #mask to extract facility (w/shr)
proc pri(priFac: int): int {.inline.} =  priFac and LOG_PRIMASK
proc fac(priFac: int): int {.inline.} = (priFac and LOG_FACMASK) shr 3
const LOG_NOTICE  = 5                   #default prio: normal msgs
const LOG_INFO    = 6                   #informational prio
const LOG_USER    = 1 shl 3             #default facility: user-level msgs
const LOG_SYSLOG  = 5 shl 3             #syslog facility: internal msgs
var host    = ""                        #local host name
var keepMax = 8
var files: Table[string, File]

proc parsePrefix(prefix: seq[string]) =
  for pfxPath in prefix:
    let cols = pfxPath.split(',')
    if cols.len > 2: continue
    let path = if cols.len == 2: cols[1] else: cols[0]
    try: files[cols[0]] = open(path, fmAppend, bufSize=0)
    except: stderr.write "could not open ", path, "\n"; discard

let splitChars = { ' ', ':', '[', '/', '\t' }   #add cmd line option?
proc getFile(msg: string): File {.inline.} =    #Route a `msg` to its `File`
  for pfx in msg.split(splitChars):             #A loop, but only want field 0
    if pfx != "":                               #Sometimes can be >1 spaces
      return (try: files[pfx] except: files.getOrDefault("", stderr))

let tmFmt = "MMM dd YYYY HH:mm:ss"
var year5 = getTime().format(" YYYY")           #Include year in all timestamps
proc stampLog(priFac: int; msg: string; kern=false) =
  if priFac.pri > keepMax: return               #Block higher lvls; "resolution"
  let pf = "P" & $priFac.pri & ",F" & $priFac.fac  #Keep priFac, xlated to Pn,Fm
  if not kern and msg.len>15 and msg[3]==' ' and msg[6]==' 'and #MMM dd hh:mm:ss
     msg[9]==':' and msg[12]==':' and msg[15]==' ':             #012345678901234
    let stamp = msg[0..5] & year5 & msg[6..15]  #Includes 1 trailing space char
    let msg   = msg[16..^1]                     #Strip stamp for prefix matching
    let combined = stamp & host & " " & pf & " " & msg & "\n"
    getFile(msg).write combined
  else:                                         #msg has no time; use now..
    let t = getTime()
    year5 = t.format(" YYYY")
    let combined = t.format(tmFmt) & " " & host & " " & pf & " " & msg & "\n"
    getFile(msg).write combined

let selfPfx = "kslog[" & $getpid() & "]: "
proc selfLog(m:string){.inline.} = stampLog(LOG_SYSLOG or LOG_INFO, selfPfx & m)

var quoted = newString(2 * 1024 + 8)            #ctrl char-quoted version
proc splitFmtStampLog(msg: string, kern=false) =
  template checkMaybeRet() {.dirty.} =          #Use after any i increment..
    if i == msg.len:                            #..not already guarded for
      stampLog(priFac, quoted, kern)            #..subsequent msg[i] use.
      return
  quoted.setLen 0                               #<123>ms\ng1[[\0]<456>m\nsg2..]
  var i = 0
  while i < msg.len:
    var priFac = LOG_USER or LOG_NOTICE         #Parse priority-facility number
    if kern:
      quoted.add "kernel: "                     #Give kernel msgs a header
      i += parseInt(msg, priFac, i)             #Also strip cryptic priFac for..
      checkMaybeRet()                           #..later stage translation.
      if msg[i] == ',': i.inc; checkMaybeRet()
    elif msg[i] == '<':
      i += 1 + parseInt(msg, priFac, i + 1)     #Strip <N>-style cryptic priFac
      checkMaybeRet()
      if msg[i] == '>': i.inc
      checkMaybeRet()
    if (priFac and not (LOG_FACMASK or LOG_PRIMASK)) != 0:
      priFac = LOG_USER or LOG_NOTICE
    while i < msg.len and msg[i] != '\0':       #Split msgs at embedded \0s
      if msg[i] == '\n': quoted.add ' '
      elif ord(msg[i]) < 32 and msg[i] != '\t':
        quoted.add '^'
        quoted.add chr(ord('@') + ord(msg[i]))  #^@, ^A, ^B...
      else:
        quoted.add msg[i]
      i.inc                                     #EOdata checked at top of loop
    if i < msg.len and msg[i] == '\0':
      i.inc                                     #EOdata checked at top of loop
    stampLog(priFac, quoted, kern)
    quoted.setLen 0

var buf = newString(1024)               #shared IO buffer
proc readParseLog(fd: cint; rd: var TFdSet; err: string; kern=false): bool =
  if FD_ISSET(fd, rd) != 0:
    buf.setLen 1024
    var sz = read(fd, buf[0].addr, 1024)
    if sz < 0:
      selfLog(err & " errno: " & $errno)
      return false                      #Break main loop on failure
    if sz > 0 and buf[sz - 1] == '\n':
      sz.dec
    buf.setLen sz                       #Set size, then parse/format/log
    splitFmtStampLog(buf, kern)
  return true                           #True = successful operation.

proc die(signo: cint) {.noconv.} =
  selfLog("exiting")
  discard unlink("/run/kslog.pid")      #Will not ordinarily have perm for this.
  quit(0)

proc kslog(name="localhost",prefix= @[",msgs"],dir="/var/log",maxLevel=8): int =
  ## This is the syslog.syslog-only part of a kernel-syslog demon.  It assumes
  ## that file descriptors 0,3 have been set up as by kslog-open.  E.g. use:
  ## "kslog-open -n`hostname` -pkernel -psshd -psu,SUs" will write kernel msgs
  ## to /var/log/kernel, sshd to /var/log/sshd, su to /var/log/SUs, and all
  ## other messages to /var/log/msgs.
  if chdir(dir) != 0: return 1
  host    = name
  keepMax = maxLevel
  prefix.parsePrefix
  selfLog("started")
  discard sigignore(SIGHUP)             #other syslog demons may use this
  signal(SIGINT, die)                   #Since only handlers we install exit..
  signal(SIGTERM, die)                  #..no need to worry about SA_RESTART.
  var rd0: TFdSet                       #set(both)
  FD_ZERO rd0                           #Main Loop: select & dispatch
  FD_SET(0, rd0)
  FD_SET(3, rd0)
  var rd = rd0                          #set(ready to read)
  while select(4, rd.addr, nil, nil, nil) != -1 and
        readParseLog(0, rd, "read from /dev/log") and
        readParseLog(3, rd, "read from /proc/kmsg", true):
    rd = rd0
  die(0)                                #should probably never happen

dispatch(kslog, help={"name"    : "host name tag for every message",
                      "maxLevel": "maximum log level to record",
                      "dir"     : "directory to run out of",
                      "prefix"  : ",-sep FIRST-WORD[,LOGFILE-BASENAME]"})
