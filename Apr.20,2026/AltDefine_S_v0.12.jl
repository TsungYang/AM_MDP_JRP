# This file is to create a function that generates all possible alternatives
# v0.11: Fix 3 — Alt is now a Vector; use push! instead of Dict assignment

function AltDefineS(Data::DefMDPData, Info::DefMDPInfo)

    # Loop to generate all possible alternatives constrainted by the capacity (area)
    # ***Assuming no stacking***
    for i1 in 0:Data.Cap
        for i2 in 0:Data.Cap
            for i3 in 0:Data.Cap
                for i4 in 0:Data.Cap
                    alt = (i1, i2, i3, i4)
                    if (sum(alt) <= Data.Cap) && (sum(alt .> 0) <= 1)       # If the quantities satisfy the capacity of build chamber
                        push!(Info.Alt, alt)                     # Append the alternative to the vector (Fix 3)
                        Info.AltReverse[alt] = length(Info.Alt)  # Reverse map: alt -> index (Fix 3)
                    end
                end
            end
        end
    end
end
