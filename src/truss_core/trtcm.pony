/*
 * Truss 5G UPF & Packet Processing Fabric
 * RFC 2698 Two-Rate Three-Color Marker (trTCM)
 */

primitive ColorGreen
  fun string(): String => "GREEN"
  fun id(): U8 => 0

primitive ColorYellow
  fun string(): String => "YELLOW"
  fun id(): U8 => 1

primitive ColorRed
  fun string(): String => "RED"
  fun id(): U8 => 2

type TrtcmColor is (ColorGreen | ColorYellow | ColorRed)

class TrtcmMeter
  """
  Implementation of RFC 2698 Two-Rate Three-Color Marker for 5G QoS Flow
  Enforcement Rules (QER). Classifies traffic into Green (conforming),
  Yellow (exceeding CIR but under PIR), and Red (violating PIR).
  """
  let _pir: U64
  let _pbs: U64
  let _cir: U64
  let _cbs: U64
  var _tp: U64
  var _tc: U64
  var _last_update_ns: U64

  new create(pir': U64, pbs': U64, cir': U64, cbs': U64) =>
    _pir = pir'
    _pbs = pbs'
    _cir = cir'
    _cbs = cbs'
    _tp = pbs'
    _tc = cbs'
    _last_update_ns = MonotonicClock.nanos()

  fun ref update(now_ns: U64) =>
    if now_ns > _last_update_ns then
      let elapsed_ns = now_ns - _last_update_ns
      let pir_tokens = ((elapsed_ns.f64() * _pir.f64()) / 1_000_000_000.0).u64()
      let cir_tokens = ((elapsed_ns.f64() * _cir.f64()) / 1_000_000_000.0).u64()

      if pir_tokens > 0 then
        _tp = (_tp + pir_tokens).min(_pbs)
      end
      if cir_tokens > 0 then
        _tc = (_tc + cir_tokens).min(_cbs)
      end
      _last_update_ns = now_ns
    end

  fun ref mark(packet_bytes: U64, now_ns: U64 = 0): TrtcmColor =>
    let ts = if now_ns == 0 then MonotonicClock.nanos() else now_ns end
    update(ts)

    if packet_bytes > _tp then
      ColorRed
    elseif packet_bytes > _tc then
      _tp = _tp - packet_bytes
      ColorYellow
    else
      _tp = _tp - packet_bytes
      _tc = _tc - packet_bytes
      ColorGreen
    end

  fun tp(): U64 => _tp
  fun tc(): U64 => _tc
  fun pir(): U64 => _pir
  fun cir(): U64 => _cir
