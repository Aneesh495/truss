/*
 * Truss 5G UPF & Packet Processing Fabric
 * Nanosecond-Accurate Token Bucket Rate Limiter
 */

class TokenBucket
  """
  High-precision token bucket rate limiter for packet policing and traffic shaping.
  Refills tokens continuously using monotonic nanosecond intervals.
  """
  var _tokens: U64
  let _rate: U64
  let _burst: U64
  var _last_refill_ns: U64

  new create(rate_bytes_per_sec: U64, burst_bytes: U64) =>
    _rate = rate_bytes_per_sec
    _burst = burst_bytes
    _tokens = burst_bytes
    _last_refill_ns = MonotonicClock.nanos()

  fun ref refill(now_ns: U64) =>
    if now_ns > _last_refill_ns then
      let elapsed_ns = now_ns - _last_refill_ns
      let tokens_to_add = ((elapsed_ns.f64() * _rate.f64()) / 1_000_000_000.0).u64()
      if tokens_to_add > 0 then
        _tokens = (_tokens + tokens_to_add).min(_burst)
        _last_refill_ns = now_ns
      end
    end

  fun ref try_consume(requested_bytes: U64, now_ns: U64 = 0): Bool =>
    let ts = if now_ns == 0 then MonotonicClock.nanos() else now_ns end
    refill(ts)
    if _tokens >= requested_bytes then
      _tokens = _tokens - requested_bytes
      true
    else
      false
    end

  fun available_tokens(): U64 => _tokens
  fun rate(): U64 => _rate
  fun burst(): U64 => _burst
