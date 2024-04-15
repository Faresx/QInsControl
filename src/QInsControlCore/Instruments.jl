abstract type Instrument end
abstract type InstrAttr end

@kwdef mutable struct VISAInstrAttr <: InstrAttr
    timeoutq::Real = 6
    querydelay::Real = 0
    termchar::Char = '\n'
end

@kwdef mutable struct SerialInstrAttr <: InstrAttr
    baudrate::Integer = 9600
    mode::SPMode = SP_MODE_READ_WRITE
    ndatabits::Integer = 8
    parity::SPParity = SP_PARITY_NONE
    nstopbits::Integer = 1
    rts::SPrts = SP_RTS_OFF
    cts::SPcts = SP_CTS_IGNORE
    dtr::SPdtr = SP_DTR_OFF
    dsr::SPdsr = SP_DSR_IGNORE
    xonxoff::SPXonXoff = SP_XONXOFF_DISABLED
    timeoutw::Real = 6
    timeoutr::Real = 6
    timeoutq::Real = 6
    querydelay::Real = 0
    termchar::Char = '\n'
end

@kwdef mutable struct TCPSocketInstrAttr <: InstrAttr
    timeoutq::Real = 6
    querydelay::Real = 0
    termchar::Char = '\n'
end

@kwdef mutable struct VirtualInstrAttr <: InstrAttr
end

struct VISAInstr <: Instrument
    name::String
    addr::String
    geninstr::GenericInstrument
    attr::VISAInstrAttr
end

struct SerialInstr <: Instrument
    name::String
    addr::String
    port::String
    sp::SerialPort
    connected::Ref{Bool}
    attr::SerialInstrAttr
end

struct TCPSocketInstr <: Instrument
    name::String
    addr::String
    ip::IPv4
    port::Int
    sock::Ref{TCPSocket}
    connected::Ref{Bool}
    attr::TCPSocketInstrAttr
end

@kwdef struct VirtualInstr <: Instrument
    name::String = "VirtualInstr"
    addr::String = "VirtualAddress"
    attr::VirtualInstrAttr = VirtualInstrAttr()
end

"""
    instrument(name, addr)

generate an instrument with (name, addr) which automatically determines the type of this instrument.
"""
function instrument(name, addr; attr=nothing)
    if occursin("SERIAL", addr)
        try
            _, portstr = split(addr, "::")
            setattr = isnothing(attr) || !isa(attr, SerialInstrAttr) ? SerialInstrAttr() : attr
            return SerialInstr(name, addr, portstr, SerialPort(portstr), false, setattr)
        catch e
            @error "address $addr is not valid" execption = e
            setattr = isnothing(attr) || !isa(attr, VISAInstrAttr) ? VISAInstrAttr() : attr
            return VISAInstr(name, addr, GenericInstrument(), setattr)
        end
    elseif occursin("TCPSOCKET", addr)
        try
            _, ipstr, portstr, _ = split(addr, "::")
            port = parse(Int, portstr)
            ip = try
                IPv4(ipstr)
            catch
            end
            isnothing(ip) && (ip = try
                IPv6(ipstr)
            catch
            end)
            return if isnothing(ip)
                setattr = isnothing(attr) || !isa(attr, VISAInstrAttr) ? VISAInstrAttr() : attr
                VISAInstr(name, addr, GenericInstrument(), setattr)
            else
                setattr = isnothing(attr) || !isa(attr, TCPSocketInstrAttr) ? TCPSocketInstrAttr() : attr
                TCPSocketInstr(name, addr, ip, port, TCPSocket(), false, setattr)
            end
        catch e
            @error "address $addr is not valid" execption = e
            setattr = isnothing(attr) || !isa(attr, VISAInstrAttr) ? VISAInstrAttr() : attr
            return VISAInstr(name, addr, GenericInstrument(), setattr)
        end
    elseif name == "VirtualInstr"
        return VirtualInstr()
    elseif occursin("VIRTUAL", split(addr, "::")[1])
        setattr = isnothing(attr) || !isa(attr, VirtualInstrAttr) ? VirtualInstrAttr() : attr
        return VirtualInstr(split(addr, "::")[end], addr, setattr)
    else
        setattr = isnothing(attr) || !isa(attr, VISAInstrAttr) ? VISAInstrAttr() : attr
        return VISAInstr(name, addr, GenericInstrument(), setattr)
    end
end

