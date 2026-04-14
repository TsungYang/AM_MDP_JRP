# This file is to create a function that generates all possible alternatives
# v0.12E: Alt is now a Vector (Fix 3 from v0.10); push! replaces Dict assignment.
#   - Eliminates IdxA counter variable.
#   - AltReverse still a Dict (keyed by NTuple, only used in heuristics — not the hot loop).

function AltDefine(Data::DefMDPData, Info::DefMDPInfo)

    # Loop to generate all possible alternatives constrained by the capacity (area)
    # ***Assuming no stacking***
    for i1 in 0:Data.Cap
        for i2 in 0:Data.Cap
            for i3 in 0:Data.Cap
                for i4 in 0:Data.Cap
                    alt = (i1, i2, i3, i4)
                    if sum(alt) <= Data.Cap
                        push!(Info.Alt, alt)                     # Append to vector (O(1) amortized)
                        Info.AltReverse[alt] = length(Info.Alt)  # Reverse map: alt → index
                    end
                end
            end
        end
    end
end
