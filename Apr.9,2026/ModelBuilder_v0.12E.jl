# Model Building Module
# v0.12E: In-transit inventory model with full v0.11 CSR flat-array performance.
#
# In-transit dynamics (preserved from v0.3E):
#   - Current in-transit (its) arrives and is added to inventory this period.
#   - New in-transit is set to alt (the shipment action chosen this period).
#   - Next-state inventory: ni_k = clamp(max(inv[k]-dem[k], MinI[k]) + its[k], MinI[k], MaxI[k])
#   - Next-state transit:   nits_k = alt[k]
#
# Cost model (preserved from v0.3E):
#   - Shipment cost: sum(alt[k] * w[k]) * v  (emergency per-unit-weight rate)
#   - Holding and backorder costs: same as v0.11
#   - Lost sales cost: same as v0.11
#   - No fixed production or powder cost (those are v0.11 c/pd terms; v0.3E uses v/w instead)
#
# Performance improvements vs v0.3E (ported from v0.11):
#   1. 8D lookup array (StArr) replaces Dict StSp — 4 inv dims + 4 transit dims.
#      Each dim is small (MinI..MaxI or 0..MaxI), fitting comfortably in cache.
#   2. CSR flat arrays (pair_start, cols_flat, vals_flat, q_flat, p_len_flat) replace
#      per-action sparse matrices — 5 total allocations vs millions in v0.3E.
#   3. Transition aggregation: deduplicates identical next-state entries per demand scenario.
#   4. Loop unrolling (Nᵢ=4 specific): explicit ni1..ni4, its1..its4 expressions.
#   5. Multi-threading (Threads.@threads on outer state loop): each state writes to a unique
#      pair_idx range in flat arrays — no data races. Per-thread buffers prevent sharing.
#   6. ActionShipCost precomputed once per action (replaces per-(s,a,d) recalculation).
#
# Thread safety:
#   - StArr: read-only after construction — safe to share across threads.
#   - Alt, AltAvail: read-only after StateEncoder — safe to share.
#   - ActionShipCost, D, ProbD, cost arrays: read-only constants — safe.
#   - cols_flat, vals_flat, q_flat, p_len_flat: each state s writes to unique pair_idx range
#     (pair_start[s]..pair_start[s+1]-1) — no race conditions across threads.
#   - cols_buffer, vals_buffer, agg_cols, agg_vals: per-thread — no sharing.

