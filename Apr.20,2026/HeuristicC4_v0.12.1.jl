# This is to create a function that applies the heuristic to determine the produciton quantity
# Heuristic C4: Prioritize the item with the highest backorder level to be increase first
# Before returning the solution, compare the total savings in inventory and backorder costs with the fixed production and powder costs

# Import packages
using Random

# Define a function to calculate the projected inventory and backorder costs
function ProjInvBkCost(h::Float64, b::Float64, ep::Float64, CurrInv::Float64, prd::Int64, ExpFutDemand::Float64)
    EndInv = 0.0
    EndBk = 0.0
    AvgInvCost = 0.0
    AvgBkCost = 0.0
    if CurrInv <= 0.0
        InvPrd = 0.0
        AvgInvCost = 0.0
        BkPrd = prd - 2 - InvPrd
        EndBk = CurrInv + ExpFutDemand*BkPrd
        AvgBkCost = (((CurrInv + EndBk) * BkPrd)/2) * b + EndBk*ep  # Calculate the average backorder cost for the item
    else
        InvPrd = min((CurrInv/ExpFutDemand), prd-2)
        EndInv = CurrInv - ExpFutDemand*InvPrd
        #println("InvPrd: $InvPrd, End Inv: $EndInv")
        if EndInv > 0
            AvgInvCost = ((((CurrInv + EndInv) * InvPrd)/2)* h) + EndInv*h
            AvgBkCost = 0.0
            #println("Avg Inv Cost: $AvgInvCost, Avg Bk Cost: $AvgBkCost")
        else
            AvgInvCost = ((((CurrInv + EndInv) * InvPrd)/2)* h)
            BkPrd = prd - 2 - InvPrd
            EndBk = ExpFutDemand*BkPrd
            AvgBkCost = ((EndBk * BkPrd)/2) * b + EndBk*ep              # Calculate the average backorder cost for the item
            #println("Avg Inv Cost: $AvgInvCost, Avg Bk Cost: $AvgBkCost")
        end
    end
    return EndInv, EndBk, AvgInvCost, AvgBkCost
end

function MainLoop(IdxList::Vector{Int64}, CurrSol::Vector{Int64}, CurrInvList::Vector{Float64}, Data::DefMDPData, ExpFutDemand::Vector{Float64}, ToBeImprove::Vector{Bool}, AvgInvCostList1::Vector{Float64}, AvgBkCostList1::Vector{Float64}, AvgInvCostList2::Vector{Float64}, AvgBkCostList2::Vector{Float64}, Savings::Vector{Float64}, BkFut::Vector{Float64}, prd::Int64)

    # Main loop to improve the production quantities
    while true
        #println("ToBeImprove: $ToBeImprove")
        if all(ToBeImprove[IdxList] .== false)                 # If there is no item that can be improved further,
            break
        end

        r = rand()
        MaxSv = 0.0
        MaxSvIdx = 0
        α = 0.2
        if r < α && (sum(ToBeImprove[IdxList]) > 1)
            MaxSvList = Float64[]
            MaxSvIdxList = Int64[]
            for i in IdxList
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
            for i in IdxList
                if ToBeImprove[i]
                    Sv = Savings[i]
                    if Sv >= MaxSv
                        MaxSv = Sv
                        MaxSvIdx = i
                    end
                end
            end
        end
        #println("Pick item $(MaxSvIdx) to increase")
        # Check the capacity of build chamber and maximum inventory level constraints
        PerspTotalQty = sum(CurrSol) + 1
        PerspInv = CurrInvList[MaxSvIdx] + 1.0
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
        CurrInvList[MaxSvIdx] = PerspInv
        #println("New solution : $(CurrSol)")

        # Update the savings for the item that has been increase
        PerspInv = CurrInvList[MaxSvIdx] + 1.0

        EndInv, EndBk, AvgInvCost, AvgBkCost = ProjInvBkCost(Data.h[MaxSvIdx], Data.b[MaxSvIdx], Data.ep[MaxSvIdx], PerspInv, prd, ExpFutDemand[MaxSvIdx])
        AvgInvCostList2[MaxSvIdx] = AvgInvCost
        AvgBkCostList2[MaxSvIdx] = AvgBkCost
                    
        Savings[MaxSvIdx] = abs(AvgBkCostList1[MaxSvIdx] - AvgBkCostList2[MaxSvIdx]) - abs(AvgInvCostList2[MaxSvIdx] - AvgInvCostList1[MaxSvIdx])
        #println("New Savings: $Savings, Bk1: $(AvgBkCostList1[MaxSvIdx]), Bk2: $(AvgBkCostList2[MaxSvIdx]), Inv1: $(AvgInvCostList1[MaxSvIdx]), Inv2: $(AvgInvCostList2[MaxSvIdx]) ")
        if (Savings[MaxSvIdx] < 0)
            ToBeImprove[MaxSvIdx] = false
        end
    end
    return ToBeImprove, AvgInvCostList1, AvgBkCostList1, AvgInvCostList2, AvgBkCostList2, Savings, BkFut
