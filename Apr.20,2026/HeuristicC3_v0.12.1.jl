# This is to create a function that applies the heuristic to determine the produciton quantity
# Heuristic C2: Prioritize the item with the highest backorder level to be increase first
# Before returning the solution, compare the total savings in inventory and backorder costs with the fixed production and powder costs

# Import packages
using Random

# Import customized function
include("Estimate_v0.12.jl")

# Define the function 
function FindProdQtyC3(Data::DefMDPData, InitInvList::Vector{Int64}, prd::Int64)

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
        CurrSol  = zeros(Int, Data.Nᵢ)
        InitBk   = Vector{Float64}(undef, Data.Nᵢ)

        # Get the current inventory levels and initial backorder levels for all items
        for i in 1:Data.Nᵢ
            AvgEndBk = EstimatePre(i, Data, InitInvList[i])
            InitBk[i] = min(AvgEndBk, abs(Data.MinI[i]))
        end
        #println("InitBk = $InitBk")
        #println("Initial Inventory Level : $(CurrInvList)")   
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
            if MaxBk < 1.0                                # If there is less than 1 expected backorder to fulfill
                break                                           # Exit the loop
            else                                                # Otherwise, 
                CurrSol[MaxBkIdx] += 1                          # Increase its production quantity by 1 unit
                if sum(CurrSol) >= Data.Cap                     # If the space of build chamber is reached, 
                    break
                else                                            # Otherwise,        
                    InitBk[MaxBkIdx] -= 1.0                      # Update the backorder level for the item
                end
            end
        end

        if sum(CurrSol) >= Data.Cap
            return CurrSol
        end
        #println("Current Sol = $CurrSol")

        # Preallocations
        ToBeImprove     = fill(true, Data.Nᵢ)
        AvgInvCostList1  = zeros(Float64, Data.Nᵢ)
        AvgBkCostList1   = zeros(Float64, Data.Nᵢ)
        AvgInvCostList2 = zeros(Float64, Data.Nᵢ)
        AvgBkCostList2 = zeros(Float64, Data.Nᵢ)
        Savings        = zeros(Float64, Data.Nᵢ)
        BkFut        = zeros(Float64, Data.Nᵢ)
        Comparison = false
        if sum(CurrSol) == 0                    # If there is no production in the current solution (no current backorder)
            Comparison = true                   # Set to compare the savings with fixed costs later
        end
        #println("Initial solution : $(CurrSol)")
        # Calculate the initial average inventory and backorder costs for all items
        for i in 1:Data.Nᵢ
            
            AvgInv, AvgBk, AvgEndInv, AvgEndBk = Estimate(i, prd-1, Data, InitInvList[i], CurrSol[i])
            #println(AvgInv)
            #println(AvgBk)
            #println(AvgEndInv)
            #println(AvgEndBk)

            BkFut[i] = AvgEndBk
                
            if BkFut[i] <= 0.0
                ToBeImprove[i] = false
            end

            AvgBkCostList1[i] = AvgBk * Data.b[i] + AvgEndBk * Data.ep[i]
            AvgInvCostList1[i] = AvgInv* Data.h[i] + AvgEndInv*Data.h[i] 

            # Calculate the savings
            PerspSol = CurrSol[i] + 1

            AvgInv, AvgBk, AvgEndInv, AvgEndBk = Estimate(i, prd-1, Data, InitInvList[i], PerspSol)

            #println(AvgInv)
            #println(AvgBk)
            #println(AvgEndInv)
            #println(AvgEndBk)

            AvgBkCostList2[i] = AvgBk * Data.b[i] + AvgEndBk * Data.ep[i]
            AvgInvCostList2[i] = AvgInv* Data.h[i] + AvgEndInv*Data.h[i]

            Savings[i] = abs(AvgBkCostList1[i] - AvgBkCostList2[i]) - abs(AvgInvCostList2[i] - AvgInvCostList1[i])
            #println("Savings: $Savings, Bk1: $(AvgBkCostList1[i]), Bk2: $(AvgBkCostList2[i]), Inv1: $(AvgInvCostList1[i]), Inv2: $(AvgInvCostList2[i]) ")
            if Savings[i] < 0
                ToBeImprove[i] = false
            end
        end

        AvgInvCostInit = sum(AvgInvCostList1)
        AvgBkCostInit = sum(AvgBkCostList1)
        
        # Main loop to improve the production quantities
        while true
            #println("ToBeImprove: $ToBeImprove")
            if all(ToBeImprove .== false)                 # If there is no item that can be improved further,
                break
            end

            r = rand()
            MaxSv = 0.0
            MaxSvIdx = 0
            if r < α && (sum(ToBeImprove) > 1)
                MaxSvList = Float64[]
                MaxSvIdxList = Int64[]
                for i in 1:Data.Nᵢ
                    if ToBeImprove[i]
                        push!(MaxSvList, Savings[i])
                        push!(MaxSvIdxList, i)
                    end
                end
                deleteat!(MaxSvIdxList, argmax(MaxSvList))
                deleteat!(MaxSvList, argmax(MaxSvList))
                MaxSv = maximum(MaxSvList)
                MaxSvIdx = MaxSvIdxList[argmax(MaxSvList)]
            else
                for i in 1:Data.Nᵢ
                    if ToBeImprove[i]
                        Sv = Savings[i]
                        if Sv > MaxSv
                            MaxSv = Sv
                            MaxSvIdx = i
                        end
                    end
                end
            end
            #println("Pick item $(MaxSvIdx) to increase")

            # Check the capacity of build chamber and maximum inventory level constraints
            PerspTotalQty = sum(CurrSol) + 1
            PerspInv = InitInvList[MaxSvIdx] + CurrSol[MaxSvIdx] + 1.0
            if (PerspTotalQty > Data.Cap) || (PerspInv > Data.MaxI[MaxSvIdx])                            # If any of the constraints is violated,
                ToBeImprove[MaxSvIdx] = false                                                            # Mark that the production quantity for the item can no longer be improved
                #println("Exceeded capacity, reverting increase for item $MaxSvIdx")
                continue
            end
            #println("New solution : $(CurrSol)")

            # Update the invnetory level
            AvgInvCostList1[MaxSvIdx] = AvgInvCostList2[MaxSvIdx]
            AvgBkCostList1[MaxSvIdx] = AvgBkCostList2[MaxSvIdx]
            CurrSol[MaxSvIdx] += 1   
            #println("New solution : $(CurrSol)")

            # Update the savings for the item that has been increase
            PerspSol = CurrSol[MaxSvIdx] + 1

            AvgInv, AvgBk, AvgEndInv, AvgEndBk = Estimate(MaxSvIdx, prd-1, Data, InitInvList[MaxSvIdx], PerspSol)

            #println(AvgInv)
            #println(AvgBk)
            #println(AvgEndInv)
            #println(AvgEndBk)

            AvgBkCostList2[MaxSvIdx] = AvgBk * Data.b[MaxSvIdx] + AvgEndBk * Data.ep[MaxSvIdx]
            AvgInvCostList2[MaxSvIdx] = AvgInv* Data.h[MaxSvIdx] + AvgEndInv*Data.h[MaxSvIdx]

            Savings[MaxSvIdx] = abs(AvgBkCostList1[MaxSvIdx] - AvgBkCostList2[MaxSvIdx]) - abs(AvgInvCostList2[MaxSvIdx] - AvgInvCostList1[MaxSvIdx])
            #println("New Savings: $Savings, Bk1: $(AvgBkCostList1[MaxSvIdx]), Bk2: $(AvgBkCostList2[MaxSvIdx]), Inv1: $(AvgInvCostList1[MaxSvIdx]), Inv2: $(AvgInvCostList2[MaxSvIdx]) ")
            if Savings[MaxSvIdx] < 0
                ToBeImprove[MaxSvIdx] = false
            end
        end
        
        AvgInvCostAft = sum(AvgInvCostList1)     
        AvgBkCostAft = sum(AvgBkCostList1)
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
#init_inv = [-2, -2, 1, 2]
#prd = 4
#sol = FindProdQtyC3(Data, init_inv, prd)
