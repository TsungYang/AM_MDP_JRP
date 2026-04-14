# This file is to create a customized structure for carrying the information
# v0.12E: In-transit inventory model ported to v0.11 CSR flat-array architecture.
#
# Changes vs v0.3E:
#   - StSp key changed from Vector{NTuple{4,Int64}} to NTuple{8,Int64}:
#       (inv1, inv2, inv3, inv4, its1, its2, its3, its4)
#     Eliminates one heap allocation per Dict lookup; enables constant-time hashing.
#   - Alt changed from Dict{Int64,NTuple} to Vector{NTuple} (O(1) indexed access, no hash overhead).
#   - AltAvail changed from Dict{Int64,Vector} to Vector{Vector} (same benefit).
#   - Sparse matrices p/q removed; replaced with 5 CSR flat arrays:
#       pair_start, cols_flat, vals_flat, q_flat, p_len_flat.
#     Drops from ~millions of small Vector allocations to 5 total allocations per ModelBuilder call.
#   - RowDot signature matches v0.11: takes (pair_idx, len, cols_flat, vals_flat, vec).
#   - RowData struct eliminated (no longer needed).
#
# Preserved from v0.3E:
#   - It1T0..It4T0 vectors (in-transit inventory per state).
#   - SparseArrays import removed (no longer used).

# Import packages
using Random   # For Xoshiro RNG used in Optimizer per-thread buffers

# Define a structure
mutable struct DefMDPInfo
    # State space: key is NTuple{8,Int64} = (inv1, inv2, inv3, inv4, its1, its2, its3, its4)
    StSp::Dict{NTuple{8, Int64}, Int64}
    It1::Vector{Int64}           # Item 1 inventory level per state
    It2::Vector{Int64}           # Item 2 inventory level per state
    It3::Vector{Int64}           # Item 3 inventory level per state
    It4::Vector{Int64}           # Item 4 inventory level per state
    It1T0::Vector{Int64}         # Item 1 in-transit inventory level per state
    It2T0::Vector{Int64}         # Item 2 in-transit inventory level per state
    It3T0::Vector{Int64}         # Item 3 in-transit inventory level per state
    It4T0::Vector{Int64}         # Item 4 in-transit inventory level per state
    Alt::Vector{NTuple{4, Int64}}               # Action vector (was Dict; now Vector for O(1) access)
    AltAvail::Vector{Vector{Int64}}             # Available actions per state (was Dict; now Vector)
    AltReverse::Dict{NTuple{4, Int64}, Int64}   # Reverse action lookup: tuple → index
    Nₛ::Int64                    # Total number of states
    # ── CSR flat-array layout (replaces sparse matrices p and q from v0.3E) ─────────────────────
    # pair_start[s] = 1-based flat index of the first action for state s (length Nₛ+1).
    # pair_start[s+1] - pair_start[s] = |AltAvail[s]|.
    # Flat index for (s, local_a): pair_idx = pair_start[s] + local_a - 1.
    # cols_flat and p_len_flat use Int32 (states fit in 32-bit, halves index memory at scale).
    pair_start::Vector{Int64}        # Cumulative action offsets: length Nₛ+1
    cols_flat::Matrix{Int32}         # Next-state indices: ND × total_valid
    vals_flat::Matrix{Float64}       # Transition probabilities: ND × total_valid
    q_flat::Vector{Float64}          # Immediate rewards: length total_valid
    p_len_flat::Vector{Int32}        # Unique transition count per (s,a) pair: length total_valid
    Value::Matrix{Float64}           # Value function: Nₛ × (Period+1)
    Decision::Matrix{Int64}          # Optimal action index: Nₛ × (Period+1)
    Gain::Matrix{Float64}            # Period gain: Nₛ × (Period+1)
    TransStateProb::Vector{Float64}  # Steady-state probabilities under optimal policy
end

# Define a function to create the structure
function CreateMDPInfo()
    StSp       = Dict{NTuple{8, Int64}, Int64}()
    It1        = Vector{Int64}()
    It2        = Vector{Int64}()
    It3        = Vector{Int64}()
    It4        = Vector{Int64}()
    It1T0      = Vector{Int64}()
    It2T0      = Vector{Int64}()
    It3T0      = Vector{Int64}()
    It4T0      = Vector{Int64}()
    Alt        = Vector{NTuple{4, Int64}}()
    AltAvail   = Vector{Vector{Int64}}()
    AltReverse = Dict{NTuple{4, Int64}, Int64}()
    Nₛ         = 0
    pair_start = Vector{Int64}()
    cols_flat  = Matrix{Int32}(undef, 0, 0)
    vals_flat  = Matrix{Float64}(undef, 0, 0)
    q_flat     = Vector{Float64}()
    p_len_flat = Vector{Int32}()
    Value      = Matrix{Float64}(undef, 0, 0)
    Decision   = Matrix{Int64}(undef, 0, 0)
    Gain       = Matrix{Float64}(undef, 0, 0)
    TransStateProb = Vector{Float64}()

    return DefMDPInfo(StSp, It1, It2, It3, It4, It1T0, It2T0, It3T0, It4T0,
                      Alt, AltAvail, AltReverse, Nₛ,
                      pair_start, cols_flat, vals_flat, q_flat, p_len_flat,
                      Value, Decision, Gain, TransStateProb)
end

# Compute the dot product of a (state, action) row with a dense vector (CSR version).
# pair_idx: flat column index into cols_flat/vals_flat for this (s, local_a) pair.
# len:      p_len_flat[pair_idx] — actual unique next-state transitions after aggregation.
# Accesses a contiguous column of cols_flat/vals_flat (column-major layout) for cache efficiency.
@inline function RowDot(pair_idx::Int, len::Int32,
                         cols_flat::Matrix{Int32}, vals_flat::Matrix{Float64},
                         vec::AbstractVector{Float64})
    s = 0.0
    @inbounds for i in 1:len
        s += vals_flat[i, pair_idx] * vec[cols_flat[i, pair_idx]]
    end
    return s
end
