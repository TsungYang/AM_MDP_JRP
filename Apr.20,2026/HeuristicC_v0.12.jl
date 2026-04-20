# This is to create a function that applies the heuristic to determine the produciton quantity
# Heuristic C: Prioritize the item with the highest backorder level to be increase first
# Before returning the solution, compare the total savings in inventory and backorder costs with the fixed production and powder costs

# Define the function 
function FindProdQtyC(Data::DefMDPData, Info::DefMDPInfo, s::Int64, prd::Int64)

    # If there is no period to go, no production is needed
    if prd <= 1
        return zeros(Int64, Data.Nᵢ)
    end

    # Preallocations
    CurrSol      = zeros(Int, Data.Nᵢ)
    CurrInvList  = Vector{Float64}(undef, Data.Nᵢ)
    InitBk   = Vector{Float64}(undef, Data.Nᵢ)

    # Get the current inventory levels and initial backorder levels for all items
    CurrInvList = [Info.It1[s], Info.It2[s], Info.It3[s], Info.It4[s]]
    InitBk = (abs.(min.(CurrInvList, 0)))
        
    # The lost sales cost is assumed to be very high, production when backorder occurs is necessary
    # Start by fulfilling the backorder quantities first
    while true
        MaxBk = 0.0
        MaxBkIdx = 0
        for i in 1:Data.Nᵢ
            Bk = InitBk[i]
            if Bk > MaxBk
                MaxBk = Bk
                MaxBkIdx = i
            end
        end
        if MaxBk == 0.0                                     # If there is no backorder left to be fulfilled,
            break                                           # Exit the loop
        else                                                # Otherwise, 
            CurrSol[MaxBkIdx] += 1                          # Increase its production quantity by 1 unit
            if sum(CurrSol) >= Data.Cap                     # If the space of build chamber is reached, 
                return CurrSol                              # Return the current solution
            else                                            # Otherwise,        
                CurrInvList[MaxBkIdx] += 1.0                # Update the inventory level for the item
                InitBk[MaxBkIdx] -= 1.0                     # Update the backorder level for the item
            end
        end
    end

    # Calculate the expected future demand for each item
    ExpFutDemand = zeros(Float64, Data.Nᵢ)
    for j in 1:length(Data.D)
        ExpFutDemand .+= Data.D[j] .* Data.ProbD[j]
    end

    # Preallocations
    ToBeImprove     = fill(true, Data.Nᵢ)
    AvgInvCostList  = zeros(Float64, Data.Nᵢ)
    AvgBkCostList   = zeros(Float64, Data.Nᵢ)
    BkFut           = Vector{Float64}(undef, Data.Nᵢ)
    Comparison = false
    if sum(CurrSol) == 0                    # If there is no production in the current solution (no current backorder)
        Comparison = true                   # Set to compare the savings with fixed costs later
    end

    # Calculate the initial average inventory and backorder costs for all items
    for i in 1:Data.Nᵢ
        BkFut[i] = abs(CurrInvList[i] - (ExpFutDemand[i] * (prd-2)))
            
        if BkFut[i] == 0.0
            ToBeImprove[i] = false
        end

        if CurrInvList[i] == 0.0
            InvPrd = 0.0
            AvgInvCostList[i] = 0.0
            BkPrd = prd - 2 - InvPrd
            EndBk = ExpFutDemand[i]*BkPrd
            AvgBkCostList[i] = ((EndBk * BkPrd)/2) * Data.b[i]  + EndBk*Data.ep[i]                  # Calculate the average backorder cost for the item
        else
            InvPrd = min((CurrInvList[i]/ExpFutDemand[i]), prd-2)
            EndInv = CurrInvList[i] - ExpFutDemand[i]*InvPrd
            #println("InvPrd: $InvPrd, End Inv: $EndInv")
            if EndInv > 0
                AvgInvCostList[i] = ((((CurrInvList[i] + EndInv) * InvPrd)/2)* Data.h[i]) +  EndInv*Data.h[i]
                AvgBkCostList[i] = 0.0
                #println("Avg Inv Cost: $AvgInvCost, Avg Bk Cost: $AvgBkCost")
            else
                AvgInvCostList[i] = ((((CurrInvList[i] + EndInv) * InvPrd)/2)* Data.h[i])
                BkPrd = prd - 2 - InvPrd
                EndBk = ExpFutDemand[i]*BkPrd
                AvgBkCostList[i] = ((EndBk * BkPrd)/2) * Data.b[i]  + EndBk*Data.ep[i]              # Calculate the average backorder cost for the item
                #println("Avg Inv Cost: $AvgInvCost, Avg Bk Cost: $AvgBkCost")
            end
        end
    end

    AvgInvCostInit = sum(AvgInvCostList)
    AvgBkCostInit = sum(AvgBkCostList)

    # Main loop to improve the production quantities
    while true

        if all(ToBeImprove .== false)                 # If there is no item that can be improved further,
            if Comparison                             # If comparison with fixed costs is needed
                AvgInvCostAft = sum(AvgInvCostList)     
                AvgBkCostAft = sum(AvgBkCostList)
                TotalSav = (AvgBkCostInit - AvgBkCostAft) - (AvgInvCostAft - AvgInvCostInit)            # Calculate the total savings: total reduction in backorder cost - total increase in inventory cost
                Production = (any(CurrSol .> 0) ? 1 : 0)                                                # Fixed production cost is incurred if there is any production
                Powder = maximum((CurrSol .> 0) .* Data.BH)                                             # Powder cost is based on the maximum build height among all items being produced
                ProdCost = Production * Data.c
                PowderCost = Powder * Data.pd
                FixedCost = ProdCost + PowderCost
                if TotalSav < FixedCost                                                                 # If the total savings is less than the fixed costs,                        
                    return zeros(Int64, Data.Nᵢ)                                                        # Return zero production for all items                                      
                else                                                                                    # Otherwise,                             
                    return CurrSol                                                                      # Return the current solution                              
                end
            else                                                                                        # If no comparison is needed,                                           
                return CurrSol                                                                          # Directly return the current solution             
            end
        end

        MaxBkFut = 0.0
        MaxBkFutIdx = 0
        for i in 1:Data.Nᵢ                                                                            
            if ToBeImprove[i]
                Bk = BkFut[i]
                if Bk > MaxBkFut
                    MaxBkFut = Bk
                    MaxBkFutIdx = i
                end
            end
        end

        if MaxBkFut == 0.0                                                                              # If there is no backorder left, 
            if Comparison                                                                               # Check if comparison with fixed costs is needed
                AvgInvCostAft = sum(AvgInvCostList)
                AvgBkCostAft = sum(AvgBkCostList)
                TotalSav = (AvgBkCostInit - AvgBkCostAft) - (AvgInvCostAft - AvgInvCostInit)            # Calculate the total savings: total reduction in backorder cost - total increase in inventory cost
                Production = (any(CurrSol .> 0) ? 1 : 0)                                                # Fixed production cost is incurred if there is any production
                Powder = maximum((CurrSol .> 0) .* Data.BH)                                             # Powder cost is based on the maximum build height among all items being produced
                ProdCost = Production * Data.c
                PowderCost = Powder * Data.pd
                FixedCost = ProdCost + PowderCost                                                       # Calculate the fixed costs: production cost + powder cost 
                if TotalSav < FixedCost                                                                 # If the total savings is less than the fixed costs,                         
                    return zeros(Int64, Data.Nᵢ)                                                        # Return zero production for all items                                          
                else
                    return CurrSol                                                                      # Return the current solution                              
                end
            else
                return CurrSol                                                                          # Directly return the current solution             
            end
        end

        # Check the capacity of build chamber and maximum inventory level constraints
        PerspTotalQty = sum(CurrSol) + 1
        PerspInv = CurrInvList[MaxBkFutIdx] + 1.0
        if (PerspTotalQty > Data.Cap) || (PerspInv > Data.MaxI[MaxBkFutIdx])                            # If any of the constraints is violated,
            ToBeImprove[MaxBkFutIdx] = false                                                            # Mark that the production quantity for the item can no longer be improved
            #println("Exceeded capacity, reverting increase for item $i")
            continue
        end
        #println("New Inventory Level for Item $i: $(CurrInvList[i])")

        AvgInvCost = AvgInvCostList[MaxBkFutIdx]
        AvgBkCost = AvgBkCostList[MaxBkFutIdx]

        InvPrd = min((PerspInv/ExpFutDemand[MaxBkFutIdx]), prd-2)
        EndInv = PerspInv - ExpFutDemand[MaxBkFutIdx]*InvPrd
        #println("InvPrd N: $InvPrd, End Inv N: $EndInv")
        if EndInv > 0.0
            AvgInvCostNew = ((((PerspInv + EndInv) * InvPrd)/2)* Data.h[MaxBkFutIdx]) +  EndInv*Data.h[MaxBkFutIdx]
            AvgBkCostNew = 0.0
            #println("Avg Inv N Cost: $AvgInvCost, Avg Bk N Cost: $AvgBkCost")
            #println("Avg Inv N Cost: $AvgInvCostNew, Avg Bk N Cost: $AvgBkCostNew")
        else
            AvgInvCostNew = ((((PerspInv + EndInv) * InvPrd)/2)* Data.h[MaxBkFutIdx])
            BkPrd = prd - 2 - InvPrd
            EndBk = ExpFutDemand[MaxBkFutIdx]*BkPrd
            AvgBkCostNew = ((EndBk * BkPrd)/2) * Data.b[MaxBkFutIdx]  + EndBk*Data.ep[MaxBkFutIdx] # Calculate the average backorder cost for the item
            #println("Avg Inv N Cost: $AvgInvCost, Avg Bk N Cost: $AvgBkCost")
            #println("Avg Inv N Cost: $AvgInvCostNew, Avg Bk N Cost: $AvgBkCostNew")
        end
        DiffInvCost = abs(AvgInvCostNew - AvgInvCost)
        DiffBkordCost = abs(AvgBkCostNew - AvgBkCost)
        if DiffInvCost <= DiffBkordCost                                                             # If the increase in production quantity results in a decrease in backorder cost >= the increase in inventory cost, accept the new solution
            #println("Invdiff: $DiffInvCost, Bkorddiff: $DiffBkordCost") 
            AvgInvCostList[MaxBkFutIdx] = AvgInvCostNew
            AvgBkCostList[MaxBkFutIdx] = AvgBkCostNew
            CurrSol[MaxBkFutIdx] += 1   
            CurrInvList[MaxBkFutIdx] = PerspInv
            Bk = abs(PerspInv - (ExpFutDemand[MaxBkFutIdx] * (prd-2)))
            if Bk == 0.0
                ToBeImprove[MaxBkFutIdx] = false
            end
        else                                                                                       # If not, don't accept the increase in production quantity  
            #println("Invdiff: $DiffInvCost, Bkorddiff: $DiffBkordCost") 
            ToBeImprove[MaxBkFutIdx] = false                                                       # Mark that the production quantity for the item can no longer be improved
        end
    end
end

# Test

#s = 2
#prd = 9
#sol = FindProdQty(Data, Info, s, prd)
