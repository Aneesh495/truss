/*
 * Truss 5G UPF & Packet Processing Fabric
 * 3GPP TS 29.244 Information Element (IE) Type Definitions
 */

use "../truss_core"

primitive IeTypeCreatePdr
  fun code(): U16 => 1
primitive IeTypePdi
  fun code(): U16 => 2
primitive IeTypeCreateFar
  fun code(): U16 => 3
primitive IeTypeForwardingParameters
  fun code(): U16 => 4
primitive IeTypeCreateUrr
  fun code(): U16 => 6
primitive IeTypeCreateQer
  fun code(): U16 => 7
primitive IeTypeCause
  fun code(): U16 => 19
primitive IeTypeSourceInterface
  fun code(): U16 => 20
primitive IeTypeFTeid
  fun code(): U16 => 21
primitive IeTypeNetworkInstance
  fun code(): U16 => 22
primitive IeTypeGateStatus
  fun code(): U16 => 25
primitive IeTypeMbr
  fun code(): U16 => 26
primitive IeTypeGbr
  fun code(): U16 => 27
primitive IeTypeOuterHeaderCreation
  fun code(): U16 => 84
primitive IeTypeApplyAction
  fun code(): U16 => 44
primitive IeTypeNodeId
  fun code(): U16 => 60
primitive IeTypeFSeid
  fun code(): U16 => 57
primitive IeTypeRecoveryTimeStamp
  fun code(): U16 => 96
primitive IeTypeOuterHeaderRemoval
  fun code(): U16 => 95
primitive IeTypeVolumeMeasurement
  fun code(): U16 => 66
primitive IeTypeDurationMeasurement
  fun code(): U16 => 67
primitive IeTypeUsageReport
  fun code(): U16 => 78
primitive IeTypeUpdatePdr
  fun code(): U16 => 9
primitive IeTypeUpdateFar
  fun code(): U16 => 10
primitive IeTypeUpdateUrr
  fun code(): U16 => 13
primitive IeTypeUpdateQer
  fun code(): U16 => 14
primitive IeTypeRemovePdr
  fun code(): U16 => 15
primitive IeTypeRemoveFar
  fun code(): U16 => 16
primitive IeTypeRemoveUrr
  fun code(): U16 => 17
primitive IeTypeRemoveQer
  fun code(): U16 => 18

class val NodeIdIe
  """
  Node ID IE (Type 60).
  Node ID Type: 0 = IPv4, 1 = IPv6, 2 = FQDN.
  """
  let node_type: U8
  let ipv4: (Ipv4Address | None)
  let fqdn: String

  new val from_ipv4(ip: Ipv4Address) =>
    node_type = 0
    ipv4 = ip
    fqdn = ""

  new val from_fqdn(name: String) =>
    node_type = 2
    ipv4 = None
    fqdn = name

class val FSeidIe
  """
  Fully Qualified SEID (F-SEID) IE (Type 57).
  """
  let seid: U64
  let ipv4: Ipv4Address

  new val create(seid': U64, ip: Ipv4Address) =>
    seid = seid'
    ipv4 = ip

class val FTeidIe
  """
  Fully Qualified TEID (F-TEID) IE (Type 21).
  """
  let teid: U32
  let ipv4: Ipv4Address
  let choose_id: Bool

  new val create(teid': U32, ip: Ipv4Address, choose: Bool = false) =>
    teid = teid'
    ipv4 = ip
    choose_id = choose

class val OuterHeaderCreationIe
  """
  Outer Header Creation IE (Type 84).
  Bit 8: GTP-U/UDP/IPv4 (0x0100)
  """
  let description: U16
  let teid: U32
  let ipv4: Ipv4Address
  let port: U16

  new val create(teid': U32, ip: Ipv4Address, port': U16 = 2152) =>
    description = 0x0100 /* GTP-U/UDP/IPv4 */
    teid = teid'
    ipv4 = ip
    port = port'

class val GateStatusIe
  """
  Gate Status IE (Type 25).
  UL Gate: 0=Open, 1=Closed.
  DL Gate: 0=Open, 1=Closed.
  """
  let ul_open: Bool
  let dl_open: Bool

  new val create(ul: Bool = true, dl: Bool = true) =>
    ul_open = ul
    dl_open = dl

class val BitRateIe
  """
  MBR or GBR Bitrate representation (uplink and downlink bps).
  """
  let ul_bps: U64
  let dl_bps: U64

  new val create(ul: U64, dl: U64) =>
    ul_bps = ul
    dl_bps = dl