function ModelBuilder(Data::DefMDPData, Info::DefMDPInfoE)

    A  = length(Info.Alt)
    S  = Info.Nₛ
    ND = length(Data.D)
    Nᵢ = Data.Nᵢ

    # Cache frequently accessed fields into local variables
    MinI  = Data.MinI
    MaxI  = Data.MaxI
    h     = Data.h
    b     = Data.b
    ls    = Data.ls
    v     = Data.v
    w     = Data.w
    D     = Data.D
    ProbD = Data.ProbD
    StSp  = Info.StSp
    Alt   = Info.Alt
    AltAvail = Info.AltAvail

    ItVec   = (Info.It1,   Info.It2,   Info.It3,   Info.It4)    # inventory per state
    ItVec_T = (Info.It1T0, Info.It2T0, Info.It3T0, Info.It4T0)  # in-transit per state
    absMinI = ntuple(i -> abs(MinI[i]), 4)

    # ── Optimization 1: 8D lookup array replacing StSp Dict ─────────────────────────────────
    # Inventory dims:  MinI[k]:MaxI[k]  → 1-based offset: off_k = 1 - MinI[k]
    # In-transit dims: 0:MaxI[k]        → 1-based offset: +1 (0-based → 1-indexed)
    off1, off2, off3, off4 = 1-MinI[1], 1-MinI[2], 1-MinI[3], 1-MinI[4]
    StArr = zeros(Int32,
                  MaxI[1]-MinI[1]+1, MaxI[2]-MinI[2]+1,
                  MaxI[3]-MinI[3]+1, MaxI[4]-MinI[4]+1,
                  Data.Cap+1,         Data.Cap+1,
                  Data.Cap+1,         Data.Cap+1)
    for (key, idx) in StSp
        # key = (inv1, inv2, inv3, inv4, its1, its2, its3, its4)
        StArr[key[1]+off1, key[2]+off2, key[3]+off3, key[4]+off4,
               key[5]+1,    key[6]+1,    key[7]+1,    key[8]+1] = idx
    end
    # StSp is NOT cleared — kept for simulation state lookup after ModelBuilder returns.

    # ── CSR Fix: compute pair_start (cumulative action offsets per state) ─────────────────────
    # pair_start[s] = 1-based flat index of the first action for state s.
    pair_start = Vector{Int64}(undef, S+1)
    pair_start[1] = 1
    for s in 1:S
        pair_start[s+1] = pair_start[s] + length(AltAvail[s])
    end
    total_valid     = pair_start[S+1] - 1
    Info.pair_start = pair_start

    # ── CSR Fix: flat array allocation (5 allocations total) ─────────────────────────────────
    # cols_flat:  ND × total_valid, Int32   — next-state index per demand scenario
    # vals_flat:  ND × total_valid, Float64 — transition probability per demand scenario
    # q_flat:     total_valid, Float64      — immediate reward per (s,a) pair
    # p_len_flat: total_valid, Int32        — unique transition count after aggregation
    Info.cols_flat  = Matrix{Int32}(undef, ND, total_valid)
    Info.vals_flat  = Matrix{Float64}(undef, ND, total_valid)
    Info.q_flat     = Vector{Float64}(undef, total_valid)
    Info.p_len_flat = Vector{Int32}(undef, total_valid)

    # ── Precompute per-action emergency shipment cost ─────────────────────────────────────────
    # ship_cost(a) = sum(alt[k] * w[k]) * v
    # Computed once outside the hot loop; same for all states and demand scenarios.
    ActionShipCost = Vector{Float64}(undef, A)
    @inbounds for a in 1:A
        alt = Alt[a]
        ActionShipCost[a] = (alt[1]*w[1] + alt[2]*w[2] + alt[3]*w[3] + alt[4]*w[4]) * v
    end

    # ── Optimization 5: per-thread buffers for multi-threading ───────────────────────────────
    # cols_buffers/agg_cols_arr use Int32 to match cols_flat element type directly.
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

    # ── Main loop (parallelized over states) ─────────────────────────────────────────────────
    # States are fully independent: reads only shared read-only data and writes to unique
    # pair_idx ranges — no synchronization needed.
    @inbounds Threads.@threads for s in 1:S
        tid         = Threads.threadid()
        cols_buffer = cols_buffers[tid]
        vals_buffer = vals_buffers[tid]
        agg_cols    = agg_cols_arr[tid]
        agg_vals    = agg_vals_arr[tid]

        # Current inventory and in-transit levels for state s (Optimization 4: unrolled)
        inv = ntuple(i -> ItVec[i][s],   Nᵢ)   # (inv1, inv2, inv3, inv4)
        its = ntuple(i -> ItVec_T[i][s], Nᵢ)   # (its1, its2, its3, its4)

        # State holding + backorder cost (same for all actions and demands at state s)
        inv_cost  = max(inv[1],0)*h[1] + max(inv[2],0)*h[2] +
                    max(inv[3],0)*h[3] + max(inv[4],0)*h[4]
        back_cost = max(-inv[1],0)*b[1] + max(-inv[2],0)*b[2] +
                    max(-inv[3],0)*b[3] + max(-inv[4],0)*b[4]
        base_cost = inv_cost + back_cost

        # 0-based offset for this state's flat-array entries
        pair_base = pair_start[s] - 1
        avail_s   = AltAvail[s]

        for local_a in eachindex(avail_s)
            a         = avail_s[local_a]
            alt       = Alt[a]
            ship_cost = ActionShipCost[a]
            reward_sum = 0.0

            for d in 1:ND
                prob = ProbD[d]
                dem  = D[d]

                # ── In-transit dynamics (v0.3E logic, unrolled for performance) ───────────
                # 1. Old in-transit (its) arrives: added to post-demand inventory.
                # 2. New in-transit is set to alt (the shipment dispatched this period).
                # Next inventory: clamp(max(inv[k] - dem[k], MinI[k]) + its[k], MinI[k], MaxI[k])
                # Next transit:   alt[k]
                ni1 = clamp(max(inv[1]-dem[1], MinI[1]) + its[1], MinI[1], MaxI[1])
                ni2 = clamp(max(inv[2]-dem[2], MinI[2]) + its[2], MinI[2], MaxI[2])
                ni3 = clamp(max(inv[3]-dem[3], MinI[3]) + its[3], MinI[3], MaxI[3])
                ni4 = clamp(max(inv[4]-dem[4], MinI[4]) + its[4], MinI[4], MaxI[4])
                # Lookup next state: inventory dims use off_k; transit dims use alt[k]+1
                ns = StArr[ni1+off1, ni2+off2, ni3+off3, ni4+off4,
                            alt[1]+1, alt[2]+1, alt[3]+1, alt[4]+1]

                # Lost sales cost: demand exceeding the allowed backorder buffer (|MinI|)
                ls_cost = max(max(dem[1]-inv[1],0) - absMinI[1], 0)*ls[1] +
                          max(max(dem[2]-inv[2],0) - absMinI[2], 0)*ls[2] +
                          max(max(dem[3]-inv[3],0) - absMinI[3], 0)*ls[3] +
                          max(max(dem[4]-inv[4],0) - absMinI[4], 0)*ls[4]

                cols_buffer[d] = ns    # Int32 direct (matches StArr return type)
                vals_buffer[d] = prob
                reward_sum    += -(base_cost + ls_cost + ship_cost) * prob
            end

            # ── Optimization 3: aggregate duplicate next-state transitions ────────────────
            # Multiple demand scenarios may produce the same next state; merge their probs.
            # O(ND²) = O(256) — negligible; eliminates redundant RowDot work in Optimizer.
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

            # ── CSR write: direct flat-array assignment (unique pair_idx per thread) ─────
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
