# This file is to create a customized structure for carrying the information
# v0.7: Uses RowData instead of sparse matrices for efficiency
# v0.9: No changes to this file (multi-threading handled in ModelBuilder_v0.9.jl)
# v0.10: Fix 1 — added p_len field for zero-allocation RowDot; Fix 3 — Alt and AltAvail changed from Dict to Vector
# v0.11 (Memory Fix C) — p_rows/q/p_len changed from action-outer [A][S] to per-state [S][local_a] layout.
# v0.11 (CSR Fix) — RowData struct removed. p_rows/q/p_len replaced with 5 CSR flat arrays:
#        pair_start, cols_flat, vals_flat, q_flat, p_len_flat.
#        Eliminates ~163.54 million small Vector allocations per model build (was 2 per RowData).
#        pair_start[s] = 1-based flat index of the first action for state s (length Nₛ+1).
#        Flat index for (s, local_a) = pair_start[s] + local_a - 1.
#        cols_flat/p_len_flat use Int32 (states ≤ 2^31 − 1, saves ~5 GB at large problem sizes).

# Define a structure
mutable struct DefMDPInfo
    StSp::Dict{NTuple{4, Int64}, Int64}         # State Space Dictionary (kept for simulation state lookup)
    It1::Vector{Int64}          # Item 1 Inventory Level vector
    It2::Vector{Int64}          # Item 2 Inventory Level vector
    It3::Vector{Int64}          # Item 3 Inventory Level vector
    It4::Vector{Int64}          # Item 4 Inventory Level vector
    Alt::Vector{NTuple{4, Int64}}                # Action Vector (Fix 3: was Dict{Int64, NTuple})
    AltAvail::Vector{Vector{Int64}}              # Available Alternatives Vector for each state (Fix 3: was Dict)
    AltReverse::Dict{NTuple{4, Int64}, Int64}    # Reverse Action Dictionary
    Nₛ::Int64                   # Total Number of States
    # CSR flat-array layout (replaces RowData / p_rows / q / p_len from v0.10–v0.11 Fix C)
    # pair_start[s] is the 1-based flat index of the first action for state s.
    # pair_start has length Nₛ+1; pair_start[s+1] - pair_start[s] = |AltAvail[s]|.
    # Flat index for (s, local_a): pair_idx = pair_start[s] + local_a - 1.
    pair_start::Vector{Int64}        # Cumulative action offsets: length Nₛ+1
    cols_flat::Matrix{Int32}         # Next-state indices: ND × total_valid (Int32: states fit in 32-bit)
    vals_flat::Matrix{Float64}       # Transition probabilities: ND × total_valid
    q_flat::Vector{Float64}          # Immediate rewards: length total_valid
    p_len_flat::Vector{Int32}        # Actual unique transitions per (s,a) pair: length total_valid
    Value::Matrix{Float64}           # Array to hold values
    Decision::Matrix{Int64}          # Array to hold decisions
    Gain::Matrix{Float64}            # Array to hold gains
    TransStateProb::Vector{Float64}  # Array to hold the steady state probabilities
end

# Define a function to create the structure
function CreateMDPInfo()
    StSp      = Dict{NTuple{4, Int64}, Int64}()
    It1       = Vector{Int64}()
    It2       = Vector{Int64}()
    It3       = Vector{Int64}()
    It4       = Vector{Int64}()
    Alt       = Vector{NTuple{4, Int64}}()
    AltAvail  = Vector{Vector{Int64}}()
    AltReverse = Dict{NTuple{4, Int64}, Int64}()
    Nₛ        = 0
    pair_start = Vector{Int64}()
    cols_flat  = Matrix{Int32}(undef, 0, 0)
    vals_flat  = Matrix{Float64}(undef, 0, 0)
    q_flat     = Vector{Float64}()
    p_len_flat = Vector{Int32}()
    Value      = Matrix{Float64}(undef, 0, 0)
    Decision   = Matrix{Int64}(undef, 0, 0)
    Gain       = Matrix{Float64}(undef, 0, 0)
    TransStateProb = Vector{Float64}()

    return DefMDPInfo(StSp, It1, It2, It3, It4, Alt, AltAvail, AltReverse, Nₛ,
                      pair_start, cols_flat, vals_flat, q_flat, p_len_flat,
                      Value, Decision, Gain, TransStateProb)
end

# Define the function to compute the dot product of a (state, action) row with a dense vector.
# CSR version: pair_idx is the flat column index into cols_flat/vals_flat;
#              len is p_len_flat[pair_idx] (actual number of unique next-state transitions).
@inline function RowDot(pair_idx::Int, len::Int32,
                         cols_flat::Matrix{Int32}, vals_flat::Matrix{Float64},
                         vec::AbstractVector{Float64})
    s = 0.0
    @inbounds for i in 1:len
        s += vals_flat[i, pair_idx] * vec[cols_flat[i, pair_idx]]
    end
    return s
end