end

function MainLoop2(IdxList::Vector{Int64}, CurrSol::Vector{Int64}, CurrInvList::Vector{Float64}, Data::DefMDPData, ExpFutDemand::Vector{Float64}, ToBeImprove::Vector{Bool}, AvgInvCostList1::Vector{Float64}, AvgBkCostList1::Vector{Float64}, AvgInvCostList2::Vector{Float64}, AvgBkCostList2::Vector{Float64}, Savings::Vector{Float64}, BkFut::Vector{Float64}, prd::Int64, FC::Float64)
 
    InitTotalInvCost = sum(AvgInvCostList1) 
    # Main loop to improve the production quantities
    while true
        #println("ToBeImprove: $ToBeImprove")
        if all(ToBeImprove[IdxList] .== false)                 # If there is no item that can be improved further,
            break
        end

        r = rand()
        MaxSv = 0.0
        MaxSvIdx = 0
        α = 0.2
        if r < α && (sum(ToBeImprove[IdxList]) > 1)
            MaxSvList = Float64[]
            MaxSvIdxList = Int64[]
            for i in IdxList
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
            for i in IdxList
                if ToBeImprove[i]
                    Sv = Savings[i]
                    if Sv >= MaxSv
                        MaxSv = Sv
                        MaxSvIdx = i
                    end
                end
            end
        end
        #println("Pick item $(MaxSvIdx) to increase")
        # Check the capacity of build chamber and maximum inventory level constraints
        PerspTotalQty = sum(CurrSol) + 1
        PerspInv = CurrInvList[MaxSvIdx] + 1.0
        if (PerspTotalQty > Data.Cap) || (PerspInv > Data.MaxI[MaxSvIdx]) || (sum(AvgInvCostList2) - InitTotalInvCost > FC)     # If any of the constraints is violated,
            ToBeImprove[MaxSvIdx] = false                                                            # Mark that the production quantity for the item can no longer be improved
            #println("Exceeded capacity, reverting increase for item $MaxSvIdx")
            continue
        end
        #println("New solution : $(CurrSol)")

        # Update the invnetory level
        AvgInvCostList1[MaxSvIdx] = AvgInvCostList2[MaxSvIdx]
        AvgBkCostList1[MaxSvIdx] = AvgBkCostList2[MaxSvIdx]
        CurrSol[MaxSvIdx] += 1   
        CurrInvList[MaxSvIdx] = PerspInv
        #println("New solution : $(CurrSol)")

        # Update the savings for the item that has been increase
        PerspInv = CurrInvList[MaxSvIdx] + 1.0

        EndInv, EndBk, AvgInvCost, AvgBkCost = ProjInvBkCost(Data.h[MaxSvIdx], Data.b[MaxSvIdx], Data.ep[MaxSvIdx], PerspInv, prd, ExpFutDemand[MaxSvIdx])
        AvgInvCostList2[MaxSvIdx] = AvgInvCost
        AvgBkCostList2[MaxSvIdx] = AvgBkCost
                    
        Savings[MaxSvIdx] = abs(AvgBkCostList1[MaxSvIdx] - AvgBkCostList2[MaxSvIdx]) - abs(AvgInvCostList2[MaxSvIdx] - AvgInvCostList1[MaxSvIdx])
        #println("New Savings: $Savings, Bk1: $(AvgBkCostList1[MaxSvIdx]), Bk2: $(AvgBkCostList2[MaxSvIdx]), Inv1: $(AvgInvCostList1[MaxSvIdx]), Inv2: $(AvgInvCostList2[MaxSvIdx]) ")
        if (Savings[MaxSvIdx] < 0) || (sum(AvgInvCostList2) - InitTotalInvCost > FC)
            ToBeImprove[MaxSvIdx] = false
        end
    end
    return ToBeImprove, AvgInvCostList1, AvgBkCostList1, AvgInvCostList2, AvgBkCostList2, Savings, BkFut
