# This is to create a function that applies the heuristic to determine the produciton quantity
# Heuristic C: Prioritize the item with the highest backorder level to be increase first
# Before returning the solution, compare the total savings in inventory and backorder costs with the fixed production and powder costs

# Import packages
using Random

# Define the function 
function FindProdQtyC1(Data::DefMDPData, Info::DefMDPInfo, s::Int64, prd::Int64)

    MaxTotalSav = -Inf
    OptSol = zeros(Int, Data.Nᵢ)
    OptComparison  = false
    α = 0.2
    for _ in 1:20
        # If there is no period to go, no production is needed
        if prd <= 1
            return zeros(Int64, Data.Nᵢ)
        end

        # Preallocations
        CurrSol      = zeros(Int, Data.Nᵢ)
        CurrInvList  = Vector{Float64}(undef, Data.Nᵢ)
        InitBk   = Vector{Float64}(undef, Data.Nᵢ)

        # Calculate the expected future demand for each item
        ExpFutDemand = zeros(Float64, Data.Nᵢ)
        for j in 1:length(Data.D)
            ExpFutDemand .+= Data.D[j] .* Data.ProbD[j]
        end

        # Get the current inventory levels and initial backorder levels for all items
        CurrInvList = [Info.It1[s], Info.It2[s], Info.It3[s], Info.It4[s]]
        CurrInvList = max.(CurrInvList .- ExpFutDemand, Data.MinI)
        InitBk = (abs.(min.(CurrInvList, 0)))
            
        # The lost sales cost is assumed to be very high, production when backorder occurs is necessary
        # Start by fulfilling the backorder quantities first
        while true
            r = rand()
            MaxBk = 0.0
            MaxBkIdx = 0
            Bk = 0.0
            if (r < α) && (sum(InitBk .>= 1.0) > 1)
                MaxBkList = Float64[]
                MaxBkIdxList = Int64[]
                for i in 1:Data.Nᵢ
                    push!(MaxBkList, InitBk[i])
                    push!(MaxBkIdxList, i)
                end
                deleteat!(MaxBkList, argmax(MaxBkList))
                deleteat!(MaxBkIdxList, argmax(MaxBkList))
                MaxBk = maximum(MaxBkList)
                MaxBkIdx = MaxBkIdxList[argmax(MaxBkList)]
                Bk = InitBk[argmax(MaxBkList)]
            else
                for i in 1:Data.Nᵢ
                    Bk = InitBk[i]
                    if Bk > MaxBk
                        MaxBk = Bk
                        MaxBkIdx = i
                    end
                end
            end
            if MaxBk < 1.0                                # If there is no integral backorder left to be fulfilled,
                break                                           # Exit the loop
            else                                                # Otherwise, 
                CurrSol[MaxBkIdx] += 1                          # Increase its production quantity by 1 unit
                if sum(CurrSol) >= Data.Cap                     # If the space of build chamber is reached, 
                    break
                else                                            # Otherwise,        
                    CurrInvList[MaxBkIdx] += 1.0                # Update the inventory level for the item
                    InitBk[MaxBkIdx] -= 1.0                      # Update the backorder level for the item
                end
            end
        end

        if sum(CurrSol) >= Data.Cap
            return CurrSol
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
            BkFut[i] = abs(CurrInvList[i] - (ExpFutDemand[i] * (prd- 2)))
                
            if BkFut[i] <= 0.0
                ToBeImprove[i] = false
            end

            if CurrInvList[i] <= 0.0
                InvPrd = 0.0
                AvgInvCostList[i] = 0.0
                BkPrd = prd - 2 - InvPrd
                EndBk = CurrInvList[i] + ExpFutDemand[i]*BkPrd
                AvgBkCostList[i] = (((CurrInvList[i] + EndBk) * BkPrd)/2) * Data.b[i]  + EndBk*Data.ep[i]                  # Calculate the average backorder cost for the item
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
                break
            end

            r = rand()
            MaxBkFut = 0.0
            MaxBkFutIdx = 0
            if r < α && (sum(ToBeImprove) > 1)
                MaxBkList = Float64[]
                MaxBkIdxList = Int64[]
                for i in 1:Data.Nᵢ
                    if ToBeImprove[i]
                        push!(MaxBkList, BkFut[i])
                        push!(MaxBkIdxList, i)
                    end
                end
                deleteat!(MaxBkList, argmax(MaxBkList))
                deleteat!(MaxBkIdxList, argmax(MaxBkList))
                MaxBkFut = maximum(MaxBkList)
                MaxBkFutIdx = MaxBkIdxList[argmax(MaxBkList)]
            else
                for i in 1:Data.Nᵢ
                    if ToBeImprove[i]
                        Bk = BkFut[i]
                        if Bk > MaxBkFut
                            MaxBkFut = Bk
                            MaxBkFutIdx = i
                        end
                    end
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
                if Bk <= 0.0
                    ToBeImprove[MaxBkFutIdx] = false
                end
            else                                                                                       # If not, don't accept the increase in production quantity  
                #println("Invdiff: $DiffInvCost, Bkorddiff: $DiffBkordCost") 
                ToBeImprove[MaxBkFutIdx] = false                                                       # Mark that the production quantity for the item can no longer be improved
            end
        end
        
        AvgInvCostAft = sum(AvgInvCostList)     
        AvgBkCostAft = sum(AvgBkCostList)
        TotalSav = (AvgBkCostInit - AvgBkCostAft) - (AvgInvCostAft - AvgInvCostInit)            # Calculate the total savings: total reduction in backorder cost - total increase in inventory cost
        if TotalSav > MaxTotalSav
            MaxTotalSav = TotalSav
            OptSol = CurrSol
            OptComparison = Comparison
        end
    end

    if OptComparison                             # If comparison with fixed costs is needed
        Production = (any(OptSol .> 0) ? 1 : 0)                                                # Fixed production cost is incurred if there is any production
        Powder = maximum((OptSol .> 0) .* Data.BH)                                             # Powder cost is based on the maximum build height among all items being produced
        ProdCost = Production * Data.c
        PowderCost = Powder * Data.pd
        FixedCost = ProdCost + PowderCost
        if MaxTotalSav < FixedCost                                                              # If the total savings is less than the fixed costs,                        
            return zeros(Int64, Data.Nᵢ)                                                        # Return zero production for all items                                      
        else                                                                                    # Otherwise,                             
            return OptSol                                                                      # Return the current solution                              
        end
    else                                                                                        # If no comparison is needed,
        return OptSol
    end
end

# Test

#s = 1
#prd = 5
#sol = FindProdQtyC1(Data, Info, s, prd)
