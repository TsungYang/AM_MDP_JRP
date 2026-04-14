# Optimization module
# v0.12E: CSR flat-array access + multi-threading, with v0.3E in-transit end-period cost.
#
# Changes vs v0.3E:
#   - include("DotProduct.jl") removed — RowDot is now defined in Initialization_v0.12E.jl.
#   - include("Heuristic_v0.3.jl") replaced with HeuristicA_v0.12E.jl + HeuristicB_v0.12E.jl.
#   - RowDot call updated to CSR signature: RowDot(pair_idx, len, cols_flat, vals_flat, Vprev).
#   - Threads.@threads added on inner state loop (Fix 4 from v0.10).
#   - while !done replaced with for n in 2:Period+1 (Fix 4 from v0.10).
#   - Terminal period separated into its own threaded block (eliminates if n==1 branch).
#   - Per-thread Xoshiro RNGs pre-allocated (for Method 4, kept commented).
#
# Preserved from v0.3E:
#   - Terminal period (n=1) end-of-horizon cost includes in-transit holding cost:
#       EndValue = -sum(|backorder| .* ep) - sum(inv .* h) - sum(in_transit .* h)
#     Items in transit are considered held and charged the holding rate h at the end horizon.
#
# Thread safety:
#   - Vprev = @view Info.Value[:, n-1] is read-only (previous period, fully written) — safe.
#   - CSR flat arrays (cols_flat, vals_flat, q_flat, p_len_flat) are read-only — safe.
#   - Info.AltAvail[s] is read-only after StateEncoder — safe.
#   - Info.Value[s,n], Info.Decision[s,n], Info.Gain[s,n] written at unique (s,n) — no race.
#   - RowDot uses only a local Float64 accumulator — no shared mutable state.

# Import customized heuristic functions
#include("HeuristicA_v0.12E.jl")
#include("HeuristicB_v0.12E.jl")

function Optimizer(Data::DefMDPData, Info::DefMDPInfoE)

    # Initialize output matrices
    Info.Value    = zeros(Float64, Info.Nₛ, Data.Period+1)
    Info.Decision = zeros(Int64,   Info.Nₛ, Data.Period+1)
    Info.Gain     = zeros(Float64, Info.Nₛ, Data.Period+1)

    # Per-thread RNGs (for Method 4 random sampling — kept commented below)
    nthreads_opt = Threads.maxthreadid()
    rngs = [Xoshiro() for _ in 1:nthreads_opt]

    # Cache flat array references outside all loops (read-only; shared safely across threads)
    pair_start = Info.pair_start
    cols_flat  = Info.cols_flat
    vals_flat  = Info.vals_flat
    q_flat     = Info.q_flat
    p_len_flat = Info.p_len_flat

    # ── Terminal period (n=1): end-of-horizon boundary cost ──────────────────────────────────
    # In-transit holding cost: items in the pipeline at the end of the horizon are charged h.
    # This preserves the v0.3E cost structure.
    @inbounds Threads.@threads for s in 1:Info.Nₛ
        inv_list        = (Info.It1[s],   Info.It2[s],   Info.It3[s],   Info.It4[s])
        in_transit_list = (Info.It1T0[s], Info.It2T0[s], Info.It3T0[s], Info.It4T0[s])
        end_back_list   = min.(inv_list, 0)
        end_inv_list    = max.(inv_list, 0)
        EndValue = -sum(abs.(end_back_list) .* Data.ep) -
                    sum(end_inv_list .* Data.h) -
                    sum(in_transit_list .* Data.h)   # in-transit holding cost at end of horizon
        Info.Value[s, 1]    = EndValue
        Info.Decision[s, 1] = 0
        Info.Gain[s, 1]     = EndValue
    end

    # ── DP periods (n=2..Period+1): backward induction ───────────────────────────────────────
    # Outer for-n loop is sequential (period n depends on n-1 values).
    # Inner state loop is fully parallel — states are independent within a period.
    for n in 2:Data.Period+1
        @inbounds Threads.@threads for s in 1:Info.Nₛ
            Vprev = @view Info.Value[:, n-1]

            # ============================================================
            # METHOD 1: Traditional DP (Exhaustive Search)
            # Finds the globally optimal action for state s at period n.
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
            # METHOD 2: Heuristic A (cost-based greedy)
            # CSR: find local_a matching the heuristic's chosen action.
            # ============================================================
            Qty = Tuple(FindProdQtyA(Data, Info, s, n))
            a   = Info.AltReverse[Qty]
            local_a = 0
            for li in eachindex(avail_s)
                if avail_s[li] == a; local_a = li; break; end
            end
            pair_idx = pair_base + local_a
            len  = p_len_flat[pair_idx]
            ev   = RowDot(pair_idx, len, cols_flat, vals_flat, Vprev)
            qval = q_flat[pair_idx]
            Info.Decision[s, n] = a
            Info.Value[s, n]    = qval + ev
            Info.Gain[s, n]     = qval + ev - Vprev[s]
            =#

            #=
            # ============================================================
            # METHOD 3: Heuristic B (backorder-weighted greedy)
            # ============================================================
            Qty = Tuple(FindProdQtyB(Data, Info, s, n))
            a   = Info.AltReverse[Qty]
            local_a = 0
            for li in eachindex(avail_s)
                if avail_s[li] == a; local_a = li; break; end
            end
            pair_idx = pair_base + local_a
            len  = p_len_flat[pair_idx]
            ev   = RowDot(pair_idx, len, cols_flat, vals_flat, Vprev)
            qval = q_flat[pair_idx]
            Info.Decision[s, n] = a
            Info.Value[s, n]    = qval + ev
            Info.Gain[s, n]     = qval + ev - Vprev[s]
            =#

            #=
            # ============================================================
            # METHOD 4: Random Sampling (100 random actions)
            # Per-thread Xoshiro RNG — thread-safe random sampling.
            # ============================================================
            MaxSoFar = -Inf
            BestA    = 0
            n_avail  = length(avail_s)
            rng      = rngs[Threads.threadid()]
            for _ in 1:100
                local_a  = rand(rng, 1:n_avail)
                pair_idx = pair_base + local_a
                ev   = RowDot(pair_idx, p_len_flat[pair_idx], cols_flat, vals_flat, Vprev)
                qval = q_flat[pair_idx]
                temp = qval + ev
                if temp > MaxSoFar
                    MaxSoFar = temp
                    BestA    = avail_s[local_a]
                end
            end
            Info.Value[s, n]    = MaxSoFar
            Info.Decision[s, n] = BestA
            Info.Gain[s, n]     = MaxSoFar - Vprev[s]
            =#

        end
    end
end
