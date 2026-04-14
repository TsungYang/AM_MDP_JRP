# MDP JRP AM v0.12E
# In-transit inventory model ported to v0.11 CSR flat-array architecture.
#
# Lineage:
#   v0.3E — introduced in-transit inventory as part of the state: state = (inv, in-transit).
#            Used sparse matrices for p/q; Dict for StSp/Alt/AltAvail.
#            Emergency shipment cost model: cost = sum(alt[k]*w[k]) * v.
#            SteadyStateSearch via dense S×S matrix power iteration.
#   v0.6  — RowData struct replaces sparse matrices; smaller memory, better cache locality.
#   v0.7  — 4D StArr replaces Dict StSp lookup; transition aggregation; loop unrolling (Nᵢ=4).
#   v0.9  — Threads.@threads on ModelBuilder outer state loop; per-thread buffers.
#   v0.10 — Pre-alloc RowData (zero in-loop allocs); Int32 StArr; Dict→Vector for Alt/AltAvail;
#            for-n loop in Optimizer replaces while-!done.
#   v0.11 — CSR flat arrays (pair_start/cols_flat/vals_flat/q_flat/p_len_flat) replace RowData;
#            O(S) TransStateSearch replaces O(S²) dense matrix; Threads.@threads on Optimizer.
#   v0.12E— Applies all v0.11 optimizations to the v0.3E in-transit model:
#            * NTuple{8,Int64} state key (4 inv + 4 transit) replaces Vector{NTuple{4,Int64}}.
#            * 8D StArr (4 inv dims + 4 transit dims) for O(1) next-state lookup.
#            * CSR flat arrays retain all v0.11 memory and speed benefits.
#            * In-transit dynamics and emergency shipment cost model preserved exactly.
#            * SteadyStateSearch uses O(S) sparse scatter iteration (no S×S matrix).
#
# Key architectural notes:
#   - State: NTuple{8,Int64} = (inv1..4, its1..4) where its = in-transit level.
#   - Transition: ni_k = clamp(max(inv[k]-dem[k], MinI[k]) + its[k], MinI[k], MaxI[k])
#                 nits_k = alt[k]  (new in-transit = shipment dispatched this period)
#   - Reward includes emergency shipment cost: -sum(alt[k]*w[k])*v per (s,a) pair.
#   - Terminal cost includes in-transit holding: -sum(its[k]*h[k]) at end of horizon.
#   - AltAvail constraint uses original v0.3E & operator (see StateEncoder header).

# Import libraries
using BenchmarkTools, CSV, DataFrames, Printf

# Import function files
include("Data_v0.12.jl")
include("Initialization_v0.12E.jl")
include("AltDefine_v0.12E.jl")
include("StateEncoder_v0.12E.jl")
include("ModelBuilder_v0.12E.jl")
include("Optimizer_v0.12E.jl")

# ── Memory Estimation ─────────────────────────────────────────────────────────────────────────
# Call after AltDefine + StateEncoder (so Nₛ and AltAvail are populated).
# Estimates heap memory that ModelBuilder will allocate under CSR flat-array layout.
# State space for v0.12E is larger than v0.11 (8D vs 4D state) due to in-transit dimensions.
function PrintMemoryEstimate(Data::DefMDPData, Info::DefMDPInfoE)
    S           = Info.Nₛ
    ND          = length(Data.D)
    A           = length(Info.Alt)
    total_valid = sum(length, Info.AltAvail)

    mem_cols   = total_valid * ND * 4     # cols_flat: Int32
    mem_vals   = total_valid * ND * 8     # vals_flat: Float64
    mem_q      = total_valid * 8          # q_flat: Float64
    mem_plen   = total_valid * 4          # p_len_flat: Int32
    mem_pstart = (S + 1) * 8             # pair_start: Int64
    mem_vdg    = S * (Data.Period + 1) * 24   # Value + Decision + Gain matrices

    # 8D StArr: 4 inv dims × 4 transit dims
    inv_size     = prod(ntuple(i -> Data.MaxI[i]-Data.MinI[i]+1, 4))
    transit_size = prod(ntuple(i -> Data.MaxI[i]+1, 4))
    mem_starr    = inv_size * transit_size * 4   # Int32

    total = mem_cols + mem_vals + mem_q + mem_plen + mem_pstart + mem_vdg + mem_starr

    println("=== Memory Estimate (v0.12E CSR flat-array layout) ===")
    @printf("  States S           = %d\n", S)
    @printf("  Actions A          = %d\n", A)
    @printf("  Valid (s,a) pairs   = %d  (avg %.1f per state)\n", total_valid, total_valid/S)
    @printf("  ND (demand scen)   = %d\n", ND)
    println("  ---")
    @printf("  cols_flat (Int32):   %8.3f GB\n", mem_cols/1e9)
    @printf("  vals_flat (Float64): %8.3f GB\n", mem_vals/1e9)
    @printf("  q_flat + p_len:      %8.3f GB\n", (mem_q+mem_plen)/1e9)
    @printf("  pair_start:          %8.3f MB\n", mem_pstart/1e6)
    @printf("  Value/Decision/Gain: %8.3f GB\n", mem_vdg/1e9)
    @printf("  StArr 8D (Int32):    %8.3f MB\n", mem_starr/1e6)
    println("  ---")
    @printf("  TOTAL ESTIMATE:      %8.3f GB\n", total/1e9)
    @printf("  System free RAM:     %8.3f GB\n", Sys.free_memory()/1e9)
    if total > Sys.free_memory()
        println("  WARNING: Estimated memory exceeds free system RAM — OOM likely!")
    end
    println("=====================================================\n")
end

# ── Core Model Function ───────────────────────────────────────────────────────────────────────
function MDP_JRP_AM_v0_12E(Data::DefMDPData, Info::DefMDPInfoE)

    # Define available actions
    AltDefine(Data, Info)
    println("Complete Action Define... \n")

    # Encode state space (inv × in-transit) and determine feasible actions per state
    StateEncoder(Data, Info)
    println("Complete State Encoder...")
    println("  States S = $(Info.Nₛ),  Actions A = $(length(Info.Alt))\n")

    # Print memory estimate before ModelBuilder allocates the main data structures
    PrintMemoryEstimate(Data, Info)

    # Build the model (8D StArr + CSR flat arrays)
    ModelBuilder(Data, Info)
    println("Complete Model Building... \n")

    # Optimization: compute Value, Decision, Gain matrices
    Optimizer(Data, Info)
    println("Complete Optimization... \n")

    # Steady-state distribution under the optimal policy (O(S) sparse scatter)
    #TransStateSearch(Data, Info)
    #println("Complete Steady State Search... \n")

    return Info, Data
end

# Run the model
#Data = CreateMDPData((5, 7, 6, 3))
#Info = CreateMDPInfo()
#@time Info2, Data = MDP_JRP_AM_v0_12E(Data, Info)
#println("MDP_JRP_AM_v0.12E Model Run Complete.")
