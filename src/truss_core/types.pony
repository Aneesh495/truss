/*
 * Truss 5G UPF & Packet Processing Fabric
 * Core Type Definitions, Capabilities, and Enumerations
 */

use "format"

primitive AccessInterface
  fun string(): String => "Access (N3/RAN)"
  fun id(): U8 => 0

primitive CoreInterface
  fun string(): String => "Core (N6/DN)"
  fun id(): U8 => 1

primitive SgiInterface
  fun string(): String => "Sgi-LAN"
  fun id(): U8 => 2

primitive InternalInterface
  fun string(): String => "Internal (N9)"
  fun id(): U8 => 3

type NetworkInterface is
  ( AccessInterface
  | CoreInterface
  | SgiInterface
  | InternalInterface )

primitive GateOpen
  fun string(): String => "OPEN"
  fun id(): U8 => 0

primitive GateClosed
  fun string(): String => "CLOSED"
  fun id(): U8 => 1

type GateStatus is (GateOpen | GateClosed)

primitive ForwardingActionForw
  fun string(): String => "FORW"
  fun id(): U8 => 0x02

primitive ForwardingActionDrop
  fun string(): String => "DROP"
  fun id(): U8 => 0x01

primitive ForwardingActionBuff
  fun string(): String => "BUFF"
  fun id(): U8 => 0x04

primitive ForwardingActionNocp
  fun string(): String => "NOCP"
  fun id(): U8 => 0x08

primitive ForwardingActionDupl
  fun string(): String => "DUPL"
  fun id(): U8 => 0x10

type ForwardingAction is
  ( ForwardingActionForw
  | ForwardingActionDrop
  | ForwardingActionBuff
  | ForwardingActionNocp
  | ForwardingActionDupl )

primitive OuterHeaderGtpUUdpIpv4
  fun description(): String => "GTP-U/UDP/IPv4"
  fun bit_flag(): U16 => 0x0100

primitive OuterHeaderGtpUUdpIpv6
  fun description(): String => "GTP-U/UDP/IPv6"
  fun bit_flag(): U16 => 0x0200

primitive OuterHeaderUdpIpv4
  fun description(): String => "UDP/IPv4"
  fun bit_flag(): U16 => 0x0400

primitive OuterHeaderUdpIpv6
  fun description(): String => "UDP/IPv6"
  fun bit_flag(): U16 => 0x0800

primitive CauseRequestAccepted
  fun code(): U8 => 1
  fun string(): String => "Request Accepted"

primitive CauseRequestRejected
  fun code(): U8 => 64
  fun string(): String => "Request Rejected"

primitive CauseSessionContextNotFound
  fun code(): U8 => 65
  fun string(): String => "Session Context Not Found"

primitive CauseMandatoryIeMissing
  fun code(): U8 => 66
  fun string(): String => "Mandatory IE Missing"

primitive CauseConditionalIeMissing
  fun code(): U8 => 67
  fun string(): String => "Conditional IE Missing"

primitive CauseRuleCreationModificationFailed
  fun code(): U8 => 69
  fun string(): String => "Rule Creation/Modification Failed"

primitive CauseSystemFailure
  fun code(): U8 => 72
  fun string(): String => "System Failure"

type PfcpCause is
  ( CauseRequestAccepted
  | CauseRequestRejected
  | CauseSessionContextNotFound
  | CauseMandatoryIeMissing
  | CauseConditionalIeMissing
  | CauseRuleCreationModificationFailed
  | CauseSystemFailure )

class val Ipv4Address
  """
  Immutable IPv4 address stored as big-endian 32-bit unsigned integer.
  """
  let raw: U32

  new val create(raw': U32) =>
    raw = raw'

  new val from_octets(o1: U8, o2: U8, o3: U8, o4: U8) =>
    raw = (o1.u32() << 24) or (o2.u32() << 16) or (o3.u32() << 8) or o4.u32()

  new val parse(s: String)? =>
    var parts = s.split(".")
    if parts.size() != 4 then error end
    let o1 = parts(0)?.u8()?
    let o2 = parts(1)?.u8()?
    let o3 = parts(2)?.u8()?
    let o4 = parts(3)?.u8()?
    raw = (o1.u32() << 24) or (o2.u32() << 16) or (o3.u32() << 8) or o4.u32()

  fun string(): String =>
    let o1 = (raw >> 24) and 0xFF
    let o2 = (raw >> 16) and 0xFF
    let o3 = (raw >> 8) and 0xFF
    let o4 = raw and 0xFF
    o1.string() + "." + o2.string() + "." + o3.string() + "." + o4.string()

  fun octet1(): U8 => ((raw >> 24) and 0xFF).u8()
  fun octet2(): U8 => ((raw >> 16) and 0xFF).u8()
  fun octet3(): U8 => ((raw >> 8) and 0xFF).u8()
  fun octet4(): U8 => (raw and 0xFF).u8()

  fun matches_prefix(prefix: Ipv4Address, mask_len: U8): Bool =>
    if mask_len == 0 then return true end
    if mask_len > 32 then return false end
    let mask: U32 = if mask_len == 32 then
      0xFFFFFFFF
    else
      let one: U64 = 1
      not ((one << (32 - mask_len.u64())) - 1).u32()
    end
    (raw and mask) == (prefix.raw and mask)

class val Flow5Tuple
  """
  Represents IP 5-tuple for Packet Detection Rule (PDR) SDF filtering.
  """
  let protocol: U8
  let src_ip: Ipv4Address
  let dst_ip: Ipv4Address
  let src_port_min: U16
  let src_port_max: U16
  let dst_port_min: U16
  let dst_port_max: U16

  new val create(
    proto: U8,
    sip: Ipv4Address,
    dip: Ipv4Address,
    sp_min: U16 = 0,
    sp_max: U16 = 65535,
    dp_min: U16 = 0,
    dp_max: U16 = 65535)
  =>
    protocol = proto
    src_ip = sip
    dst_ip = dip
    src_port_min = sp_min
    src_port_max = sp_max
    dst_port_min = dp_min
    dst_port_max = dp_max

  fun matches(
    proto: U8,
    sip: Ipv4Address,
    dip: Ipv4Address,
    sport: U16,
    dport: U16)
    : Bool
  =>
    if (protocol != 0) and (protocol != proto) then return false end
    if (src_ip.raw != 0) and (src_ip.raw != sip.raw) then return false end
    if (dst_ip.raw != 0) and (dst_ip.raw != dip.raw) then return false end
    if (sport < src_port_min) or (sport > src_port_max) then return false end
    if (dport < dst_port_min) or (dport > dst_port_max) then return false end
    true
