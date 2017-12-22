import discover
import strutils
import nativesockets
import net
import streams
import strformat
import times
import patty
import tables
import future

type
  Host = ref object
    id: uint32
    name: string
    ip: string
    data: string # List of "K:V\n" pairs.

  HostTable = Table[uint32, Host]

variant MaybeHost:
  NoHost
  Known(h: Host)
  Unknown(id: uint32)

type
  Lang* = enum C, Cxx, ObjC, Custom

  MsgKind = enum
    Login
    GetCS
    JobBegin
    JobDone
    LocalJobBegin
    LocalJobDone
    Stats

  Msg = object
    host: MaybeHost
    jobId: uint32 # in everything except Stats and Login
    case kind: MsgKind
    of Login, LocalJobDone: discard
    of Stats:
      msg: string
    of JobBegin:
      remoteStartTime: Time
    of LocalJobBegin:
      localStartTime: Time
      file: string
    of JobDone:
      realMsec, userMsec, sysMsec, pageFaults: uint32
      inRaw, outRaw, inComp, outComp: uint32
      exitCode: int32
      isFromServer:bool
    of GetCS:
      filename: string
      lang: Lang

proc startTime(m: Msg): Time =
  if m.kind == LocalJobBegin:
    m.localStartTime
  else:
    m.remoteStartTime # throws if kind != JobBegin

proc toMaybeHost(id: uint32): MaybeHost = Unknown(id)
proc toMaybeHost(h: Host): MaybeHost = Known(h)

proc `$`(mh: MaybeHost): string =
  match mh:
    NoHost: "(none)"
    Unknown(id): $id
    Known(h): fmt"{h.name.escape}@{h.ip}"

proc updateHost(hosts: var HostTable, stats: Msg) =
  assert stats.kind == Stats
  if stats.host.id notin hosts:
    echo "new host ", stats.host.id
    hosts[stats.host.id] = Host(id: stats.host.id)
  hosts.withValue(stats.host.id, value) do:
    value.data = stats.msg
    for line in stats.msg.splitLines:
      let kv = line.split(':')
      if kv[0] == "Name": value.name = kv[1]
      elif kv[0] == "IP": value.ip = kv[1]

proc getHost(hosts: HostTable, id: uint32): MaybeHost =
  let h = hosts.getOrDefault(id)
  if h != nil:
    Known(h)
  else:
    echo "cant find host ", id
    Unknown(id)

proc send(sock: Socket, u: uint32) =
  var buf = u.htonl
  assert sock.send(addr buf, sizeof buf) == 4

proc recvU32(sock: Socket): uint32 =
  assert sock.recv(addr result, sizeof result) == sizeof result
  result = result.htonl

proc login(sched: Socket) =
  discard sched.recvU32 # TODO negotiate
  sched.send(PROTOCOL_VERSION.uint32 shl 24)
  discard sched.recvU32
  sched.send(PROTOCOL_VERSION.uint32 shl 24)
  sched.send(4u32)
  sched.send('R'.uint32) # R is login?

proc readMsg(sock: Socket): string =
  # TODO handle close cleanly
  let size = sock.recvU32.int
  result = newStringOfCap(size)
  assert sock.recv(result, size) == size

proc readIceNum(buf: Stream): uint32 = buf.readUint32.htonl
proc readIceStr(buf: Stream): string =
  let strLen = buf.readIceNum - 1 # wire size include NUL byte.
  result = buf.readStr(strLen.int)
  assert buf.readChar() == '\0'

proc parseMsg(buf: Stream): Msg =
  var rawKind = buf.readIceNum

  result.kind = case rawKind.char
    of 'O': LocalJobDone
    of 'R': Login
    of 'S': GetCs
    of 'T': JobBegin
    of 'U': JobDone
    of 'V': LocalJobBegin
    of 'W': Stats
    else: (echo fmt"Got an unknown message kind: {rawKind}"; Login)

  defer:
    let ex = getCurrentException()
    if ex != nil:
      ex.msg &= fmt" while parsing a {result.kind} message ({rawKind}|{rawKind.char})"
  case result.kind
  of Login:
    echo "Why is scheduler logging in to us?"
    return
  of LocalJobDone:
    result.jobId = buf.readIceNum
  of Stats:
    result.host = buf.readIceNum.toMaybeHost
    result.msg = buf.readIceStr
  of JobBegin:
    result.jobId = buf.readIceNum
    result.remoteStartTime = buf.readIceNum.int.fromUnix
    result.host = buf.readIceNum.toMaybeHost
  of LocalJobBegin:
    result.host = buf.readIceNum.toMaybeHost
    result.jobId = buf.readIceNum
    result.localStartTime = buf.readIceNum.int.fromUnix
    result.file = buf.readIceStr
  of JobDone:
    result.jobId = buf.readIceNum
    result.exitCode = cast[int32](buf.readIceNum)
    result.realMsec = buf.readIceNum
    result.userMsec = buf.readIceNum
    result.sysMsec = buf.readIceNum
    result.pageFaults = buf.readIceNum
    result.inComp = buf.readIceNum
    result.inRaw = buf.readIceNum
    result.outComp = buf.readIceNum
    result.outRaw = buf.readIceNum
    result.isFromServer = (buf.readIceNum and 1u32) == 0
  of GetCS:
    result.filename = buf.readIceStr
    result.lang = buf.readIceNum.Lang
    result.jobId = buf.readIceNum
    result.host = buf.readIceNum.toMaybeHost
    
  assert buf.atEnd()

when isMainModule:
  let schedInfo = getScheduler()
  let sched = dial(schedInfo.ip, schedInfo.port)
  sched.setSockOpt(OptKeepAlive, true)
  sched.login()

  var hostTable: HostTable = initTable[uint32, Host]()

  while true:
    var buf = sched.readMsg().newStringStream()
    if buf.atEnd: break

    var msg = buf.parseMsg
    if msg.kind == Stats:
      hostTable.updateHost(msg)
      echo "Host:{msg.host}\n{msg.msg}\n".fmt
    else:
      if msg.host.kind == MaybeHostKind.Unknown:
        var tmp = hostTable.getHost(msg.host.id)
        msg.host = tmp #tmp works around nim#6960
      echo getTime(), ": ", msg
