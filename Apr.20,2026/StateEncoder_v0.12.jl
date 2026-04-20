# This file is to create a function that handles the state encoding and pre-detemine the feasible actions given a state
# v0.11: Fix 3 — enumerate(Info.Alt) for vector iteration; push! for AltAvail

# Define a function encoding the state space
function StateEncoder(Data::DefMDPData, Info::DefMDPInfo)

    idxS = 1                        # Initialize the state index

    # Loop through all possible inventory levels to create the state space
    for inv1 in Data.MinI[1]:Data.MaxI[1]
        for inv2 in Data.MinI[2]:Data.MaxI[2]
            for inv3 in Data.MinI[3]:Data.MaxI[3]
                for inv4 in Data.MinI[4]:Data.MaxI[4]
                    Info.StSp[(inv1, inv2, inv3, inv4)] = idxS
                    push!(Info.It1, inv1)
                    push!(Info.It2, inv2)
                    push!(Info.It3, inv3)
                    push!(Info.It4, inv4)

                    # Define the available alternatives for each state
                    # Suppose the production can be launched freely
                    AltAvail_list = Int64[]
                    for (idxA, alt) in enumerate(Info.Alt)   # Fix 3: enumerate instead of Dict iteration
                        #if (!((inv1 > 0) && (alt[1] > 0))) && (!((inv2 > 0) && (alt[2] > 0))) && (!((inv3 > 0) && (alt[3] > 0))) && (!((inv4 > 0) && (alt[4] > 0)))
                        #    push!(AltAvail_list, idxA)      # Add the feasible alternative index to the list
                        #end
                        # Put the cap on the production quantity based on current inventory level and max inventory level
                        if (inv1 + alt[1] <= Data.MaxI[1]) && (inv2 + alt[2] <= Data.MaxI[2]) && (inv3 + alt[3] <= Data.MaxI[3]) && (inv4 + alt[4] <= Data.MaxI[4])
                            push!(AltAvail_list, idxA)      # Add the feasible alternative index to the list
                        end
                    end
                    push!(Info.AltAvail, AltAvail_list)   # Fix 3: push! instead of Dict assignment
                    idxS += 1                               # Update the state index
                end
            end
        end
    end

    NumS = idxS-1                                           # Total number of states
    Info.Nₛ = NumS                                           # Store the total number of states into the structure
end