"""
    connect!(rm, instr)

connect to an instrument with given ResourceManager rm.

    connect!(instr)

same but with auto-generated ResourceManager.
"""
connect!(rm, instr::VISAInstr) = Instruments.connect!(rm, instr.geninstr, instr.addr)
function connect!(_, instr::SerialInstr)
    set_speed(instr.sp, instr.attr.baudrate)
    set_frame(instr.sp; ndatabits=instr.attr.ndatabits, parity=instr.attr.parity, nstopbits=instr.attr.nstopbits)
    set_flow_control(
        instr.sp;
        rts=instr.attr.rts, cts=instr.attr.cts, dtr=instr.attr.dtr, dst=instr.attr.dst, xonxoff=instr.attr.xonxoff
    )
    set_write_timeout(instr.sp, instr.attr.timeoutw)
    set_read_timeout(instr.sp, instr.attr.timeoutr)
    LibSerialPort.open(instr.sp; mode=instr.attr.mode)
    instr.connected[] = true
end
function connect!(_, instr::TCPSocketInstr)
    if !instr.connected[]
        instr.sock[] = Sockets.connect(instr.ip, instr.port)
        instr.connected[] = true
    end
end
connect!(_, ::VirtualInstr) = nothing
connect!(instr::Instrument) = connect!(ResourceManager(), instr)

"""
    disconnect!(instr)

disconnect the instrument.
"""
disconnect!(instr::VISAInstr) = Instruments.disconnect!(instr.geninstr)
function disconnect!(instr::SerialInstr)
    if instr.connected[]
        close(instr.sp)
        instr.connected[] = false
    end
end
function disconnect!(instr::TCPSocketInstr)
    if instr.connected[]
        close(instr.sock[])
        instr.connected[] = false
    end
end
disconnect!(::VirtualInstr) = nothing

global VIASYNC::Bool = false

"""
    write(instr, msg)

write some message string to the instrument.
"""
Base.write(instr::VISAInstr, msg::AbstractString) = (VIASYNC ? writeasync : Instruments.write)(instr.geninstr, string(msg, instr.attr.termchar))
Base.write(instr::SerialInstr, msg::AbstractString) = write(instr.sp, string(msg, instr.attr.termchar))
Base.write(instr::TCPSocketInstr, msg::AbstractString) = println(instr.sock[], string(msg, instr.attr.termchar))
Base.write(::VirtualInstr, ::AbstractString) = nothing

"""
    read(instr)

read the instrument.
"""
Base.read(instr::VISAInstr) = (VIASYNC ? readasync : Instruments.read)(instr.geninstr)
Base.read(instr::SerialInstr) = rstrip(read(instr.sp, String), ['\r', '\n'])
Base.read(instr::TCPSocketInstr) = readline(instr.sock[])
Base.read(::VirtualInstr) = "read"

"""
    query(instr, msg; delay=0)

query the instrument with some message string.
"""
function _query_(instr::Instruments.GenericInstrument, msg; delay=0, timeout=6, errormsg="time out")
    write(instr, msg)
    delay < 0.001 || sleep(delay)
    t = @async read(instr)
    isok = timedwhile(() -> istaskdone(t), timeout)
    return isok ? fetch(t) : error(errormsg)
end
function query(instr::VISAInstr, msg::AbstractString)
    if VIASYNC
        queryasync(instr.geninstr, msg)
    else
        _query_(
            instr.geninstr, msg;
            delay=instr.attr.querydelay, timeout=instr.attr.timeoutq, errormsg="$(instr.addr) time out"
        )
    end
end
function query(instr::SerialInstr, msg::AbstractString)
    write(instr, msg)
    instr.attr.querydelay < 0.001 || sleep(instr.attr.querydelay)
    t = @async read(instr)
    isok = timedwhile(() -> istaskdone(t), instr.attr.timeoutq)
    return isok ? fetch(t) : error("$(instr.addr) time out")
end
function query(instr::TCPSocketInstr, msg::AbstractString)
    write(instr, msg)
    instr.attr.querydelay < 0.001 || sleep(instr.attr.querydelay)
    t = @async read(instr)
    isok = timedwhile(() -> istaskdone(t), instr.attr.timeoutq)
    return isok ? fetch(t) : error("$(instr.addr) time out")
end
query(::VirtualInstr, ::AbstractString) = "query"

"""
    isconnected(instr)

determine if the instrument is connected.
"""
isconnected(instr::VISAInstr) = instr.geninstr.connected
isconnected(instr::SerialInstr) = instr.connected[]
isconnected(instr::TCPSocketInstr) = instr.connected[]
isconnected(::VirtualInstr) = true