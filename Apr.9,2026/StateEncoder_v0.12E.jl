# This file is to create a function that handles the state encoding and pre-determine the
# feasible actions given a state.
# v0.12E: In-transit inventory preserved from v0.3E; data structures upgraded to v0.11 style.
#
# Changes vs v0.3E:
#   - StSp key changed to NTuple{8,Int64}: (inv1..4, its1..4) — flat tuple, no Vector allocation.
#   - Alt iteration changed from `for (idxA, alt) in Info.Alt` (Dict) to `enumerate(Info.Alt)`.
#   - AltAvail changed from Dict assignment to push! into Vector{Vector{Int64}}.
#
# Preserved from v0.3E:
#   - Full 8-level nested loop over (inv1..4, its1..4).
#   - In-transit constraint expression uses & (bitwise AND) exactly as in v0.3E.
#
# NOTE on in-transit constraint operator precedence:
#   The expression `!(its1 > 0 & alt[1] > 0)` uses & (bitwise AND for integers), which in Julia
#   binds tighter than >, so it parses as `its1 > (0 & alt[1]) > 0`.
#   `0 & alt[1]` == 0 for any integer alt[1], so this reduces to `its1 > 0 > 0` == false,
#   making `!false` == true. The in-transit ordering constraint is therefore NEVER enforced —
#   only the MaxI capacity bound applies. This preserves v0.3E behavior intentionally.

function StateEncoder(Data::DefMDPData, Info::DefMDPInfoE)

    idxS = 1

    # Loop through all possible inventory levels to create the state space
    for inv1 in Data.MinI[1]:Data.MaxI[1]
        for inv2 in Data.MinI[2]:Data.MaxI[2]
            for inv3 in Data.MinI[3]:Data.MaxI[3]
                for inv4 in Data.MinI[4]:Data.MaxI[4]
                    # In-transit ranges 0:MaxI[k] (cannot be negative; upper-bounded by MaxI)
                    for its1 in 0:Data.Cap
                        for its2 in 0:Data.Cap
                            for its3 in 0:Data.Cap
                                for its4 in 0:Data.Cap
                                    ship = its1 + its2 + its3 + its4
                                    if ship <= Data.Cap
                                        # Flat NTuple{8} key: (inventory..., in-transit...)
                                        state = (inv1, inv2, inv3, inv4, its1, its2, its3, its4)
                                        Info.StSp[state] = idxS
                                        push!(Info.It1,   inv1)
                                        push!(Info.It2,   inv2)
                                        push!(Info.It3,   inv3)
                                        push!(Info.It4,   inv4)
                                        push!(Info.It1T0, its1)
                                        push!(Info.It2T0, its2)
                                        push!(Info.It3T0, its3)
                                        push!(Info.It4T0, its4)

                                        # Determine feasible actions for this state.
                                        # A shipment (alt) is feasible if:
                                        #   (a) ordering does not push inventory above MaxI, AND
                                        #   (b) there is no existing in-transit order for that item.
                                        # Note: condition (b) uses & operator — see file header for
                                        # the operator-precedence note; effectively always true.
                                        AltAvail_list = Int64[]
                                        for (idxA, alt) in enumerate(Info.Alt)
                                            if (inv1 + alt[1] <= Data.MaxI[1]) && (inv2 + alt[2] <= Data.MaxI[2]) &&
                                            (inv3 + alt[3] <= Data.MaxI[3]) && (inv4 + alt[4] <= Data.MaxI[4]) &&
                                            (!((its1 > 0) & (alt[1] > 0))) && (!((its2 > 0) & (alt[2] > 0))) &&
                                            (!((its3 > 0) & (alt[3] > 0))) && (!((its4 > 0) & (alt[4] > 0)))
                                                push!(AltAvail_list, idxA)
                                            end
                                        end
                                        push!(Info.AltAvail, AltAvail_list)
                                        idxS += 1
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    Info.Nₛ = idxS - 1
end
