# MDP JRP AM v0.11
# v0.7: Optimized with 4D array lookup (replaces Dict), transition aggregation, and loop unrolling
# v0.9: Added multi-threading on the outer state loop for additional speedup
# v0.10: Fix 1 — pre-allocated RowData with p_len (zero in-loop allocations)
#        Fix 2 — StArr uses Int32 (restores L2 cache fit at large problem sizes)
#        Fix 3 — Alt and AltAvail changed from Dict to Vector (O(1) indexed access)
#        Fix 4 — Optimizer while !done replaced with for n loop (eliminates branch in hot path)
# v0.11 (Memory Fixes):
#        Fix A — TransStateSearch: eliminated O(S²) dense matrix (was primary OOM cause).
#                At MaxI=(16,16,16,16) the old S×S matrix alone needed 136 GB; now O(S).
#        Fix B removed — empty!(Info.StSp) removed so simulation can look up states via StSp.
#        Fix C — p_rows/q/p_len: changed from action-outer [A][S] to per-state [S][local_a].
#                (superseded by CSR Fix below)
#        CSR Fix — RowData/p_rows/q/p_len replaced with 5 CSR flat arrays. Drops ~164 million
#                  small Vector allocations to 5. Memory: ~27.5 GB → ~16.7 GB.
#                  ModelBuilder @allocated: ~34.1 GB → ~17 GB.
# Nᵢ=4 specific — uses hardcoded 4D indexing for maximum performance
# Simulation-callable — no top-level execution; safe to include from MDPExp or other scripts.

# Import libraries
using BenchmarkTools, CSV, DataFrames, Printf

# Import function files
include("Data_v0.12.jl")
include("Initialization_v0.12.jl")
include("AltDefine_S_v0.12.jl")
include("StateEncoder_v0.12.jl")
include("ModelBuilder_v0.12.jl")
include("Optimizer_v0.12.jl")
include("TransStateSearch_v0.12.jl")

# ── Memory Estimation ─────────────────────────────────────────────────────────
# Call after AltDefine + StateEncoder (so Nₛ and AltAvail are populated).
# Estimates heap memory that ModelBuilder will allocate under the CSR flat-array layout.
# Uses exact valid-pair count from AltAvail rather than an average.
#
# Note: actual Julia process RSS will be higher due to GC overhead, OS pages,
# and Julia runtime. Use `Sys.free_memory()` / `Sys.total_memory()` at runtime
# for remaining system RAM.
function PrintMemoryEstimate(Data::DefMDPData, Info::DefMDPInfo)
    S           = Info.Nₛ
    ND          = length(Data.D)
    A           = length(Info.Alt)
    total_valid = sum(length, Info.AltAvail)   # exact count of valid (s,a) pairs

    # CSR flat-array memory breakdown:
    #   cols_flat  : Int32 × ND × total_valid  (next-state indices)
    #   vals_flat  : Float64 × ND × total_valid (transition probabilities)
    #   q_flat     : Float64 × total_valid      (immediate rewards)
    #   p_len_flat : Int32 × total_valid        (unique transition counts)
    #   pair_start : Int64 × (S+1)             (CSR row-pointer array)
    mem_cols   = total_valid * ND * 4     # Int32
    mem_vals   = total_valid * ND * 8     # Float64
    mem_q      = total_valid * 8          # Float64
    mem_plen   = total_valid * 4          # Int32
    mem_pstart = (S + 1) * 8             # Int64

    # Optimizer arrays: Value (Float64) + Decision (Int64) + Gain (Float64)
    mem_vdg = S * (Data.Period + 1) * 24

    # StArr (Int32, kept for simulation state lookup)
    mem_starr = prod(ntuple(i -> Data.MaxI[i]-Data.MinI[i]+1, 4)) * 4

    total = mem_cols + mem_vals + mem_q + mem_plen + mem_pstart + mem_vdg + mem_starr

    println("=== Memory Estimate (CSR flat-array layout) ===")
    @printf("  States S          = %d\n", S)
    @printf("  Actions A         = %d\n", A)
    @printf("  Valid (s,a) pairs  = %d  (avg %.1f per state)\n", total_valid, total_valid/S)
    @printf("  ND (demand scen)  = %d\n", ND)
    println("  ---")
    @printf("  cols_flat (Int32):   %8.3f GB\n", mem_cols/1e9)
    @printf("  vals_flat (Float64): %8.3f GB\n", mem_vals/1e9)
    @printf("  q_flat + p_len:      %8.3f GB\n", (mem_q+mem_plen)/1e9)
    @printf("  pair_start:          %8.3f MB\n", mem_pstart/1e6)
    @printf("  Value/Decision/Gain: %8.3f GB\n", mem_vdg/1e9)
    @printf("  StArr (Int32):       %8.3f MB\n", mem_starr/1e6)
    println("  ---")
    @printf("  TOTAL ESTIMATE:      %8.3f GB\n", total/1e9)
    @printf("  System free RAM:     %8.3f GB\n", Sys.free_memory()/1e9)
    if total > Sys.free_memory()
        println("  WARNING: Estimated memory exceeds free system RAM — OOM likely!")
    end
    println("===============================================\n")
end

# ── Core Model Function ───────────────────────────────────────────────────────
# Runs the full MDP pipeline: AltDefine → StateEncoder → ModelBuilder →
# Optimizer → TransStateSearch. Safe to call multiple times with fresh Data/Info.
# Includes MDPSimulation_v0.11.jl so MDPSim / MDPSimAM are available after return.
function MDP_JRP_AM_S_v0_12(Data::DefMDPData, Info::DefMDPInfo)

    # Define available actions
    AltDefineS(Data, Info)
    println("AltDefine complete.")

    # Encode state space and determine feasible actions per state
    StateEncoder(Data, Info)
    println("StateEncoder complete.")
    println("  States S = $(Info.Nₛ),  Actions A = $(length(Info.Alt))\n")

    # Print memory estimate before ModelBuilder allocates the main data structures
    PrintMemoryEstimate(Data, Info)

    # Build the model (CSR flat arrays: pair_start, cols_flat, vals_flat, q_flat, p_len_flat)
    ModelBuilder(Data, Info)
    println("ModelBuilder complete.")

    # Optimization: compute Value, Decision, Gain matrices
    Optimizer(Data, Info)
    println("Optimizer complete.")

    # Steady-state distribution under the optimal policy
    #TransStateSearch(Data, Info)
    #println("TransStateSearch complete.\n")

    return Info, Data
end

# Run the model
#Data = CreateMDPData((5, 7, 6, 3))
#Info = CreateMDPInfo()
#@time Info2, Data = MDP_JRP_AM_v0_11(Data, Info)
#println("MDP_JRP_AM_v0.11 Model Run Complete.")