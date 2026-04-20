# This is to create a function that applies the heuristic to determine the produciton quantity
# Heuristic D: Similar to Heuristic A, but the amount of backorder is bounded and the lost sales is incurred
# if the backorder exceeds the maximum allowable backorder level for an item

# Define the function 
function FindProdQtyD(Data::DefMDPData, Info::DefMDPInfo, s::Int64, prd::Int64)

    # If there is no period left to go, no production quantity to be made
    if prd <= 1
        return zeros(Int64, Data.Nᵢ)
    end

    # Preallocations
    CurrSol      = zeros(Int, Data.Nᵢ)
    CurrInvList  = Vector{Float64}(undef, Data.Nᵢ)
    InitBk   = Vector{Float64}(undef, Data.Nᵢ)

    # Get the current inventory levels and initial backorder levels
    CurrInvList = [Info.It1[s], Info.It2[s], Info.It3[s], Info.It4[s]]
    InitBk = (abs.(min.(CurrInvList, 0)))
        
    # Assuming no production when backorder occurs is not acceptable as the lost sales cost is very high
    # Start by fulfilling all backorders first
    while true
        MaxBk = 0.0
        MaxBkIdx = 0
        for i in 1:Data.Nᵢ              # Loop through all items to find the item with the highest backorder level
            Bk = InitBk[i]
            if Bk > MaxBk
                MaxBk = Bk
                MaxBkIdx = i
            end
        end
        if MaxBk == 0.0                 # If the hihest backorder level is 0, all backorders have been fulfilled
            break
        else                            # Otherwise, increase the production quantity for that item by 1 unit
            CurrSol[MaxBkIdx] += 1                           
            if sum(CurrSol) >= Data.Cap # If the capacity of the build chamber is reached, return the current solution
                return CurrSol
            else                        # Otherwise, update the current inventory and initial backorder levels
                CurrInvList[MaxBkIdx] += 1.0    
                InitBk[MaxBkIdx] -= 1.0
            end
        end
    end

    # Calculate the projected future demand for each item
    ExpFutDemand = zeros(Float64, Data.Nᵢ)
    for j in 1:length(Data.D)
        ExpFutDemand .+= Data.D[j] .* Data.ProbD[j]
    end

    # Preallocations
    ToBeImprove     = fill(true, Data.Nᵢ)
    AvgInvCostList  = zeros(Float64, Data.Nᵢ)
    AvgBkCostList   = zeros(Float64, Data.Nᵢ)
    BkFut           = Vector{Float64}(undef, Data.Nᵢ)

    # Calculate the initial average inventory and backorder costs for each item based on the current solution
    for i in 1:Data.Nᵢ
        BkFut[i] = abs(CurrInvList[i] - (ExpFutDemand[i] * (prd-2)))
            
        if BkFut[i] == 0.0
            ToBeImprove[i] = false
        end

        if CurrInvList[i] == 0.0
            InvPrd = 0.0
            AvgInvCostList[i] = 0.0
            BkPrd = prd - 2 - InvPrd
            EndBk = clamp(ExpFutDemand[i]*BkPrd, 0, Data.MinI[i])                                  # Calculate the end backorder level, bounded by the maximum allowable backorder level
            LS = max(ExpFutDemand[i]*BkPrd - Data.MinI[i], 0)                                      # Calculate the lost sales if the backorder exceeds the maximum allowable backorder level  
            AvgBkCostList[i] = ((EndBk * BkPrd)/2) * Data.b[i]  + EndBk*Data.ep[i] + LS*Data.ls[i] # Calculate the average backorder cost for the item
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
                EndBk = clamp(ExpFutDemand[i]*BkPrd, 0, Data.MinI[i])                              # Calculate the end backorder level, bounded by the maximum allowable backorder level
                LS = max(ExpFutDemand[i]*BkPrd - Data.MinI[i], 0)                                  # Calculate the lost sales if the backorder exceeds the maximum allowable backorder level    
                AvgBkCostList[i] = ((EndBk * BkPrd)/2) * Data.b[i]  + EndBk*Data.ep[i] + LS*Data.ls[i] # Calculate the average backorder cost for the item
                #println("Avg Inv Cost: $AvgInvCost, Avg Bk Cost: $AvgBkCost")
            end
        end
    end


    # Start the heuristics until either no further improvement can be made or the space of build chamber is fully utilized
    while true

        if all(ToBeImprove .== false)
            return CurrSol
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

        if MaxBkFut == 0.0
            return CurrSol
        end

        # Check if the space of build chamber is reached
        PerspTotalQty = sum(CurrSol) + 1
        PerspInv = CurrInvList[MaxBkFutIdx] + 1.0
        if (PerspTotalQty > Data.Cap) || (PerspInv > Data.MaxI[MaxBkFutIdx]) 
            ToBeImprove[MaxBkFutIdx] = false              # Mark that the production quantity for the item can no longer be improved
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
            EndBk = clamp(ExpFutDemand[MaxBkFutIdx]*BkPrd, 0, Data.MinI[MaxBkFutIdx])       # Calculate the end backorder level, bounded by the maximum allowable backorder level
            LS = max(ExpFutDemand[MaxBkFutIdx]*BkPrd - Data.MinI[MaxBkFutIdx], 0)           # Calculate the lost sales if the backorder exceeds the maximum allowable backorder level for an item
            AvgBkCostNew = ((EndBk * BkPrd)/2) * Data.b[MaxBkFutIdx]  + EndBk*Data.ep[MaxBkFutIdx] + LS*Data.ls[MaxBkFutIdx] # Calculate the average backorder cost for the item
            #println("Avg Inv N Cost: $AvgInvCost, Avg Bk N Cost: $AvgBkCost")
            #println("Avg Inv N Cost: $AvgInvCostNew, Avg Bk N Cost: $AvgBkCostNew")
        end
        DiffInvCost = abs(AvgInvCostNew - AvgInvCost)
        DiffBkordCost = abs(AvgBkCostNew - AvgBkCost)
        if DiffInvCost <= DiffBkordCost                                         # If the increase in production quantity results in a decrease in backorder cost >= the increase in inventory cost, accept the new solution   
            #println("Invdiff: $DiffInvCost, Bkorddiff: $DiffBkordCost") 
            AvgInvCostList[MaxBkFutIdx] = AvgInvCostNew
            AvgBkCostList[MaxBkFutIdx] = AvgBkCostNew
            CurrSol[MaxBkFutIdx] += 1
            CurrInvList[MaxBkFutIdx] = PerspInv
            Bk = abs(PerspInv - (ExpFutDemand[MaxBkFutIdx] * (prd-2)))
            if Bk == 0.0
                ToBeImprove[MaxBkFutIdx] = false
            end
        else                                                                    # If not, don't accept the increase in production quantity 
            #println("Invdiff: $DiffInvCost, Bkorddiff: $DiffBkordCost") 
            ToBeImprove[MaxBkFutIdx] = false                                    # Mark that the production quantity for the item can no longer be improved
        end
    end
end

# Test

#s = 2
#prd = 9
#sol = FindProdQty(Data, Info, s, prd)
