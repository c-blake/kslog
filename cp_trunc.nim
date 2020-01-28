import os, posix, times

proc cp_trunc*(src: string, dst: string, pid: Pid=0, verbose=false): int =
  ## ``cp_trunc`` copies ``src`` to ``dst`` (both paths to regular files),
  ## SIGSTOPs ``pid`` to ensure it stops appending, copies any new data,
  ## truncates ``src`` to 0 and SIGCONTs ``pid``.  This is nice for rotating a
  ## log file being actively appended to by a known ``pid`` (via O_APPEND).
  ## Simpler approaches cannot ensure that no data is missed (from the brief
  ## time between the end of the first copy and truncation).  Zero return
  ## means everything went as planned.

  template fail(msg: string, eno: cint, rv: int) =
    stderr.write msg & ": " & $strerror(eno) & "\n"
    return rv

  template resume_fail(pid: Pid, msg: string, eno: cint, rv: int) =
    let e = eno
    if pid != 0: discard kill(pid, SIGCONT)
    fail msg, e, rv

  if pid != 0 and kill(pid, 0) == -1 and errno == EPERM:  #signal perm check
    fail "cannot signal " & $pid, errno, 2  #(Also proceed if pid doesn't exist)
  var buffer = newSeq[char](16000)
  let buf = buffer[0].addr.pointer
  let siz = 16000.csize
  let sfd = open(src, O_RDWR)               #Source read-write (since we trunc)
  if sfd == -1: fail "open(\"" & src & "\")", errno, 3
  defer: discard close(sfd)
  var stS: Stat; discard fstat(sfd, stS)
  if not S_ISREG(stS.st_mode): fail src & " is not a regular file", 0, 4
  let dfd = open(dst, O_CREAT or O_TRUNC or O_WRONLY, 0o666) #Make Destination
  if dfd == -1: fail "open(\"" & dst & "\")", errno, 5
  defer: discard close(dfd)
  var stD: Stat; discard fstat(dfd, stD)
  if not S_ISREG(stD.st_mode): fail dst & " is not a regular file", 0, 6
  if verbose: echo "copying " & src & " -> " & dst
  while true:                               #Copy bytes until we run out
    let nR = read(sfd, buf, siz)
    if nR > 0:
      let nW = write(dfd, buf, nR)          #May run out of space for dst
      if nW != nR: fail "write dst", errno, 7
    if nR != siz: break
  var t0: float                             #Maybe report pause time
  if pid != 0:
    if verbose:
      echo "pausing " & $pid
      t0 = epochTime()
    discard kill(pid, SIGSTOP)              #Pause writer (or barrel onward
                                            #..since writer is now gone).
    while true:                             #Now copy any NEW data
      let nR = read(sfd, buf, siz)          #This loop will almost always be
      if nR > 0:                            #..just 1 read & 1 write, but we
        let nW = write(dfd, buf, nR)        #..code it for rapid append cases.
        if nW != nR: resume_fail pid, "write dst", errno, 8
      if nR != siz: break
  if ftruncate(sfd, 0) != 0:                #Copied all data: Truncate src!
    resume_fail pid, "ftruncate", errno, 9
  if pid != 0:
    discard kill(pid, SIGCONT)              #Resume writer, now appending from 0
    if verbose:
      let dt = $((epochTime() - t0) * 1e3) & " millisec"
      echo "truncated \"" & src & "\"; resumed " & $pid & " after " & dt

when isMainModule:
  import cligen
  dispatch(cp_trunc, cmdName="cp-trunc",
           help={"src"    : "source path to copy & truncate",
                 "dst"    : "destination path of copy",
                 "pid"    : "pid to pause during tail copy (0=>no pause)",
                 "verbose": "print activity" })
