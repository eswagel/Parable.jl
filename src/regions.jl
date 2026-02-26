"""
    Region

Abstract supertype for region descriptors used by access declarations.

A region scopes an effect to a subset of an object so Parables can distinguish
independent accesses from conflicting ones.
"""
abstract type Region end

"""
    Whole() <: Region

Region representing an entire object.
"""
struct Whole <: Region end

"""
    Key(k) <: Region

Region representing a single logical key `k`, typically used for map-like
containers or keyed partitions.
"""
struct Key{K} <: Region
    k::K
end

"""
    Block(r::UnitRange{Int}) <: Region

One-dimensional contiguous index range.
"""
struct Block <: Region
    r::UnitRange{Int}
end

"""
    Tile(I::UnitRange{Int}, J::UnitRange{Int}) <: Region

Two-dimensional rectangular tile defined by row range `I` and column range `J`.
"""
struct Tile <: Region
    I::UnitRange{Int}
    J::UnitRange{Int}
end

"""
    IndexSet(idxs::AbstractVector{Int}) <: Region

Sparse set of explicit indices.
"""
struct IndexSet{T<:AbstractVector{Int}} <: Region
    idxs::T
end

"""
    ranges_overlap(a::UnitRange{Int}, b::UnitRange{Int}) -> Bool

Return `true` when integer ranges `a` and `b` intersect.
"""
ranges_overlap(a::UnitRange{Int}, b::UnitRange{Int}) = max(first(a), first(b)) <= min(last(a), last(b))

"""
    overlaps(a::Region, b::Region) -> Bool

Return whether regions `a` and `b` may overlap.

# Semantics
- `Whole()` overlaps everything.
- `Key(k1)` overlaps `Key(k2)` only when `k1 == k2`.
- `Block` and `Tile` use range intersection checks.
- `IndexSet` currently uses a conservative overlap policy for `IndexSet` pairs.
- Unknown region combinations default to conservative `true`.
"""
overlaps(::Whole, ::Whole) = true
overlaps(::Whole, ::Region) = true
overlaps(::Region, ::Whole) = true
overlaps(::Key, ::Whole) = true
overlaps(::Whole, ::Key) = true

overlaps(a::Key, b::Key) = a.k == b.k
overlaps(::Key, ::Region) = false
overlaps(a::Region, b::Key) = overlaps(b, a)

overlaps(a::Block, b::Block) = ranges_overlap(a.r, b.r)

overlaps(a::Tile, b::Tile) = ranges_overlap(a.I, b.I) && ranges_overlap(a.J, b.J)

"""
    overlaps(a::IndexSet, b::IndexSet) -> Bool

Conservative overlap check for sparse index sets.

Currently returns `true` to avoid missed dependencies.
"""
overlaps(::IndexSet, ::IndexSet) = true

overlaps(::Region, ::Region) = true