end

# Define the function 
function FindProdQtyC4(Data::DefMDPData, InitInvList::Vector{Int64}, prd::Int64)

    MaxTotalSav = -Inf
    OptSol = zeros(Int, Data.Nᵢ)
    OptComparison  = false
    # Calculate the expected future demand per period for each item
    ExpFutDemand = zeros(Float64, Data.Nᵢ)
    for j in 1:length(Data.D)
        ExpFutDemand .+= Data.D[j] .* Data.ProbD[j]
    end

    #for _ in 1:20
        # If there is no period to go, no production is needed
        if prd <= 1
            return zeros(Int64, Data.Nᵢ)
        end

        # Preallocations
        CurrSol      = zeros(Int, Data.Nᵢ)
        CurrInvList  = Vector{Float64}(undef, Data.Nᵢ)
        InitBk   = Vector{Float64}(undef, Data.Nᵢ)

        # Get the current inventory levels and initial backorder levels for all items
        CurrInvList = max.(InitInvList .- ExpFutDemand, Data.MinI)
        InitBk = (abs.(min.(CurrInvList, 0)))
        #println("Initial Inventory Level : $(CurrInvList)")   
        # The lost sales cost is assumed to be very high, production when backorder occurs is necessary
        # Start by fulfilling the backorder quantities first
        while true
            r = rand()
            MaxBk = 0.0
            MaxBkIdx = 0
            Bk = 0.0
            α = 0.2
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
        AvgInvCostList1  = zeros(Float64, Data.Nᵢ)
        AvgBkCostList1   = zeros(Float64, Data.Nᵢ)
        AvgInvCostList2 = zeros(Float64, Data.Nᵢ)
        AvgBkCostList2 = zeros(Float64, Data.Nᵢ)
        Savings        = zeros(Float64, Data.Nᵢ)
        BkFut        = zeros(Float64, Data.Nᵢ)
        InitSol = CurrSol
        InitCurrInvList = CurrInvList

        #println("Initial solution : $(CurrSol)")
        # Calculate the initial average inventory and backorder costs for all items
        for i in 1:Data.Nᵢ
            BkFut[i] = abs(CurrInvList[i] - (ExpFutDemand[i] * (prd- 2)))
                
            if BkFut[i] <= 0.0
                ToBeImprove[i] = false
            end

            EndInv, EndBk, AvgInvCost, AvgBkCost = ProjInvBkCost(Data.h[i], Data.b[i], Data.ep[i], CurrInvList[i], prd, ExpFutDemand[i])
            AvgInvCostList1[i] = AvgInvCost
            AvgBkCostList1[i] = AvgBkCost

            # Calculate the savings
            PerspInv = CurrInvList[i] + 1.0

            EndInv, EndBk, AvgInvCost, AvgBkCost = ProjInvBkCost(Data.h[i], Data.b[i], Data.ep[i], PerspInv, prd, ExpFutDemand[i])
            AvgInvCostList2[i] = AvgInvCost
            AvgBkCostList2[i] = AvgBkCost

            Savings[i] = abs(AvgBkCostList1[i] - AvgBkCostList2[i]) - abs(AvgInvCostList2[i] - AvgInvCostList1[i])
            #println("Savings: $Savings, Bk1: $(AvgBkCostList1[i]), Bk2: $(AvgBkCostList2[i]), Inv1: $(AvgInvCostList1[i]), Inv2: $(AvgInvCostList2[i]) ")
            if (Savings[i] < 0)
                ToBeImprove[i] = false
            end
        end
        InitAvgInvCostList1 = AvgInvCostList1
        InitAvgBkCostList1 = AvgBkCostList1
        InitAvgInvCostList2 = AvgInvCostList2
        InitAvgBkCostList2 = AvgInvCostList2
        AvgInvCostInit = sum(AvgInvCostList1)
        AvgBkCostInit = sum(AvgBkCostList1)
        InitToBeImprove = ToBeImprove

        if any(CurrSol .> 0)
            BuildH = maximum((CurrSol .> 0) .* Data.BH)
            if BuildH == 2

                IdxList = [1:Data.Nᵢ;]

                ToBeImprove, AvgInvCostList1, AvgBkCostList1, AvgInvCostList2, AvgBkCostList2, Savings, BkFut = 
                MainLoop(IdxList, CurrSol, CurrInvList, Data, ExpFutDemand, ToBeImprove, AvgInvCostList1, AvgBkCostList1, AvgInvCostList2, AvgBkCostList2, Savings, BkFut, prd)
                
                AvgInvCostAft = sum(AvgInvCostList1)     
                AvgBkCostAft = sum(AvgBkCostList1)
                TotalSav = (AvgBkCostInit - AvgBkCostAft) - (AvgInvCostAft - AvgInvCostInit)            # Calculate the total savings: total reduction in backorder cost - total increase in inventory cost
                if TotalSav > MaxTotalSav
                    MaxTotalSav = TotalSav
                    OptSol = CurrSol
                end

            elseif BuildH == 1
            
                IdxList = Int64[]
                for i in 1:Data.Nᵢ
                    if Data.BH[i] == 2
                        push!(IdxList, i)
                    end
                end
                
                PowderCost = 2 * Data.pd
                PowderCost2 = BuildH*Data.pd
                FixedCost1 = Data.c + PowderCost 
                FixedCost2 = Data.c + PowderCost2
                AddFixedCost = FixedCost1 - FixedCost2

                ToBeImprove, AvgInvCostList1, AvgBkCostList1, AvgInvCostList2, AvgBkCostList2, Savings, BkFut = 
                MainLoop2(IdxList, CurrSol, CurrInvList, Data, ExpFutDemand, ToBeImprove, AvgInvCostList1, AvgBkCostList1, AvgInvCostList2, AvgBkCostList2, Savings, BkFut, prd, AddFixedCost)

                AvgInvCostAft = sum(AvgInvCostList1[IdxList])     
                AvgBkCostAft = sum(AvgBkCostList1[IdxList])
                TotalSav = (AvgBkCostInit - AvgBkCostAft) - (AvgInvCostAft - AvgInvCostInit)  

                if any(CurrSol[IdxList] .> 0) && (TotalSav > AddFixedCost)

                    IdxList = [1:Data.Nᵢ;]
                    ToBeImprove, AvgInvCostList1, AvgBkCostList1, AvgInvCostList2, AvgBkCostList2, Savings, BkFut = 
                    MainLoop(IdxList, CurrSol, CurrInvList, Data, ExpFutDemand, ToBeImprove, AvgInvCostList1, AvgBkCostList1, AvgInvCostList2, AvgBkCostList2, Savings, BkFut, prd)

                    AvgInvCostAft = sum(AvgInvCostList1)     
                    AvgBkCostAft = sum(AvgBkCostList1)
                    TotalSav = (AvgBkCostInit - AvgBkCostAft) - (AvgInvCostAft - AvgInvCostInit)            # Calculate the total savings: total reduction in backorder cost - total increase in inventory cost
                                                                         
                    if TotalSav > MaxTotalSav
                        MaxTotalSav = TotalSav
                        OptSol = CurrSol
                    end
                else
                    IdxList = Int64[]
                    for i in 1:Data.Nᵢ
                        if Data.BH[i] == 1
                            push!(IdxList, i)
                        end
                    end
                    CurrSol = InitSol
                    CurrInvList = InitCurrInvList
                    AvgInvCostList1 = InitAvgInvCostList1
                    AvgBkCostList1 = InitAvgBkCostList1
                    AvgInvCostList2 = InitAvgInvCostList2
                    AvgBkCostList2 = InitAvgBkCostList2
                    ToBeImprove = InitToBeImprove

                    ToBeImprove, AvgInvCostList1, AvgBkCostList1, AvgInvCostList2, AvgBkCostList2, Savings, BkFut = 
                    MainLoop(IdxList, CurrSol, CurrInvList, Data, ExpFutDemand, ToBeImprove, AvgInvCostList1, AvgBkCostList1, AvgInvCostList2, AvgBkCostList2, Savings, BkFut, prd)
                    
                    AvgInvCostAft = sum(AvgInvCostList1[IdxList])     
                    AvgBkCostAft = sum(AvgBkCostList1[IdxList])
                    TotalSav = (AvgBkCostInit - AvgBkCostAft) - (AvgInvCostAft - AvgInvCostInit)            # Calculate the total savings: total reduction in backorder cost - total increase in inventory cost
                    if TotalSav > MaxTotalSav
                        MaxTotalSav = TotalSav
                        OptSol = CurrSol
                    else
                        OptSol = zeros(Int64, Data.Nᵢ)
                    end
                end
            end
        else

            if all(CurrInvList .> 0)
                return zeros(Int64, Data.Nᵢ)
            else
                IdxList = Int64[]
                for i in 1:Data.Nᵢ
                    if Data.BH[i] == 2
                        push!(IdxList, i)
                    end
                end

                PowderCost = 2 * Data.pd
                PowderCost2 = 1*Data.pd
                FixedCost1 = Data.c + PowderCost 
                FixedCost2 = Data.c + PowderCost2
                AddFixedCost = FixedCost1 - FixedCost2

                ToBeImprove, AvgInvCostList1, AvgBkCostList1, AvgInvCostList2, AvgBkCostList2, Savings, BkFut = 
                MainLoop2(IdxList, CurrSol, CurrInvList, Data, ExpFutDemand, ToBeImprove, AvgInvCostList1, AvgBkCostList1, AvgInvCostList2, AvgBkCostList2, Savings, BkFut, prd, FixedCost1)

                AvgInvCostAft = sum(AvgInvCostList1[IdxList])     
                AvgBkCostAft = sum(AvgBkCostList1[IdxList])
                TotalSav = (AvgBkCostInit - AvgBkCostAft) - (AvgInvCostAft - AvgInvCostInit)        
                
                if any(CurrSol[IdxList] .> 0) && (TotalSav > FixedCost1)

                    IdxList = Int64[]
                    for i in 1:Data.Nᵢ
                        if Data.BH[i] == 1
                            push!(IdxList, i)
                        end
                    end
                    ToBeImprove, AvgInvCostList1, AvgBkCostList1, AvgInvCostList2, AvgBkCostList2, Savings, BkFut = 
                    MainLoop(IdxList, CurrSol,CurrInvList, Data, ExpFutDemand, ToBeImprove, AvgInvCostList1, AvgBkCostList1, AvgInvCostList2, AvgBkCostList2, Savings, BkFut, prd)

                    AvgInvCostAft = sum(AvgInvCostList1)     
                    AvgBkCostAft = sum(AvgBkCostList1)
                    TotalSav = (AvgBkCostInit - AvgBkCostAft) - (AvgInvCostAft - AvgInvCostInit)            # Calculate the total savings: total reduction in backorder cost - total increase in inventory cost
                                                                            
                    if TotalSav > MaxTotalSav
                        MaxTotalSav = TotalSav
                        OptSol = CurrSol
                    end

                else
                    IdxList = Int64[]
                    for i in 1:Data.Nᵢ
                        if Data.BH[i] == 1
                            push!(IdxList, i)
                        end
                    end
                    CurrSol = InitSol
                    CurrInvList = InitCurrInvList
                    AvgInvCostList1 = InitAvgInvCostList1
                    AvgBkCostList1 = InitAvgBkCostList1
                    AvgInvCostList2 = InitAvgInvCostList2
                    AvgBkCostList2 = InitAvgBkCostList2
                    ToBeImprove = InitToBeImprove

                    ToBeImprove, AvgInvCostList1, AvgBkCostList1, AvgInvCostList2, AvgBkCostList2, Savings, BkFut = 
                    MainLoop2(IdxList, CurrSol, CurrInvList, Data, ExpFutDemand, ToBeImprove, AvgInvCostList1, AvgBkCostList1, AvgInvCostList2, AvgBkCostList2, Savings, BkFut, prd, FixedCost2)
                        
                    AvgInvCostAft = sum(AvgInvCostList1[IdxList])     
                    AvgBkCostAft = sum(AvgBkCostList1[IdxList])
                    TotalSav = (AvgBkCostInit - AvgBkCostAft) - (AvgInvCostAft - AvgInvCostInit)            # Calculate the total savings: total reduction in backorder cost - total increase in inventory cost 
                    
                    if TotalSav > MaxTotalSav
                        MaxTotalSav = TotalSav
                        OptSol = CurrSol
                    else
                        OptSol = zeros(Int64, Data.Nᵢ)
                    end
                end
            end
        end
    #end
    return OptSol
end

# Test

#init_inv = [2, 2, 2, 2]
#prd = 5
#sol = FindProdQtyC4(Data, init_inv, prd)
