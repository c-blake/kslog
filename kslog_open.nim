import os, posix, cligen/osUt, cligen/posixUt
when not declared(stdout): import std/syncio

proc main() =
  let params = commandLineParams()
  if params.len < 1:
    stdout.write("""
This is the super-user part of kslog.  It forks, binds /dev/log (as file
descriptor 0), opens /dev/kmsg (as file descriptor 3) and writes its pid
file to /run/kslog.pid.  Finally, it drops privilege to syslog.syslog and
runs kslog with any passed command parameters.  Due to dropping privs,
kslog itself cannot remove /run/kslog.pid (but process table checks work).
""")
    quit(0)

  if fork() != 0: quit(0)                       #Eh, exit 0 even on failed fork
  discard close(0)                              #liberate file descrip 0
  let dfd = socket(AF_UNIX, SOCK_DGRAM, 0)
  if dfd != SocketHandle(0):
    stderr.write "cannot make a socket or get fd 0\n"
    quit(1)

  var uds: Sockaddr_un                          #bind new socket to /dev/log
  uds.sun_family = AF_UNIX.TSa_Family
  let pathVal = "/dev/log"                      #+ 1 below copies \0
  copyMem uds.sun_path[0].addr, pathVal[0].unsafeAddr, pathVal.len + 1
  discard unlink(cast[cstring](uds.sun_path[0].addr))  #liberate path name
  if bindSocket(dfd, cast[ptr SockAddr](uds.addr), uds.sizeof.SockLen) < 0:
    stderr.write "cannot bind socket to /dev/log\n"
    quit(2)

  discard chmod("/dev/log".cstring, 0o666)      #Want all to be able to syslog

  discard close(3)            #only 0,1,2 should be open, but right fd matters
  let kfd = open("/dev/kmsg", O_RDONLY)         #Get handle on kmsg
  if kfd != 3:
    stderr.write "cannot open /dev/kmsg or get fd 3\n"
    quit(3)

  let pidFile = "/run/kslog.pid"                #Is this ever named anything
  discard unlink(pidFile.cstring)               #..else?  Could parameterize,
  writeNumberToFile(pidFile, getpid().int)      #..but not great to let root
  discard chmod(pidFile.cstring, 0o644)         #..clobber user-spec files. ;)

  if not dropPrivilegeTo("syslog", "syslog"):   #Drop privileges->syslog.syslog
    stderr.write "cannot drop privileges. Not root? No syslog user/group?\n"
    quit(4)

  let arg0 = "kslog"                            #Run the main parser-log-writer
  let argv = allocCStringArray(@[ arg0 ] & params)
  discard execvp(arg0.cstring, argv)
  stderr.write "cannot exec kslog\n"
  quit(5)

main()
