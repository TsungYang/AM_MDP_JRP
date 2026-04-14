# This is to create a function that applies the heuristic to determine the produciton quantity
# Heuristic B: Prioritize the item with the highest backorder cost to be increased first.

# Define the function 
function FindProdQtyB(Data::DefMDPData, Info::DefMDPInfo, s::Int64, prd::Int64)

    # If there is no periods to go, no production is needed
    if prd <= 1
        return zeros(Int64, Data.Nᵢ)
    end

    # Preallocations
    CurrSol      = zeros(Int, Data.Nᵢ)
    CurrInvList  = Vector{Float64}(undef, Data.Nᵢ)
    InitBk   = Vector{Float64}(undef, Data.Nᵢ)

    # Get the current inventory level and initial backorder cost for each item
    CurrInvList = [Info.It1[s], Info.It2[s], Info.It3[s], Info.It4[s]]
    InitBk = (abs.(min.(CurrInvList, 0))) .* Data.b
        
    # Lost sales cost is assumed to be very high, production when backorder occurs is necessary
    # Start by fulfilling the backorder quantities first
    while true
        MaxBk = 0.0
        MaxBkIdx = 0
        for i in 1:Data.Nᵢ              # For each item, find the one with the highest backorder cost
            Bk = InitBk[i]
            if Bk > MaxBk
                MaxBk = Bk
                MaxBkIdx = i
            end
        end
        if MaxBk == 0.0                 # If there is no backorder cost, break the loop
            break
        else                            # Otherwise, 
            CurrSol[MaxBkIdx] += 1      # Increase its production quantity by 1 unit
            if sum(CurrSol) >= Data.Cap # If the space of build chamber is reached,
                return CurrSol          # return the current solution
            else
                CurrInvList[MaxBkIdx] += 1.0              # Update the current inventory level
                InitBk[MaxBkIdx] -= Data.b[MaxBkIdx]      # Update the backorder cost
            end
        end
    end

    # Calculate the projected future demand for each item over the remaining periods
    ExpFutDemand = zeros(Float64, Data.Nᵢ)
    for j in 1:length(Data.D)
        ExpFutDemand .+= Data.D[j] .* Data.ProbD[j]
    end

    # Preallocations
    ToBeImprove     = fill(true, Data.Nᵢ)
    AvgInvCostList  = zeros(Float64, Data.Nᵢ)
    AvgBkCostList   = zeros(Float64, Data.Nᵢ)
    BkFut           = Vector{Float64}(undef, Data.Nᵢ)

    # Calculate the initial average inventory cost and backorder cost for each item over the remaining periods after fulfilling the current backorders
    for i in 1:Data.Nᵢ
        BkFut[i] = abs(CurrInvList[i] - (ExpFutDemand[i] * (prd-2))) * Data.b[i]            # Calcuate the projected backorder cost for the item
            
        if BkFut[i] == 0.0                              # If there is no projected backorder cost, mark that the production quantity for the item can no longer be improved                          
            ToBeImprove[i] = false          
        end

        if CurrInvList[i] == 0.0                        # If there is no current inventory, 
            InvPrd = 0.0                                #set inventory period to 0                          
            AvgInvCostList[i] = 0.0                     # Set average inventory cost to 0
            BkPrd = prd - 2 - InvPrd                    # Compute the number of periods with backorder
            EndBk = ExpFutDemand[i]*BkPrd               # Compute the end of backorder level
            AvgBkCostList[i] = ((EndBk * BkPrd)/2) * Data.b[i]  + EndBk*Data.ep[i]                                  # Calculate the average backorder cost for the item
        else                                                                                                        # If there is current inventory,
            InvPrd = min((CurrInvList[i]/ExpFutDemand[i]), prd-2)                                                   # Compute number of periods before running out of inventory
            EndInv = CurrInvList[i] - ExpFutDemand[i]*InvPrd                                                        # Compute end inventory level
            #println("InvPrd: $InvPrd, End Inv: $EndInv")
            if EndInv > 0                                                                                           # If there is inventory left at the end of periods,  
                AvgInvCostList[i] = ((((CurrInvList[i] + EndInv) * InvPrd)/2)* Data.h[i]) +  EndInv*Data.h[i]       # Calculate the average inventory cost for the item
                AvgBkCostList[i] = 0.0                                                                              # Set average backorder cost to 0                                       
                #println("Avg Inv Cost: $AvgInvCost, Avg Bk Cost: $AvgBkCost")
            else                                                                                                    # If there is no inventory left at the end of periods,  
                AvgInvCostList[i] = ((((CurrInvList[i] + EndInv) * InvPrd)/2)* Data.h[i])                           # Calculate the average inventory cost for the item
                BkPrd = prd - 2 - InvPrd                                                                            # Compute the number of periods with backorder
                EndBk = ExpFutDemand[i]*BkPrd                                                                       # Compute the end of backorder level
                AvgBkCostList[i] = ((EndBk * BkPrd)/2) * Data.b[i]  + EndBk*Data.ep[i]                              # Calculate the average backorder cost for the item
                #println("Avg Inv Cost: $AvgInvCost, Avg Bk Cost: $AvgBkCost")
            end
        end
    end


    # Main loop to iteratively improve the production quantities until no further improvement is possible
    while true

        if all(ToBeImprove .== false)               # If no production quantities can be improved, return the current solution
            return CurrSol
        end

        # Loop through each item to find the one with the highest projected backorder cost that can be improved
        MaxBkFut = 0.0
        MaxBkFutIdx = 0
        for i in 1:Data.Nᵢ              # For each item, 
            if ToBeImprove[i]           # If the quantity can be improved,
                Bk = BkFut[i]           # get its projected backorder cost
                if Bk > MaxBkFut
                    MaxBkFut = Bk
                    MaxBkFutIdx = i
                end
            end
        end

        if MaxBkFut == 0.0              # If no projected backorder cost can be improved, return the current solution
            return CurrSol
        end

        # Check the capacity of build chamber and maximum inventory level constraints
        PerspTotalQty = sum(CurrSol) + 1                                            # Projected production quantity after increasing the production quantity by 1 for the item with highest projected backorder                     
        PerspInv = CurrInvList[MaxBkFutIdx] + 1.0                                   # Projected inventory level for the item after increase                       
        if (PerspTotalQty > Data.Cap) || (PerspInv > Data.MaxI[MaxBkFutIdx])        # If any of the constraints is violated,
            ToBeImprove[MaxBkFutIdx] = false                                        # Mark that the production quantity for the item can no longer be improved
            #println("Exceeded capacity, reverting increase for item $i")
            continue
        end
        #println("New Inventory Level for Item $i: $(CurrInvList[i])")

        AvgInvCost = AvgInvCostList[MaxBkFutIdx]                                    # Get the current average inventory cost for the item   
        AvgBkCost = AvgBkCostList[MaxBkFutIdx]                                      # Get the current average backorder cost for the item                  

        InvPrd = min((PerspInv/ExpFutDemand[MaxBkFutIdx]), prd-2)                   # Compute number of periods before running out of inventory
        EndInv = PerspInv - ExpFutDemand[MaxBkFutIdx]*InvPrd                        # Compute end inventory level
        #println("InvPrd N: $InvPrd, End Inv N: $EndInv")
        if EndInv > 0.0                                                             # If there is inventory left at the end of periods,    
            AvgInvCostNew = ((((PerspInv + EndInv) * InvPrd)/2)* Data.h[MaxBkFutIdx]) +  EndInv*Data.h[MaxBkFutIdx]     # Calculate the average inventory cost for the item
            AvgBkCostNew = 0.0                                                                                          # Set average backorder cost to 0
            #println("Avg Inv N Cost: $AvgInvCost, Avg Bk N Cost: $AvgBkCost")
            #println("Avg Inv N Cost: $AvgInvCostNew, Avg Bk N Cost: $AvgBkCostNew")
        else                                                                        # If there is no inventory left at the end of periods,              
            AvgInvCostNew = ((((PerspInv + EndInv) * InvPrd)/2)* Data.h[MaxBkFutIdx])                                   # Calculate the average inventory cost for the item    
            BkPrd = prd - 2 - InvPrd                                                                                    # Compute the number of periods with backorder
            EndBk = ExpFutDemand[MaxBkFutIdx]*BkPrd                                                                     # Compute the end of backorder level                                  
            AvgBkCostNew = ((EndBk * BkPrd)/2) * Data.b[MaxBkFutIdx]  + EndBk*Data.ep[MaxBkFutIdx]                      # Calculate the average backorder cost for the item
            #println("Avg Inv N Cost: $AvgInvCost, Avg Bk N Cost: $AvgBkCost")
            #println("Avg Inv N Cost: $AvgInvCostNew, Avg Bk N Cost: $AvgBkCostNew")
        end
        DiffInvCost = abs(AvgInvCostNew - AvgInvCost)                               # Calculate the change in average inventory cost                          
        DiffBkordCost = abs(AvgBkCostNew - AvgBkCost)                               # Calculate the change in average backorder cost          
        if DiffInvCost <= DiffBkordCost                                             # If the decrease in backorder cost that >= the increase in inventory cost, accept the new solution
            #println("Invdiff: $DiffInvCost, Bkorddiff: $DiffBkordCost") 
            AvgInvCostList[MaxBkFutIdx] = AvgInvCostNew                             # Update the average inventory cost list
            AvgBkCostList[MaxBkFutIdx] = AvgBkCostNew                               # Update the average backorder cost list
            CurrSol[MaxBkFutIdx] += 1                                               # Accept the increase in production quantity              
            CurrInvList[MaxBkFutIdx] = PerspInv                                     # Update the current inventory level
            Bk = abs(PerspInv - (ExpFutDemand[MaxBkFutIdx] * (prd-2))) * Data.b[MaxBkFutIdx]        # Update the projected backorder cost for the item
            if Bk == 0.0                                                            # If there is no projected backorder cost, mark that the production quantity for the item can no longer be improved   
                ToBeImprove[MaxBkFutIdx] = false    
            end
        else                                                                       # Otherwise, don't accept the new solution and mark that the production quantity for the itme can no longer be improved     
            #println("Invdiff: $DiffInvCost, Bkorddiff: $DiffBkordCost") 
            ToBeImprove[MaxBkFutIdx] = false
        end
    end
end

# Test

#s = 2
#prd = 9
#sol = FindProdQty(Data, Info, s, prd)
