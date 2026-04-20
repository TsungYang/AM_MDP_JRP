# Optimization module
# v0.7: Uses RowData directly (no sparse matrix conversion needed)
# v0.9 (update): Added Threads.@threads on inner state loop; per-thread RNGs for Method 4
# v0.10: Fix 1 — RowDot now takes explicit len from p_len (zero extra allocation)
#        Fix 4 — while !done replaced with explicit for n loop (eliminates branch in hot path)
# v0.11 (Memory Fix C) — All method access patterns updated from p_rows[a][s] to p_rows[s][local_a]
# v0.11 (CSR Fix) — p_rows/q/p_len replaced with flat-array access via pair_start/cols_flat/
#        vals_flat/q_flat/p_len_flat. RowDot now takes (pair_idx, len, cols_flat, vals_flat, vec).
#        pair_start/flat arrays are cached outside loops for efficient repeated access.

# Import customized functions (heuristics)
include("HeuristicA_v0.12.jl")
include("HeuristicB_v0.12.jl")
include("HeuristicC_v0.12.jl")
include("HeuristicD_v0.12.jl")

# Define the function
function Optimizer(Data::DefMDPData, Info::DefMDPInfo)

    # value matrix for values in each period
    Info.Value = zeros(Float64, Info.Nₛ, Data.Period+1)

    # Decision matrix for decisions in each period
    Info.Decision = zeros(Int64, Info.Nₛ, Data.Period+1)

    # Decision matrix for gains in each period
    Info.Gain = zeros(Float64, Info.Nₛ, Data.Period+1)

    # Per-thread RNGs for Method 4 (thread-safe random sampling)
    nthreads_opt = Threads.maxthreadid()
    rngs = [Xoshiro() for _ in 1:nthreads_opt]

    # Cache flat array references outside all loops (read-only; shared across threads safely)
    pair_start = Info.pair_start
    cols_flat  = Info.cols_flat
    vals_flat  = Info.vals_flat
    q_flat     = Info.q_flat
    p_len_flat = Info.p_len_flat

    # ── Fix 4: Terminal period (n=1) — standalone threaded block ─────────────────
    @inbounds Threads.@threads for s in 1:Info.Nₛ
        inv_list      = (Info.It1[s], Info.It2[s], Info.It3[s], Info.It4[s])
        end_back_list = min.(inv_list, 0)
        end_inv_list  = max.(inv_list, 0)
        EndValue = -sum(abs.(end_back_list) .* Data.ep) - sum(end_inv_list .* Data.h)
        Info.Value[s, 1]    = EndValue
        Info.Decision[s, 1] = 0
        Info.Gain[s, 1]     = EndValue
    end

    # ── Fix 4: DP periods (n=2..Period+1) — for loop replaces while !done ────────
    for n in 2:Data.Period+1
        @inbounds Threads.@threads for s in 1:Info.Nₛ
            Vprev = @view Info.Value[:, n-1]

            # ============================================================
            # METHOD 1: Traditional DP (Exhaustive Search)
            # Searches all available actions for optimal solution.
            # CSR Fix: access flat arrays via pair_start[s] offset.
            # ============================================================
            MaxSoFar = -Inf
            BestA    = 0

            pair_base = pair_start[s] - 1   # 0-based; pair_idx = pair_base + local_a
            avail_s   = Info.AltAvail[s]

            for local_a in eachindex(avail_s)
                pair_idx = pair_base + local_a
                len      = p_len_flat[pair_idx]
                ev       = RowDot(pair_idx, len, cols_flat, vals_flat, Vprev)
                qval     = q_flat[pair_idx]
                temp     = qval + ev
                if temp > MaxSoFar
                    MaxSoFar = temp
                    BestA    = avail_s[local_a]
                end
            end
            Info.Value[s, n]    = MaxSoFar
            Info.Decision[s, n] = BestA
            Info.Gain[s, n]     = MaxSoFar - Vprev[s]

            #=
            # ============================================================
            # METHOD 2: Heuristic-based Action Selection
            # CSR Fix: look up pair_idx from pair_start[s] + local_a - 1
            # ============================================================
            Qty = Tuple(FindProdQtyA(Data, Info, s, n))
            a = Info.AltReverse[Qty]
            avail_s = Info.AltAvail[s]
            local_a = 0
            for li in eachindex(avail_s)
                if avail_s[li] == a; local_a = li; break; end
            end
            pair_idx = pair_start[s] + local_a - 1
            len  = p_len_flat[pair_idx]
            ev   = RowDot(pair_idx, len, cols_flat, vals_flat, Vprev)
            qval = q_flat[pair_idx]
            Info.Decision[s, n] = a
            Info.Value[s, n]    = qval + ev
            Info.Gain[s, n]     = qval + ev - Vprev[s]
            =#

            #=
            # ============================================================
            # METHOD 3: Q-value Only (Greedy Immediate Reward)
            # CSR Fix: track BestLocalA alongside BestA for flat-array access
            # ============================================================
            MaxSoFar   = -Inf
            BestA      = 0
            BestLocalA = 0

            pair_base_m3 = pair_start[s] - 1
            avail_s_m3   = Info.AltAvail[s]

            for local_a in eachindex(avail_s_m3)
                pair_idx = pair_base_m3 + local_a
                temp     = q_flat[pair_idx]
                if temp > MaxSoFar
                    MaxSoFar   = temp
                    BestA      = avail_s_m3[local_a]
                    BestLocalA = local_a
                end
            end
            best_pair_idx = pair_base_m3 + BestLocalA
            ev = RowDot(best_pair_idx, p_len_flat[best_pair_idx], cols_flat, vals_flat, Vprev)
            Info.Value[s, n]    = MaxSoFar + ev
            Info.Decision[s, n] = BestA
            Info.Gain[s, n]     = MaxSoFar + ev - Vprev[s]
            =#

            #=
            # ============================================================
            # METHOD 4: Random Sampling
            # CSR Fix: sample local_a (position in AltAvail[s]) then compute pair_idx
            # ============================================================
            MaxSoFar = -Inf
            BestA    = 0

            pair_base_m4 = pair_start[s] - 1
            avail_s_m4   = Info.AltAvail[s]
            n_avail      = length(avail_s_m4)
            rng          = rngs[Threads.threadid()]

            for _ in 1:100
                local_a  = rand(rng, 1:n_avail)
                pair_idx = pair_base_m4 + local_a
                ev   = RowDot(pair_idx, p_len_flat[pair_idx], cols_flat, vals_flat, Vprev)
                qval = q_flat[pair_idx]
                temp = qval + ev
                if temp > MaxSoFar
                    MaxSoFar = temp
                    BestA    = avail_s_m4[local_a]
                end
            end
            Info.Value[s, n]    = MaxSoFar
            Info.Decision[s, n] = BestA
            Info.Gain[s, n]     = MaxSoFar - Vprev[s]
            =#

        end
    end
end
