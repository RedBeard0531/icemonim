# Translated by c2nim from glibc ifaddrs.h with many manual edits.

##  The `getifaddrs' function generates a linked list of these structures.
##    Each element of the list describes one network interface.

import posix
import posix
import future
import ospaths

type
  sockaddr = SockAddr

  ##  At most one of the following two is valid.  If the IFF_BROADCAST
  ##  bit is set in `ifa_flags', then `ifa_broadaddr' is valid.  If the
  ##  IFF_POINTOPOINT bit is set, then `ifa_dstaddr' is valid.
  ##  It is never the case that both these bits are set at once.
  INNER_C_UNION_883504612 {.importc: "no_name", header: "ifaddrs.h", bycopy.} = object {.
      union.}
    ##  Broadcast address of this interface.
    broadaddr {.importc: "ifu_broadaddr".}: ptr sockaddr

    ##  Point-to-point destination address.
    dstaddr {.importc: "ifu_dstaddr".}: ptr sockaddr
  
  ifaddrs* {.importc: "struct ifaddrs", header: "ifaddrs.h", bycopy.} = object
    next* {.importc: "ifa_next".}: ptr ifaddrs ##  Pointer to the next structure.
    name* {.importc: "ifa_name".}: cstring ##  Name of this network interface.
    flags* {.importc: "ifa_flags".}: cuint ##  Flags as from SIOCGIFFLAGS ioctl.
    sockaddr* {.importc: "ifa_addr".}: ptr sockaddr ##  Network address of this interface.
    netmask* {.importc: "ifa_netmask".}: ptr sockaddr ##  Netmask of this interface.
    ifu* {.importc: "ifa_ifu".}: INNER_C_UNION_883504612
    data* {.importc: "ifa_data".}: pointer ##  Address-specific data (may be unused).

##  Create a linked list of `struct ifaddrs' structures, one for each
##  network interface on the host machine.  If successful, store the
##  list in *IFAP and return 0.  On errors, return -1 and set `errno'.
## 
##  The storage returned in *IFAP is allocated dynamically and can
##  only be properly freed by passing it to `freeifaddrs'.
proc getifaddrs_raw(ifap: var ptr ifaddrs): cint {.importc: "getifaddrs",
    header: "ifaddrs.h".}

##  Reclaim the storage allocated by a previous `getifaddrs' call.
proc freeifaddrs(ifa: ptr ifaddrs) {.importc: "freeifaddrs", header: "ifaddrs.h".}
  

# The rest of this file was manually written for nim.

proc broadaddr*(ifa: ptr ifaddrs): ptr sockaddr = ifa.ifu.broadaddr
proc dstaddr*(ifa: ptr ifaddrs): ptr sockaddr = ifa.ifu.dstaddr

## Iterates overall interface addresses.
##
## Warning: addresses are automatically freed after iteration, so be sure to
## copy anything you need before moving on. This also means that you should
## never use this iterator with ``sequtils.toSeq``!
iterator getifaddrs*(): ptr ifaddrs =
  var addrs: ptr ifaddrs
  if getifaddrs_raw(addrs) != 0:
    let err = osLastError()
    raiseOSError(err, "Error getting interface addrs")
  defer: freeifaddrs(addrs)
  while addrs != nil:
    yield addrs
    addrs = addrs.next
