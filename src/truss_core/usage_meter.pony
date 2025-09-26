/*
 * Truss 5G UPF & Packet Processing Fabric
 * 3GPP TS 29.244 Usage Reporting Rule (URR) Metering & Accounting
 */

primitive TriggerPeriodic
  fun string(): String => "Periodic Reporting"
  fun bit_flag(): U32 => 0x01

primitive TriggerVolumeThreshold
  fun string(): String => "Volume Threshold"
  fun bit_flag(): U32 => 0x02

primitive TriggerTimeThreshold
  fun string(): String => "Time Threshold"
  fun bit_flag(): U32 => 0x04

primitive TriggerTermination
  fun string(): String => "Termination / Session Deletion"
  fun bit_flag(): U32 => 0x08

type UsageReportTrigger is
  ( TriggerPeriodic
  | TriggerVolumeThreshold
  | TriggerTimeThreshold
  | TriggerTermination )

class val VolumeMeasurement
  let total_bytes: U64
  let uplink_bytes: U64
  let downlink_bytes: U64
  let total_packets: U64
  let uplink_packets: U64
  let downlink_packets: U64

  new val create(
    tb: U64,
    ub: U64,
    db: U64,
    tp: U64,
    up: U64,
    dp: U64)
  =>
    total_bytes = tb
    uplink_bytes = ub
    downlink_bytes = db
    total_packets = tp
    uplink_packets = up
    downlink_packets = dp

class val UsageReport
  let urr_id: U32
  let trigger: UsageReportTrigger
  let volume: VolumeMeasurement
  let duration_seconds: U64
  let timestamp_ns: U64

  new val create(
    id': U32,
    trig': UsageReportTrigger,
    vol': VolumeMeasurement,
    dur': U64,
    ts': U64)
  =>
    urr_id = id'
    trigger = trig'
    volume = vol'
    duration_seconds = dur'
    timestamp_ns = ts'

class UsageMeter
  """
  Accumulates packet traffic volume and time duration for a subscriber session.
  Detects threshold crossings and generates 3GPP compliant usage reports.
  """
  let _urr_id: U32
  let _vol_threshold: U64
  let _time_threshold_sec: U64
  var _total_bytes: U64 = 0
  var _uplink_bytes: U64 = 0
  var _downlink_bytes: U64 = 0
  var _total_packets: U64 = 0
  var _uplink_packets: U64 = 0
  var _downlink_packets: U64 = 0
  var _bytes_since_report: U64 = 0
  let _start_time_ns: U64
  var _last_report_ns: U64

  new create(urr_id': U32, vol_threshold': U64 = 0, time_threshold_sec': U64 = 0) =>
    _urr_id = urr_id'
    _vol_threshold = vol_threshold'
    _time_threshold_sec = time_threshold_sec'
    _start_time_ns = MonotonicClock.nanos()
    _last_report_ns = _start_time_ns

  fun ref record_uplink(packet_bytes: U64): (UsageReport | None) =>
    _uplink_bytes = _uplink_bytes + packet_bytes
    _total_bytes = _total_bytes + packet_bytes
    _uplink_packets = _uplink_packets + 1
    _total_packets = _total_packets + 1
    _bytes_since_report = _bytes_since_report + packet_bytes
    _check_thresholds()

  fun ref record_downlink(packet_bytes: U64): (UsageReport | None) =>
    _downlink_bytes = _downlink_bytes + packet_bytes
    _total_bytes = _total_bytes + packet_bytes
    _downlink_packets = _downlink_packets + 1
    _total_packets = _total_packets + 1
    _bytes_since_report = _bytes_since_report + packet_bytes
    _check_thresholds()

  fun ref _check_thresholds(): (UsageReport | None) =>
    let now = MonotonicClock.nanos()

    /* Check volume threshold */
    if (_vol_threshold > 0) and (_bytes_since_report >= _vol_threshold) then
      return _generate_report(TriggerVolumeThreshold, now)
    end

    /* Check time threshold */
    if _time_threshold_sec > 0 then
      let elapsed_sec = (now - _last_report_ns) / 1_000_000_000
      if elapsed_sec >= _time_threshold_sec then
        return _generate_report(TriggerTimeThreshold, now)
      end
    end

    None

  fun ref generate_final_report(): UsageReport =>
    _generate_report(TriggerTermination, MonotonicClock.nanos())

  fun ref _generate_report(trig: UsageReportTrigger, now: U64): UsageReport =>
    let dur = (now - _start_time_ns) / 1_000_000_000
    let vol = VolumeMeasurement(
      _total_bytes,
      _uplink_bytes,
      _downlink_bytes,
      _total_packets,
      _uplink_packets,
      _downlink_packets)
    _bytes_since_report = 0
    _last_report_ns = now
    UsageReport(_urr_id, trig, vol, dur, now)

  fun urr_id(): U32 => _urr_id
  fun total_bytes(): U64 => _total_bytes
  fun uplink_bytes(): U64 => _uplink_bytes
  fun downlink_bytes(): U64 => _downlink_bytes
  fun total_packets(): U64 => _total_packets
