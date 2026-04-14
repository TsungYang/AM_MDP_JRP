# This file is to create a function that calculates the transient state probabilities for computing the weighted average cost
# v0.10: Fix 1 — use p_len for RowData iteration (avoids length() on pre-allocated buffer)
# v0.11 (Memory Fix A) — Eliminated O(S²) dense transition matrix pᵒ.
#        Old code: pᵒ = zeros(Float64, Nₛ, Nₛ) — allocates S² × 8 bytes
#                  e.g. MaxI=(16,16,16,16) → S=130,321 → 136 GB → OOM on 128 GB machine
#        New code: sparse scatter power-iteration using flat arrays directly — O(S) memory only.
#        Also eliminated 3 per-iteration heap allocations from the convergence while loop.
# v0.11 (Memory Fix C) — Updated to use per-state layout p_rows[s][local_a] instead of p_rows[a][s].
# v0.11 (CSR Fix) — Updated to use flat arrays (pair_start/cols_flat/vals_flat/p_len_flat)
#        instead of nested RowData access. Same O(S) memory; eliminates pointer-chasing.

# Import packages
using LinearAlgebra

# Define the function
function TransStateSearch(Data::DefMDPData, Info::DefMDPInfo)
    Info.TransStateProb = zeros(Float64, Info.Nₛ)

    OP = Data.Period + 1

    # Two plain 1-D arrays replace the old 1×Nₛ transposed vectors and S×S matrix.
    # Memory: 2 × Nₛ × 8 bytes  (was: Nₛ² × 8 bytes for pᵒ alone)
    Π  = fill(1.0 / Info.Nₛ, Info.Nₛ)   # current distribution
    Πₙ = zeros(Float64, Info.Nₛ)          # next distribution buffer (reused every iteration)

    # Cache flat array references (read-only)
    pair_start = Info.pair_start
    cols_flat  = Info.cols_flat
    vals_flat  = Info.vals_flat
    p_len_flat = Info.p_len_flat

    # Precompute local action index for each state's optimal decision.
    # Done once before the convergence loop — avoids repeated linear search per iteration.
    local_a_map = Vector{Int}(undef, Info.Nₛ)
    @inbounds for s in 1:Info.Nₛ
        a     = Info.Decision[s, OP]
        avail = Info.AltAvail[s]
        for li in eachindex(avail)
            if avail[li] == a
                local_a_map[s] = li
                break
            end
        end
    end

    # Sparse power iteration: Πₙ[s'] += Π[s] * P(s → s')
    # P is stored implicitly in flat arrays — no S×S matrix ever allocated.
    # Each state s contributes at most ND unique next-state entries (typically 4–16).
    while true
        fill!(Πₙ, 0.0)
        @inbounds for s in 1:Info.Nₛ
            local_a  = local_a_map[s]
            pair_idx = pair_start[s] + local_a - 1
            len      = p_len_flat[pair_idx]
            πs       = Π[s]
            for k in 1:len
                Πₙ[cols_flat[k, pair_idx]] += πs * vals_flat[k, pair_idx]
            end
        end

        # L∞ convergence check — zero allocations (no ConvergenceList array needed)
        converged = true
        @inbounds for s in 1:Info.Nₛ
            if abs(Πₙ[s] - Π[s]) > 1e-5
                converged = false
                break
            end
        end

        Π, Πₙ = Πₙ, Π    # swap buffer references — zero allocation

        if converged
            Info.TransStateProb = Π
            break
        end
    end
end
