"""
    Access

Access metadata used for dependency analysis.

# Fields
- `objid::UInt64`: Stable object identity (`objectid(obj)`).
- `obj::Any`: Original object reference (kept for diagnostics).
- `eff::Effect`: Access effect (`Read`, `Write`, `ReadWrite`, `Reduce`).
- `reg::Region`: Region descriptor over the object.
"""
struct Access
    objid::UInt64
    obj::Any
    eff::Effect
    reg::Region
end

"""
    objkey(obj) -> (UInt64, Any)

Return `(objectid(obj), obj)` for reuse in access construction and debugging.
"""
objkey(obj) = (objectid(obj), obj)

"""
    access(obj, eff::Effect, reg::Region) -> Access

Construct an `Access` record from an object, effect, and region.
"""
function access(obj, eff::Effect, reg::Region)
    id, o = objkey(obj)
    Access(id, o, eff, reg)
end
