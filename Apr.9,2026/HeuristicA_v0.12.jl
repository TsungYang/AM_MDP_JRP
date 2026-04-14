# This is to create a function that applies the heuristic to determine the produciton quantity
# Heuristic C: Prioritize the item with the highest backorder quantity to be increased first.

# Define the function 
function FindProdQtyA(Data::DefMDPData, Info::DefMDPInfo, s::Int64, prd::Int64)

    # If there is no periods to go, no production is needed
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
    # Start by fulfilling the backorder quantities first
    while true
        MaxBk = 0.0                 
        MaxBkIdx = 0                
        for i in 1:Data.Nᵢ          # Loop through all items to find the item with the highest backorder quantity
            Bk = InitBk[i]          # Get the backorder quantity for the item
            if Bk > MaxBk           # If the backorder quantity is greater than the current maximum backorder
                MaxBk = Bk          # Update the maximum backorder
                MaxBkIdx = i        # Update the index of the item with maximum backorder
            end
        end
        if MaxBk == 0.0             # If there is no backorder for any item,
            break                   # Move to the next step
        else
            CurrSol[MaxBkIdx] += 1  # Increase the production quantity by 1 unit
            if sum(CurrSol) >= Data.Cap # If the space of build chamber is reaches its cpacity after the increase, return the current solution
                return CurrSol
            else                        # Otherwise, update the current inventory level and initiailize backorder level
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

    # Calculate the initial average inventory cost and backorder cost for each item based on the solution after fulfilling backorders
    for i in 1:Data.Nᵢ
        BkFut[i] = abs(CurrInvList[i] - (ExpFutDemand[i] * (prd-2)))                # Calculate the projected backorder level for the item   
        
        if BkFut[i] == 0.0                                                          # If there is no projected backorder for the item, no further improvement needed                                  
            ToBeImprove[i] = false
        end

        if CurrInvList[i] == 0.0                                                    # If the current inventory level is 0, no inventory cost incurred
            InvPrd = 0.0                                                            # Number of periods with inventory
            AvgInvCostList[i] = 0.0                                                 # Store the average inventroy cost as 0
            BkPrd = prd - 2 - InvPrd                                                # Number of periods with backorder
            EndBk = ExpFutDemand[i]*BkPrd                                           # Calculate the end backorder level for the item
            AvgBkCostList[i] = ((EndBk * BkPrd)/2) * Data.b[i]  + EndBk*Data.ep[i]  # Calculate the average backorder cost for the item
        else                                                                        # If the current inventory level is greater than 0, calculate both inventory cost and backorder cost
            InvPrd = min((CurrInvList[i]/ExpFutDemand[i]), prd-2)                   # Number of periods with inventory
            EndInv = CurrInvList[i] - ExpFutDemand[i]*InvPrd                        # Calculate the end inventory level for the item
            #println("InvPrd: $InvPrd, End Inv: $EndInv")
            if EndInv > 0                                                           # If there is inventory left at the end, no backorder cost incurred
                AvgInvCostList[i] = ((((CurrInvList[i] + EndInv) * InvPrd)/2)* Data.h[i]) +  EndInv*Data.h[i] # Inventory cost calculation
                AvgBkCostList[i] = 0.0                                                                        # Backorder cost is 0                                      
                #println("Avg Inv Cost: $AvgInvCost, Avg Bk Cost: $AvgBkCost")
            else                                                                                              # If there is backorder at the end, calculate both inventory cost and backorder cost
                AvgInvCostList[i] = ((((CurrInvList[i] + EndInv) * InvPrd)/2)* Data.h[i])                     # Inventory cost calculation
                BkPrd = prd - 2 - InvPrd                                                                      # Number of periods with backorder                                      
                EndBk = ExpFutDemand[i]*BkPrd                                                                 # End backorder level calculation                                   
                AvgBkCostList[i] = ((EndBk * BkPrd)/2) * Data.b[i]  + EndBk*Data.ep[i]                        # Calculate the average backorder cost for the item
                #println("Avg Inv Cost: $AvgInvCost, Avg Bk Cost: $AvgBkCost")
            end
        end
    end

    # Main loop to iteratively increase the production quantity based on the backorder cost and inventory cost
    while true

        # If there is no item that can be improved further, return the current solution
        if all(ToBeImprove .== false)
            return CurrSol
        end

        # Loop through all items to find the item with the highest projected backorder quantity
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

        if MaxBkFut == 0.0                  # If the maximum projected backorder is 0,
            return CurrSol                  # Return the current solution
        end

        # Check the capacity of build chamber and maximum inventory level constraints after increasing the production quantity by 1 for the item with highest projected backorder
        PerspTotalQty = sum(CurrSol) + 1                                        # Projected production quantity
        PerspInv = CurrInvList[MaxBkFutIdx] + 1.0                               # Projected inventory level for the item after increase
        if (PerspTotalQty > Data.Cap) || (PerspInv > Data.MaxI[MaxBkFutIdx])    # If any of the constraints is violated,
            ToBeImprove[MaxBkFutIdx] = false                                    # Mark that the production quantity for the item can no longer be improved
            #println("Exceeded capacity, reverting increase for item $i")
            continue
        end
        #println("New Inventory Level for Item $i: $(CurrInvList[i])")

        AvgInvCost = AvgInvCostList[MaxBkFutIdx]            # Record the current average inventory cost for comparison
        AvgBkCost = AvgBkCostList[MaxBkFutIdx]              # Record the current average backorder cost for comparison

        InvPrd = min((PerspInv/ExpFutDemand[MaxBkFutIdx]), prd-2)   # Number of periods with inventory
        EndInv = PerspInv - ExpFutDemand[MaxBkFutIdx]*InvPrd        # Calculate the end inventory level for the item
        #println("InvPrd N: $InvPrd, End Inv N: $EndInv")

        if EndInv > 0.0                                             # If there is inventory left at the end, no backorder cost incurred                                        
            AvgInvCostNew = ((((PerspInv + EndInv) * InvPrd)/2)* Data.h[MaxBkFutIdx]) +  EndInv*Data.h[MaxBkFutIdx]
            AvgBkCostNew = 0.0
            #println("Avg Inv N Cost: $AvgInvCost, Avg Bk N Cost: $AvgBkCost")
            #println("Avg Inv N Cost: $AvgInvCostNew, Avg Bk N Cost: $AvgBkCostNew")
        else                                                        # Otherwise, calculate both inventory cost and backorder cost
            AvgInvCostNew = ((((PerspInv + EndInv) * InvPrd)/2)* Data.h[MaxBkFutIdx])
            BkPrd = prd - 2 - InvPrd
            EndBk = ExpFutDemand[MaxBkFutIdx]*BkPrd
            AvgBkCostNew = ((EndBk * BkPrd)/2) * Data.b[MaxBkFutIdx]  + EndBk*Data.ep[MaxBkFutIdx] # Calculate the average backorder cost for the item
            #println("Avg Inv N Cost: $AvgInvCost, Avg Bk N Cost: $AvgBkCost")
            #println("Avg Inv N Cost: $AvgInvCostNew, Avg Bk N Cost: $AvgBkCostNew")
        end
        DiffInvCost = abs(AvgInvCostNew - AvgInvCost)           # Calculate the increase of inventory cost
        DiffBkordCost = abs(AvgBkCostNew - AvgBkCost)           # Calculate the reduction of backorder cost
        
        if DiffInvCost < DiffBkordCost                          # If the reduction in backorder cost is greater than the increase in inventory cost, keep the increase in production quantity
            #println("Invdiff: $DiffInvCost, Bkorddiff: $DiffBkordCost") 
            AvgInvCostList[MaxBkFutIdx] = AvgInvCostNew         # Update the average inventory cost list
            AvgBkCostList[MaxBkFutIdx] = AvgBkCostNew           # Update the average backorder cost list
            CurrSol[MaxBkFutIdx] += 1                           # Keep the increase in production quantity
            CurrInvList[MaxBkFutIdx] = PerspInv                 # Update the current inventory level
            Bk = abs(PerspInv - (ExpFutDemand[MaxBkFutIdx] * (prd-2)))  # Update the projected backorder level
            if Bk == 0.0                                                # If there is no projected backorder for the item after the increase,
                ToBeImprove[MaxBkFutIdx] = false                        # Mark that the production quantity for the item can no longer be improved
            end
        else                                                    # Otherwise, do not update the production quantity and mark that the item can no longer be improved
            #println("Invdiff: $DiffInvCost, Bkorddiff: $DiffBkordCost") 
            ToBeImprove[MaxBkFutIdx] = false
        end
    end
end

# Test
#s = 2418
#prd = 3
#sol = FindProdQtyA(Data, Info, s, prd)
