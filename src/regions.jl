"""
Regions describe disjoint parts of a logical object used for conflict detection.
"""
abstract type Region end

"""
Entire object.
"""
struct Whole <: Region end

"""
Single key within an associative container.
"""
struct Key{K} <: Region
    k::K
end

"""
One-dimensional block over contiguous indices.
"""
struct Block <: Region
    r::UnitRange{Int}
end

"""
Two-dimensional tile over row/column ranges.
"""
struct Tile <: Region
    I::UnitRange{Int}
    J::UnitRange{Int}
end

"""
Sparse set of explicit indices.
"""
struct IndexSet{T<:AbstractVector{Int}} <: Region
    idxs::T
end

"""
Check whether two integer ranges overlap.
"""
ranges_overlap(a::UnitRange{Int}, b::UnitRange{Int}) = max(first(a), first(b)) <= min(last(a), last(b))

"""
Overlap semantics; default to conservative `true` for unknown combos.
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
Conservative default for index sets until a more precise checker is provided.
"""
overlaps(::IndexSet, ::IndexSet) = true

overlaps(::Region, ::Region) = true
