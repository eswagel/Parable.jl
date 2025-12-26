"""
Access declaration tying an object identity to an effect and region.
"""
struct Access
    objid::UInt64
    obj::Any
    eff::Effect
    reg::Region
end

"""
Return `(objectid(obj), obj)` for reuse when declaring accesses.
"""
objkey(obj) = (objectid(obj), obj)

"""
Construct an `Access` from a concrete object, effect, and region.
"""
function access(obj, eff::Effect, reg::Region)
    id, o = objkey(obj)
    Access(id, o, eff, reg)
end
