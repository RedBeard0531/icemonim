import net
import nativesockets
import ifaddrs
import strformat
import strutils
import algorithm

type Scheduler* = object
  ip*: string
  port*: Port
  name*: string
  startTime*:uint64
  version*:uint32

const
  NETNAME = "ICECREAM" #TODO make this configurable
  DISCOVER_PORT = 8765.Port
  PROTOCOL_VERSION* = 37

var
  IFF_POINTOPOINT {.importc: "IFF_POINTOPOINT", header:"<net/if.h>".} : cuint
  IFF_BROADCAST {.importc: "IFF_BROADCAST", header:"<net/if.h>".} : cuint

proc getScheduler*: Scheduler =
  let sock = newSocket(sockType=SOCK_DGRAM, protocol=IPPROTO_UDP, buffered=false)
  defer: sock.close()
  sock.setSockOpt(OptBroadcast, true)

  proc sendBroadcast() =
    for ifaddr in getifaddrs():
      if (ifaddr.flags and IFF_POINTOPOINT) != 0 or (ifaddr.flags and IFF_BROADCAST) == 0:
        continue

      if ifaddr.name == nil or ifaddr.sockaddr == nil or ifaddr.sockaddr.sa_family.Domain != AF_INET or
          ifaddr.netmask == nil or ifaddr.broadaddr == nil:
        continue

      var broadaddr = ifaddr.broadaddr.getAddrString
      echo fmt"Broadcasting for scheduler on {ifaddr.name} {broadaddr}:{DISCOVER_PORT}"
      assert sock.sendTo(broadaddr, DISCOVER_PORT, $PROTOCOL_VERSION.char) == 1

  proc getReplies(): seq[Scheduler] =
    result = @[]
    while true:
      var fds = @[sock.getFd]
      if fds.selectRead(2000) == 0:
        if result.len == 0:
          sendBroadcast()
          continue
        break

      var sched: Scheduler
      var buf = ""
      assert sock.recvFrom(buf, 32, sched.ip, sched.port) != 0
      #echo fmt"Got msg from {tup.ip}:{sched.port} |{buf.escape}|"
      if buf.len != 32 or buf[0].ord != PROTOCOL_VERSION + 2:
        continue # ignore weird replies.

      copyMem(addr sched.version, addr buf[1], 4)
      copyMem(addr sched.startTime, addr buf[1+4], 8)
      sched.name = $cstring(addr buf[1+4+8])
      echo fmt"Heard from {sched}"
      if sched.name != NETNAME:
        echo fmt"ignoring because name isn't '{NETNAME}'"
        continue
      result &= sched

  sendBroadcast()
  result = getReplies().sortedByIt((it.version, -int(it.startTime)))[^1]
  echo fmt"Best scheduler is {result.ip}:{result.port}"

when isMainModule:
  discard getScheduler()
