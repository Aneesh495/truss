/*
 * Truss 5G UPF & Packet Processing Fabric
 * Structured Logging Subsystem
 */

primitive LogLevelTrace
  fun string(): String => "TRACE"
  fun priority(): U8 => 0

primitive LogLevelDebug
  fun string(): String => "DEBUG"
  fun priority(): U8 => 1

primitive LogLevelInfo
  fun string(): String => "INFO"
  fun priority(): U8 => 2

primitive LogLevelWarn
  fun string(): String => "WARN"
  fun priority(): U8 => 3

primitive LogLevelError
  fun string(): String => "ERROR"
  fun priority(): U8 => 4

primitive LogLevelFatal
  fun string(): String => "FATAL"
  fun priority(): U8 => 5

type LogLevel is
  ( LogLevelTrace
  | LogLevelDebug
  | LogLevelInfo
  | LogLevelWarn
  | LogLevelError
  | LogLevelFatal )

actor Logger
  """
  Thread-safe asynchronous structured logger actor for the UPF runtime.
  """
  let _out: OutStream
  var _min_level: LogLevel

  new create(out: OutStream, min_level: LogLevel = LogLevelInfo) =>
    _out = out
    _min_level = min_level

  be set_level(level: LogLevel) =>
    _min_level = level

  be trace(subsystem: String, msg: String) =>
    _log(LogLevelTrace, subsystem, msg)

  be debug(subsystem: String, msg: String) =>
    _log(LogLevelDebug, subsystem, msg)

  be info(subsystem: String, msg: String) =>
    _log(LogLevelInfo, subsystem, msg)

  be warn(subsystem: String, msg: String) =>
    _log(LogLevelWarn, subsystem, msg)

  be err(subsystem: String, msg: String) =>
    _log(LogLevelError, subsystem, msg)

  be fatal(subsystem: String, msg: String) =>
    _log(LogLevelFatal, subsystem, msg)

  fun ref _log(level: LogLevel, subsystem: String, msg: String) =>
    if level.priority() >= _min_level.priority() then
      let ts = MonotonicClock.nanos()
      _out.print("[" + ts.string() + " ns] [" + level.string() + "] [" + subsystem + "] " + msg)
    end
