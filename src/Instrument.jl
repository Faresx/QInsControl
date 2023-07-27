function autodetect()
    addrs = find_resources(CPU)
    for addr in addrs
        manualadd(addr)
    end
end

function manualadd(addr)
    idn = "IDN"
    st = true
    ct = Controller("", addr)
    try
        login!(CPU, ct)
        idn = ct(query, CPU, "*IDN?", Val(:query))
        logout!(CPU, ct)
    catch e
        @error "[$(now())]\n$(mlstr("instrument communication failed!!!"))" instrument_address = addr exception = e
        logout!(CPU, addr)
        for ins in keys(INSTRBUFFERVIEWERS)
            ins == "Others" && continue
            if haskey(INSTRBUFFERVIEWERS[ins], addr)
                delete!(INSTRBUFFERVIEWERS[ins], addr)
            end
        end
        st = false
    end
    if st
        for (ins, cf) in insconf
            if true in occursin.(split(cf.conf.idn, ';'), idn)
                if haskey(INSTRBUFFERVIEWERS[ins], addr)
                    return true
                else
                    push!(INSTRBUFFERVIEWERS[ins], addr => InstrBufferViewer(ins, addr))
                    return true
                end
            end
        end
    end
    if addr != ""
        push!(INSTRBUFFERVIEWERS["Others"], addr => InstrBufferViewer("Others", addr))
    end
    return st
end

function refresh_instrlist()
    if !SYNCSTATES[Int(AutoDetecting)] && !SYNCSTATES[Int(AutoDetectDone)]
        SYNCSTATES[Int(AutoDetecting)] = true
        remote_do(workers()[1], SYNCSTATES) do SYNCSTATES
            errormonitor(@async begin
                try
                    for ins in keys(INSTRBUFFERVIEWERS)
                        ins == "VirtualInstr" && continue
                        empty!(INSTRBUFFERVIEWERS[ins])
                    end
                    autodetect()
                    SYNCSTATES[Int(AutoDetecting)] && (SYNCSTATES[Int(AutoDetectDone)] = true)
                catch e
                    SYNCSTATES[Int(AutoDetecting)] && (SYNCSTATES[Int(AutoDetectDone)] = true)
                    @error mlstr("auto searching failed!!!") exception = e
                end
            end)
        end
        poll_autodetect()
    end
end

function poll_autodetect()
    errormonitor(
        @async begin
            starttime = time()
            while true
                if time() - starttime > 180
                    SYNCSTATES[Int(AutoDetecting)] = false
                    SYNCSTATES[Int(AutoDetectDone)] = false
                    break
                end
                if SYNCSTATES[Int(AutoDetectDone)]
                    instrbufferviewers_remote = remotecall_fetch(() -> INSTRBUFFERVIEWERS, workers()[1])
                    for ins in keys(instrbufferviewers_remote)
                        ins == "VirtualInstr" && continue
                        empty!(INSTRBUFFERVIEWERS[ins])
                        for addr in keys(instrbufferviewers_remote[ins])
                            push!(INSTRBUFFERVIEWERS[ins], addr => InstrBufferViewer(ins, addr))
                        end
                    end
                    SYNCSTATES[Int(AutoDetecting)] = false
                    SYNCSTATES[Int(AutoDetectDone)] = false
                    break
                else
                    yield()
                end
            end
        end
    )
end

function fetch_ibvs(addinstr)
    remotecall_wait(workers()[1], addinstr) do addinstr
        delete!(INSTRBUFFERVIEWERS["Others"], addinstr)
    end
    delete!(INSTRBUFFERVIEWERS["Others"], addinstr)
    instrbufferviewers_remote = remotecall_fetch(() -> INSTRBUFFERVIEWERS, workers()[1])
    for ins in keys(instrbufferviewers_remote)
        ins == "VirtualInstr" && continue
        for addr in keys(instrbufferviewers_remote[ins])
            haskey(INSTRBUFFERVIEWERS[ins], addr) && continue
            push!(INSTRBUFFERVIEWERS[ins], addr => InstrBufferViewer(ins, addr))
        end
    end
end

let
    addinstr::String = ""
    st::Bool = false
    time_old::Float64 = 0
    global function manualadd_from_others()
        @c ComBoS("##OthersIns", &addinstr, keys(INSTRBUFFERVIEWERS["Others"]))
        if CImGui.Button(stcstr(MORESTYLE.Icons.NewFile, " ", mlstr("Add"), " "))
            st = remotecall_fetch(manualadd, workers()[1], addinstr)
            st && (fetch_ibvs(addinstr); addinstr = "")
            time_old = time()
        end
        if time() - time_old < 2
            CImGui.SameLine()
            if st
                CImGui.TextColored(MORESTYLE.Colors.HighlightText, mlstr("successfully added!"))
            else
                CImGui.TextColored(MORESTYLE.Colors.LogError, mlstr("addition failed!!!"))
            end
        end
    end
end

let
    newinsaddr::String = ""
    st::Bool = false
    time_old::Float64 = 0
    global function manualadd_ui()
        if CImGui.CollapsingHeader(stcstr("\t\t\t", mlstr("Others"), "\t\t\t\t\t\t"))
            manualadd_from_others()
        end
        if CImGui.CollapsingHeader(stcstr("\t\t\t", mlstr("Manual Input"), "\t\t\t\t\t\t"))
            @c InputTextWithHintRSZ("##manual input addr", mlstr("instrument address"), &newinsaddr)
            if CImGui.BeginPopup("select common address")
                for addr in CONF.ComAddr.addrs
                    addr == "" && (CImGui.TextColored(MORESTYLE.Colors.HighlightText, "unavailable option!");
                    continue)
                    CImGui.MenuItem(addr) && (newinsaddr = addr)
                end
                CImGui.EndPopup()
            end
            CImGui.OpenPopupOnItemClick("select common address", 1)
            if CImGui.Button(stcstr(MORESTYLE.Icons.NewFile, " ", mlstr("Add"), "##manual input addr"))
                st = remotecall_fetch(manualadd, workers()[1], newinsaddr)
                st && (fetch_ibvs(newinsaddr); newinsaddr = "")
                time_old = time()
            end
            if time() - time_old < 2
                CImGui.SameLine()
                if st
                    CImGui.TextColored(MORESTYLE.Colors.HighlightText, mlstr("successfully added!"))
                else
                    CImGui.TextColored(MORESTYLE.Colors.LogError, mlstr("addition failed!!!"))
                end
            end
        end
    end
end