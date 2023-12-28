types = [
    :SweepQuantity, :SetQuantity, :ReadQuantity, :InstrBuffer, :InstrBufferViewer,
    :CodeBlock, :StrideCodeBlock, :SweepBlock, :SettingBlock, :ReadingBlock,
    :WriteBlock, :QueryBlock, :ReadBlock, :FeedbackBlock,
    :Node, :ResizeGrip, :ImagePin, :ImageRegion, :SampleHolderNode, :NodeEditor, :DAQTask,
    :Layout, :DataSeries, :DataPicker,
    :Xaxis, :Yaxis, :Zaxis, :Axis, :Linecut, :Annotation, :PlotSeries, :Plot, :DataPlot,
    :ImNodesStyle, :MoreStyleVariable, :MoreStyleColor, :MoreStyleIcon, :MoreStyle, :UnionStyle
]

for T in types
    JLD2T = Symbol(:JLD2, T)
    eval(quote
        struct $JLD2T
            fieldnames_dict::Dict
        end
        JLD2.writeas(::Type{$T}) = $JLD2T
        JLD2.wconvert(::Type{$JLD2T}, obj::$T) = $JLD2T(Dict(fdnm => getproperty(obj, fdnm) for fdnm in fieldnames($T)))
        function JLD2.rconvert(::Type{$T}, jld2obj::$JLD2T)
            obj = $T()
            fdnms = fieldnames($T)
            for fdnm in keys(jld2obj.fieldnames_dict)
                fdnm in fdnms && setproperty!(obj, fdnm, convert(fieldtype($T, fdnm), jld2obj.fieldnames_dict[fdnm]))
            end
            obj
        end
    end)
end