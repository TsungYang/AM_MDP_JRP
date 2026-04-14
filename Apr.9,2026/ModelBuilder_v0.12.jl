# This is the file to create function for Building Module
# v0.7: Optimized with 4D array lookup (replaces Dict), transition aggregation, and loop unrolling
# v0.9: Added multi-threading on the outer state loop (Optimization 5)
# v0.10: Fix 1 — pre-allocated RowData with p_len (zero in-loop allocations)
#        Fix 2 — StArr uses Int32 (restores L2 cache fit at large problem sizes)
# v0.11 (Memory Fix B removed) — empty!(Info.StSp) removed; StSp is kept for simulation state lookup.
# v0.11 (CSR Fix) — Pre-allocation replaced with 5 CSR flat arrays (pair_start, cols_flat,
#        vals_flat, q_flat, p_len_flat). Drops ~164 million small Vector allocations to just 5.
#        cols_buffers/agg_cols_arr changed to Int32 to match cols_flat directly (no int conversion).
# Nᵢ=4 specific — uses hardcoded 4D indexing for maximum performance

function ModelBuilder(Data::DefMDPData, Info::DefMDPInfo)

    A  = length(Info.Alt)
    S  = Info.Nₛ
    ND = length(Data.D)
    Nᵢ = Data.Nᵢ

    # Cache frequently accessed fields
    MinI  = Data.MinI
    MaxI  = Data.MaxI
    h     = Data.h
    b     = Data.b
    ls    = Data.ls
    BH    = Data.BH
    c     = Data.c
    v     = Data.v
    w     = Data.w
    pd    = Data.pd
    D     = Data.D
    ProbD = Data.ProbD
    StSp  = Info.StSp
    Alt   = Info.Alt
    AltAvail = Info.AltAvail

    ItVec   = (Info.It1, Info.It2, Info.It3, Info.It4, Info.It1T0, Info.It2T0, Info.It3T0, Info.It4T0)
    absMinI = ntuple(i -> abs(MinI[i]), 4)

    # ── Optimization 1: Build 4D lookup array (replaces Dict, fits in L1/L2 cache) ──
    off1, off2, off3, off4 = 1-MinI[1], 1-MinI[2], 1-MinI[3], 1-MinI[4]
    StArr = zeros(Int32, MaxI[1]-MinI[1]+1, MaxI[2]-MinI[2]+1,   # Fix 2: Int32
                         MaxI[3]-MinI[3]+1, MaxI[4]-MinI[4]+1)
    for (key, idx) in StSp
        StArr[key[1]+off1, key[2]+off2, key[3]+off3, key[4]+off4] = idx
    end
    # Note: Info.StSp is NOT cleared here (Memory Fix B removed) so that
    # MDPSimAM can look up states via Info.StSp[Tuple(InvLvl)] after model build.

    # ── CSR Fix: Compute pair_start (cumulative action offsets per state) ─────────
    # pair_start[s] = 1-based flat index of the first action for state s.
    # pair_start has length S+1; pair_start[S+1] - 1 = total valid (s,a) pairs.
    pair_start = Vector{Int64}(undef, S+1)
    pair_start[1] = 1
    for s in 1:S
        pair_start[s+1] = pair_start[s] + length(AltAvail[s])
    end
    total_valid    = pair_start[S+1] - 1
    Info.pair_start = pair_start

    # ── CSR Fix: Flat array allocation (5 allocations replaces ~164 million) ──────
    # cols_flat: ND × total_valid, Int32 — next-state indices per demand scenario
    # vals_flat: ND × total_valid, Float64 — transition probabilities
    # q_flat:    total_valid, Float64 — immediate rewards per (s,a) pair
    # p_len_flat: total_valid, Int32 — actual unique transitions after aggregation
    Info.cols_flat  = Matrix{Int32}(undef, ND, total_valid)
    Info.vals_flat  = Matrix{Float64}(undef, ND, total_valid)
    Info.q_flat     = Vector{Float64}(undef, total_valid)
    Info.p_len_flat = Vector{Int32}(undef, total_valid)

    # Precompute action costs
    ActionProdCost = Vector{Float64}(undef, A)
    ActionPowdCost = Vector{Float64}(undef, A)
    @inbounds for a in 1:A
        alt  = Alt[a]
        prod = false
        for i in 1:Nᵢ
            if alt[i] > 0; prod = true; break; end
        end
        ActionProdCost[a] = prod ? c : 0.0
        ActionPowdCost[a] = maximum(alt[i] > 0 ? BH[i] : 0 for i in 1:Nᵢ) * pd
    end

    # ── Optimization 5: Per-thread buffers for multi-threading ───────────────────
    # CSR Fix: cols_buffers and agg_cols_arr changed to Int32 — StArr returns Int32,
    # so storing directly as Int32 avoids a widening-then-narrowing conversion roundtrip.
    nthreads     = Threads.maxthreadid()
    cols_buffers = [Vector{Int32}(undef, ND)   for _ in 1:nthreads]
    vals_buffers = [Vector{Float64}(undef, ND) for _ in 1:nthreads]
    agg_cols_arr = [Vector{Int32}(undef, ND)   for _ in 1:nthreads]
    agg_vals_arr = [Vector{Float64}(undef, ND) for _ in 1:nthreads]

    # Cache flat array references outside the parallel loop (avoids repeated Info field access)
    cols_flat  = Info.cols_flat
    vals_flat  = Info.vals_flat
    q_flat     = Info.q_flat
    p_len_flat = Info.p_len_flat

    # ── Main loop (parallelized over states) ─────────────────────────────────────
    # Each state s is fully independent: reads only shared read-only data (StArr,
    # Alt, AltAvail, cost arrays) and writes to unique pair_idx ranges in flat arrays.
    @inbounds Threads.@threads for s in 1:S
        tid         = Threads.threadid()
        cols_buffer = cols_buffers[tid]
        vals_buffer = vals_buffers[tid]
        agg_cols    = agg_cols_arr[tid]
        agg_vals    = agg_vals_arr[tid]

        inv = ntuple(i -> ItVec[i][s], Nᵢ)

        # Optimization 4: Unrolled cost computation
        inv_cost  = max(inv[1],0)*h[1] + max(inv[2],0)*h[2] +
                    max(inv[3],0)*h[3] + max(inv[4],0)*h[4]
        back_cost = max(-inv[1],0)*b[1] + max(-inv[2],0)*b[2] +
                    max(-inv[3],0)*b[3] + max(-inv[4],0)*b[4]
        base_cost = inv_cost + back_cost

        # CSR Fix: 0-based offset for this state's flat-array entries
        # pair_idx = pair_base + local_a  (1-indexed, since local_a starts at 1)
        pair_base = pair_start[s] - 1
        avail_s   = AltAvail[s]

        for local_a in eachindex(avail_s)
            a         = avail_s[local_a]
            alt       = Alt[a]
            prod_cost = ActionProdCost[a]
            powd_cost = ActionPowdCost[a]
            reward_sum = 0.0

            for d in 1:ND
                prob = ProbD[d]
                dem  = D[d]

                # Optimization 1+4: Unrolled next-state + 4D array lookup
                ni1 = clamp(max(inv[1]-dem[1], MinI[1])+alt[1], MinI[1], MaxI[1])
                ni2 = clamp(max(inv[2]-dem[2], MinI[2])+alt[2], MinI[2], MaxI[2])
                ni3 = clamp(max(inv[3]-dem[3], MinI[3])+alt[3], MinI[3], MaxI[3])
                ni4 = clamp(max(inv[4]-dem[4], MinI[4])+alt[4], MinI[4], MaxI[4])
                ns  = StArr[ni1+off1, ni2+off2, ni3+off3, ni4+off4]  # returns Int32

                # Optimization 4: Unrolled lost sales cost
                ls_cost = max(max(dem[1]-inv[1],0)-absMinI[1],0)*ls[1] +
                          max(max(dem[2]-inv[2],0)-absMinI[2],0)*ls[2] +
                          max(max(dem[3]-inv[3],0)-absMinI[3],0)*ls[3] +
                          max(max(dem[4]-inv[4],0)-absMinI[4],0)*ls[4]

                cols_buffer[d]  = ns   # Int32 direct (no widening; matches cols_flat element type)
                vals_buffer[d]  = prob
                reward_sum     += -(base_cost + ls_cost + prod_cost + powd_cost) * prob
            end

            # Optimization 3: Aggregate duplicate transitions (O(ND²)=O(256), negligible)
            n_unique = 0
            @inbounds for d in 1:ND
                ns_d  = cols_buffer[d]
                found = false
                for j in 1:n_unique
                    if agg_cols[j] == ns_d
                        agg_vals[j] += vals_buffer[d]
                        found = true; break
                    end
                end
                if !found
                    n_unique += 1
                    agg_cols[n_unique] = ns_d
                    agg_vals[n_unique] = vals_buffer[d]
                end
            end

            # CSR Fix: write directly into flat arrays (no RowData, no pointer chasing)
            # Each state's pair_idx range is unique across threads — no race condition.
            pair_idx = pair_base + local_a
            @inbounds for j in 1:n_unique
                cols_flat[j, pair_idx] = agg_cols[j]
                vals_flat[j, pair_idx] = agg_vals[j]
            end
            p_len_flat[pair_idx] = n_unique
            q_flat[pair_idx]     = reward_sum
        end
    end
end
