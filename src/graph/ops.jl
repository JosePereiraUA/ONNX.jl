using Base
# TODO: we need kwarg support for many of these

# Generic
get_tuple(x) = (x...,)
get_tuple() = nothing
convert_type(x) = Base.convert(Array{Float32, 1}, x)

ops[:Concat] = function (params, xs...)
  vcall(:cat, params[:axis] + 2, xs...)
end

ops[:Gemm] = function (params, A, B, C)
  @assert haskey(params, :alpha) && haskey(params, :beta)
  layer = DataFlow.isconstant(B)
  A = get(params, :transA, 0) == 1 ? vcall(transpose, A) : A
  B = get(params, :transB, 0) == 1 ? vcall(transpose, B) : B
  layer ?
    vcall(vcall(:Dense, B, C), A) :
    vcall(broadcast, :+, vcall(*, B, A), C)
end

# Image

function pads(ps)
  padbegin = ps[1:end÷2]
  padend   = ps[end÷2+1:end]
  padbegin == padend || error("Only symmetric padding currently supported, got $padbegin and $padend")
  return (padbegin...)
end

ops[:Conv] = function (params, x, w, b...)
  length(params[:kernel_shape]) == 2 || error("Only Conv2D currently supported")
  if !haskey(params, Symbol("pads"))
    params[:pads] = (0,0)
  end
  if !haskey(params, Symbol("strides"))
    params[:strides] = (1,1)
  end
  if (haskey(params, Symbol("auto_pad")))
    if (String(params[:auto_pad]) == "SAME_UPPER" || String(params[:auto_pad] == "SAME_LOWER"))
      params[:pads] =  Base.convert(Array{Int64,1}, (params[:kernel_shape] .- 1)./2) # Only for strides = [1,1]
    end                                                                           # To Do: Add support for other stride values.
  end
  if isempty(b)
    return vcall(vcall(:Conv, w, convert_type([0]), :relu, Symbol("stride=$((params[:strides]...,))"), Symbol("pad=$((params[:pads]...))")), x)
  end
  vcall(vcall(:Conv, w, b[1], Symbol("stride=$((params[:strides]...,))"),Symbol("pad=$(pads(params[:pads]))")), x)
end

ops[:MaxPool] = function (params, x)
  length(params[:kernel_shape]) == 2 || error("Only maxpool2d currently supported")
  strides = params[:strides] == params[:kernel_shape] ? [] : [params[:strides]]
  vcall(:maxpool, x, (params[:kernel_shape]...,), Symbol("pad=$(pads(params[:pads]))"),Symbol("stride=$((params[:strides]...))"))
end

ops[:GlobalAveragePool] = function (params, x)
  vcall(:mean, x, (1,2))
end

#ops[:BatchNormalization] = function (params, x, scale, b, mean, var)
#  vcall(:BatchNorm, )
# Regularise

ops[:Dropout] = function (params, x)
  vcall(vcall(:Dropout, params[:ratio]), x)
end

# Activation

iscallp(f, v) = DataFlow.iscall(v) && f(v[1])
islayer(v, name) = iscallp(l -> iscallp(x -> x == constant(name), l), v)

ops[:Relu] = function (params, x)
  if islayer(x, :Conv) || islayer(x, :Dense)
    layer = x[1]
    layer = vcall(layer[1], layer[2:3]..., :relu, layer[end], layer[4])
    vcall(layer, x[2])
  else
    vcall(broadcast, :relu, x)
  end
end

ops[:Softmax] = function (params, x)
  vcall(:softmax, x)
end

ops[:Constant] = function (params)
  constant(Symbol("weights[\"$(params.name)\"]"))
end

ops[:Reshape] = function(params, tensor)
  vcall(:reshape, tensor, (params[:shape]...))
end

#To-Do : add broadcast here (Urgent)
#         Add axis condition here
ops[:Add] = function(params, A, B)
  if (params[:broadcast] == 1)
    vcall( :Add,params[:axis], A, B)                  # To-DO : Define Add function  
  else
    # Broadcast not defined: Perform normal addition.
    vcall(:+, A, vcall(:permutedims, B, [2,1]))
  end
end

ops[:MatMul] = function(params, A, B)
  vcall(:*, A, B)
end