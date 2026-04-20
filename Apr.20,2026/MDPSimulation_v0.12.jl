# This file is to define a function that simulate the MDP model for JRP AM problem using the policy 
#obtained from DP or heuristic methods

# Import packages
using Random, Distributions, Combinatorics, DSP
#include("HeuristicC1_v0.12.1.jl")
include("HeuristicC2.5_v0.12.1.jl")
include("HeuristicC3_v0.12.1.jl")


# Define the mechanism for replenshiment of TM
function TMRepl(InvLvl::Vector{Int64}, ReplReq:: Vector{Int64}, BS::Vector{Int64}, Data::DefMDPData)
    
    # Update the replenishment request based on the current inventory level base stock policy
    for i in 1:Data.Nᵢ
        if InvLvl[i] < BS[i]
            ReplReq[i] = BS[i] - InvLvl[i]
        else
            ReplReq[i] = 0
        end
    end
    return InvLvl, ReplReq
end

# Define a function to calculate the base stock level for each item (based on current demand pattern)
function BSCal(Data::DefMDPData, BSLvl::Float64, LT::Int)
    BS = zeros(Int, Data.Nᵢ)

    for i in 1:Data.Nᵢ
        Pattern = Data.DPattern[i]      # e.g. [0,1,2]
        Prob    = Data.ProbDPattern[i]  # e.g. [p0,p1,p2], sum == 1

        # Single-day demand PMF as dense array over 0:MaxD1
        maxd1 = maximum(Pattern)
        pmf = zeros(Float64, maxd1 + 1)
        for (d, p) in zip(Pattern, Prob)
            pmf[d + 1] += p
        end

        # Convolve PMF with itself LT-1 times
        pmf_LT = pmf
        for _ in 2:LT
            pmf_LT = conv(pmf_LT, pmf)  # Base.conv on vectors
        end

        # pmf_LT[k+1] = P(S = k), k = 0:LT*maxd1
        cdf = cumsum(pmf_LT)

        # Smallest k with CDF >= BSLvl
        idx = findfirst(x -> x >= BSLvl, cdf)
        BS[i] = idx === nothing ? length(cdf) - 1 : (idx - 1)
    end

    return BS
end

# Define the simulation function for pure base stock policy (No AM)
function MDPSim(Data::DefMDPData, Info::DefMDPInfo, SimPeriod::Int64, BS::Vector{Int64}, SLT::Int64)

    seed = [1233, 8907, 234359, 9790223]     # Seeds for random number generators for the demand of each item
    DGen = []
    for i in 1:Data.Nᵢ                       # Create a random number generator for each item
        push!(DGen, Xoshiro(seed[i]))
    end

    TotalCost = 0.0
    TotalInv = 0
    TotalDemand = 0
    TotalStockout = 0     
    count = 0    
    ReplReq = zeros(Int64, Data.Nᵢ) 
    InvLvl = BS                            # Initial inventory level set to be the base stock level
    ReplPeriod = 0

    # Simulation starts
    for n in 1:SimPeriod

        # Determine the current period in the replenishment cycle
        CyclePeriod = mod(n, Data.Period)
        #println("Period: $CyclePeriod")
        #println("Initial Inventory Level: $InvLvl")

        if ReplPeriod == 0
            InvLvl .+= ReplReq   # Given the current inventory level and restocking requested last time, calculate the new inventory level
        end

        # If the current period is 1 (The start of a new restocking cycle), Send out the restocking request
        # Also, the replenishment for TM arrives.
        if (CyclePeriod == 1) && (n!==1)
            InvLvl, ReplReq = TMRepl(InvLvl, ReplReq, BS, Data)
            ReplPeriod = SLT
            #InvLvl .+= ReplReq   # Given the current inventory level and restocking requested last time, calculate the new inventory level (only happen when the replenishment arrives immediately)
            #println("Inventory Level after TM Replenishment: $InvLvl, send out request: $ReplReq")
        end

        # Get the action from the Optimal policy
        #a = Info.Decision[Info.StSp[Tuple(InvLvl)], Data.Period - CyclePeriod + 1]

        # Generate demand based on the probability Distribution
        demand = zeros(Int64, Data.Nᵢ)
        for i in 1:Data.Nᵢ
            Rdm = rand(DGen[i])
            ProbCum = cumsum(Data.ProbDPattern[i])
            for j in 1:length(ProbCum)
                if Rdm <= ProbCum[j]
                    demand[i] = Data.DPattern[i][j]
                    break
                end
            end
        end
        #println("Demand: $demand")
        #println("Production quantity: $(Info.Alt[a])")

        # Calculate inventory, backorder, lost sales, production, and powder levels
        Inv = max.(InvLvl, 0)
        Backorder = abs.(min.(InvLvl, 0))
        Stockout = demand .- max.(min.(demand, InvLvl), 0)
        LostSales = max.(abs.(min.(InvLvl .- demand, 0)) .- abs.(Data.MinI), 0)
        #Prod = Info.Alt[a]
        #Production = (any(Prod .> 0) ? 1 : 0)
        #Powder = maximum((Prod .> 0) .* Data.BH)

        # Calculate the cost for each component (quantity * cost/unit)
        InvCost = sum(Inv .* Data.h)
        BackorderCost = sum(Backorder .* Data.b)
        LostSalesCost = sum(LostSales .* Data.ls)
        #ProductionCost = Production * Data.c
        #PowderCost = Powder * Data.pd

        # Update total cost
        TotalCost += (InvCost + BackorderCost + LostSalesCost)
        TotalInv += sum(Inv)
        TotalDemand += sum(demand)
        TotalStockout += sum(Stockout)

        # Update inventory level for the next period
        InvLvl = max.(InvLvl .- demand, Data.MinI)
        ReplPeriod -= 1
        
        if any((InvLvl .- BS) .> 0)
            #println("Exceeding base stock level ($BS)!")
            count += 1
        end
    end

    return TotalCost, TotalInv, TotalDemand, TotalStockout, count
end

# Define the simulation function for pure base stock policy
function MDPSimAMM(Data::DefMDPData, Info::DefMDPInfo, SimPeriod::Int64, BS::Vector{Int64}, InitBS::Vector{Int64}, SLT::Int64)

    seed = [1233, 8907, 234359, 9790223]     # Seeds for random number generators for the demand of each item
    DGen = []
    for i in 1:Data.Nᵢ                       # Create a random number generator for each item
        push!(DGen, Xoshiro(seed[i]))
    end
    
    InvCostList = zeros(Float64, Data.Nᵢ)
    BackorderCostList  = zeros(Float64, Data.Nᵢ)
    LostSalesCostList = zeros(Float64, Data.Nᵢ)
    InvList = zeros(Int64, Data.Nᵢ)
    BackorderList = zeros(Int64, Data.Nᵢ)
    LostSalesList = zeros(Int64, Data.Nᵢ)
    TotalCost = 0.0
    TotalInv = 0
    TotalDemand = 0
    TotalStockout = 0    
    TotalProductionCost = 0.0
    TotalPowderCost = 0.0
    count = 0    
    ReplReq = zeros(Int64, Data.Nᵢ) 
    InvLvl = BS                            # Initial inventory level set to be the base stock level
    ReplPeriod = 0

    # Simulation starts
    for n in 1:SimPeriod

        # Determine the current period in the replenishment cycle
        CyclePeriod = mod(n, Data.Period)
        #println("Period: $CyclePeriod")
        #println("Initial Inventory Level: $InvLvl")

        if ReplPeriod == 0
            InvLvl .+= ReplReq   # Given the current inventory level and restocking requested last time, calculate the new inventory level
        end

        # If the current period is 1 (The start of a new restocking cycle), Send out the restocking request
        # Also, the replenishment for TM arrives.
        if (CyclePeriod == 1) && (n!==1)
            InvLvl, ReplReq = TMRepl(InvLvl, ReplReq, BS, Data)
            ReplPeriod = SLT
            # InvLvl .+= ReplReq   # Given the current inventory level and restocking requested last time, calculate the new inventory level (only happen when the replenishment arrives immediately)
            #println("Inventory Level after TM Replenishment: $InvLvl, send out request: $ReplReq")
        end

        # Avoid the inventory level go over the maximum values
        InvLvlA = min.(InvLvl, InitBS)

        # Get the action from the Optimal policy
        #println("Period: $CyclePeriod")
        if CyclePeriod == 0
            a = Info.Decision[Info.StSp[Tuple(InvLvlA)], CyclePeriod + 2]
            #println("Period1: ", CyclePeriod + 2)
        else
            a = Info.Decision[Info.StSp[Tuple(InvLvlA)], Data.Period - CyclePeriod + 2]
            #println("Period1: ", (Data.Period) - CyclePeriod + 2)
        end

        # Generate demand based on the probability Distribution
        demand = zeros(Int64, Data.Nᵢ)
        for i in 1:Data.Nᵢ
            Rdm = rand(DGen[i])
            ProbCum = cumsum(Data.ProbDPattern[i])
            for j in 1:length(ProbCum)
                if Rdm <= ProbCum[j]
                    demand[i] = Data.DPattern[i][j]
                    break
                end
            end
        end
        #println("Demand: $demand")
        #println("Production quantity: $(Info.Alt[a])")

        # Calculate inventory, backorder, lost sales, production, and powder levels
        Inv = max.(InvLvl, 0)
        Backorder = abs.(min.(InvLvl, 0))
        Stockout = demand .- max.(min.(demand, InvLvl), 0)
        LostSales = max.(abs.(min.(InvLvl .- demand, 0)) .- abs.(Data.MinI), 0)
        Prod = Info.Alt[a]
        Production = (any(Prod .> 0) ? 1 : 0)
        Powder = maximum((Prod .> 0) .* Data.BH)

        # Calculate the cost for each component (quantity * cost/unit)
        InvCost = Inv .* Data.h
        BackorderCost = Backorder .* Data.b
        LostSalesCost = LostSales .* Data.ls
        ProductionCost = Production * Data.c
        PowderCost = Powder * Data.pd

        # Update the cost, ivnentory, backorder, lostsales lists
        InvCostList .+= InvCost 
        BackorderCostList .+= BackorderCost 
        LostSalesCostList .+= LostSalesCost
        InvList .+= Inv
        BackorderList .+= Backorder
        LostSalesList .+= LostSales

        # Update total cost
        TotalCost += sum(InvCost .+ BackorderCost .+ LostSalesCost) + ProductionCost + PowderCost
        TotalInv += sum(Inv)
        TotalDemand += sum(demand)
        TotalStockout += sum(Stockout)
        TotalProductionCost += ProductionCost
        TotalPowderCost += PowderCost

        # Update inventory level for the next period
        InvLvl = max.(InvLvl .- demand .+ Prod, Data.MinI)
        ReplPeriod -= 1
        
        if any((InvLvl .- BS) .> 0)
            #println("Exceeding base stock level ($BS)!")
            count += 1
        end
    end

    return TotalCost, InvCostList, BackorderCostList, LostSalesCostList, TotalProductionCost, TotalPowderCost, TotalInv, TotalDemand, TotalStockout, InvList, BackorderList, LostSalesList, count

end

# Define the simulation function for pure base stock policy
function MDPSimAMS(Data::DefMDPData, Info::DefMDPInfo, SimPeriod::Int64, BS::Vector{Int64}, InitBS::Vector{Int64}, SLT::Int64)

    seed = [1233, 8907, 234359, 9790223]     # Seeds for random number generators for the demand of each item
    DGen = []
    for i in 1:Data.Nᵢ                       # Create a random number generator for each item
        push!(DGen, Xoshiro(seed[i]))
    end
    
    InvCostList = zeros(Float64, Data.Nᵢ)
    BackorderCostList  = zeros(Float64, Data.Nᵢ)
    LostSalesCostList = zeros(Float64, Data.Nᵢ)
    InvList = zeros(Int64, Data.Nᵢ)
    BackorderList = zeros(Int64, Data.Nᵢ)
    LostSalesList = zeros(Int64, Data.Nᵢ)
    TotalCost = 0.0
    TotalInv = 0
    TotalDemand = 0
    TotalStockout = 0    
    TotalProductionCost = 0.0
    TotalPowderCost = 0.0
    count = 0    
    ReplReq = zeros(Int64, Data.Nᵢ) 
    InvLvl = BS                            # Initial inventory level set to be the base stock level
    ReplPeriod = 0

    # Simulation starts
    for n in 1:SimPeriod

        # Determine the current period in the replenishment cycle
        CyclePeriod = mod(n, Data.Period)
        #println("Period: $CyclePeriod")
        #println("Initial Inventory Level: $InvLvl")

        if ReplPeriod == 0
            InvLvl .+= ReplReq   # Given the current inventory level and restocking requested last time, calculate the new inventory level
        end

        # If the current period is 1 (The start of a new restocking cycle), Send out the restocking request
        # Also, the replenishment for TM arrives.
        if (CyclePeriod == 1) && (n!==1)
            InvLvl, ReplReq = TMRepl(InvLvl, ReplReq, BS, Data)
            ReplPeriod = SLT
            # InvLvl .+= ReplReq   # Given the current inventory level and restocking requested last time, calculate the new inventory level (only happen when the replenishment arrives immediately)
            #println("Inventory Level after TM Replenishment: $InvLvl, send out request: $ReplReq")
        end

        # Avoid the inventory level go over the maximum values
        InvLvlA = min.(InvLvl, InitBS)

        # Get the action from the Optimal policy
        #println("Period: $CyclePeriod")
        if CyclePeriod == 0
            a = Info.Decision[Info.StSp[Tuple(InvLvlA)], CyclePeriod + 2]
            #println("Period1: ", CyclePeriod + 2)
        else
            a = Info.Decision[Info.StSp[Tuple(InvLvlA)], Data.Period - CyclePeriod + 2]
            #println("Period1: ", (Data.Period) - CyclePeriod + 2)
        end

        # Generate demand based on the probability Distribution
        demand = zeros(Int64, Data.Nᵢ)
        for i in 1:Data.Nᵢ
            Rdm = rand(DGen[i])
            ProbCum = cumsum(Data.ProbDPattern[i])
            for j in 1:length(ProbCum)
                if Rdm <= ProbCum[j]
                    demand[i] = Data.DPattern[i][j]
                    break
                end
            end
        end
        #println("Demand: $demand")
        #println("Production quantity: $(Info.Alt[a])")

        # Calculate inventory, backorder, lost sales, production, and powder levels
        Inv = max.(InvLvl, 0)
        Backorder = abs.(min.(InvLvl, 0))
        Stockout = demand .- max.(min.(demand, InvLvl), 0)
        LostSales = max.(abs.(min.(InvLvl .- demand, 0)) .- abs.(Data.MinI), 0)
        Prod = Info.Alt[a]
        Production = (any(Prod .> 0) ? 1 : 0)
        Powder = maximum((Prod .> 0) .* Data.BH)

        # Calculate the cost for each component (quantity * cost/unit)
        InvCost = Inv .* Data.h
        BackorderCost = Backorder .* Data.b
        LostSalesCost = LostSales .* Data.ls
        ProductionCost = Production * Data.c
        PowderCost = Powder * Data.pd

        # Update the cost, ivnentory, backorder, lostsales lists
        InvCostList .+= InvCost 
        BackorderCostList .+= BackorderCost 
        LostSalesCostList .+= LostSalesCost
        InvList .+= Inv
        BackorderList .+= Backorder
        LostSalesList .+= LostSales

        # Update total cost
        TotalCost += sum(InvCost .+ BackorderCost .+ LostSalesCost) + ProductionCost + PowderCost
        TotalInv += sum(Inv)
        TotalDemand += sum(demand)
        TotalStockout += sum(Stockout)
        TotalProductionCost += ProductionCost
        TotalPowderCost += PowderCost

        # Update inventory level for the next period
        InvLvl = max.(InvLvl .- demand .+ Prod, Data.MinI)
        ReplPeriod -= 1
        
        if any((InvLvl .- BS) .> 0)
            #println("Exceeding base stock level ($BS)!")
            count += 1
        end
    end

    return TotalCost, InvCostList, BackorderCostList, LostSalesCostList, TotalProductionCost, TotalPowderCost, TotalInv, TotalDemand, TotalStockout, InvList, BackorderList, LostSalesList, count

end

# Define the simulation function for pure base stock policy
function MDPSimE(Data::DefMDPData, Info::DefMDPInfo, SimPeriod::Int64, BS::Vector{Int64}, InitBS::Vector{Int64}, SLT::Int64)

    seed = [1233, 8907, 234359, 9790223]     # Seeds for random number generators for the demand of each item
    DGen = []
    for i in 1:Data.Nᵢ                       # Create a random number generator for each item
        push!(DGen, Xoshiro(seed[i]))
    end
    
    InvCostList = zeros(Float64, Data.Nᵢ)
    BackorderCostList  = zeros(Float64, Data.Nᵢ)
    LostSalesCostList = zeros(Float64, Data.Nᵢ)
    InvList = zeros(Int64, Data.Nᵢ)
    BackorderList = zeros(Int64, Data.Nᵢ)
    LostSalesList = zeros(Int64, Data.Nᵢ)
    TotalCost = 0.0
    TotalInv = 0
    TotalDemand = 0
    TotalStockout = 0    
    TotalProductionCost = 0.0
    TotalPowderCost = 0.0
    count = 0    
    ReplReq = zeros(Int64, Data.Nᵢ) 
    InvLvl = BS                            # Initial inventory level set to be the base stock level
    ReplPeriod = 0
    InTransit = zeros(Int64, Data.Nᵢ)

    # Simulation starts
    for n in 1:SimPeriod

        # Determine the current period in the replenishment cycle
        CyclePeriod = mod(n, Data.Period)
        #println("Period: $CyclePeriod")
        #println("Initial Inventory Level: $InvLvl")

        if ReplPeriod == 0
            InvLvl .+= ReplReq   # Given the current inventory level and restocking requested last time, calculate the new inventory level
        end

        # If the current period is 1 (The start of a new restocking cycle), Send out the restocking request
        # Also, the replenishment for TM arrives.
        if (CyclePeriod == 1) && (n!==1)
            InvLvl, ReplReq = TMRepl(InvLvl, ReplReq, BS, Data)
            ReplPeriod = SLT
            # InvLvl .+= ReplReq   # Given the current inventory level and restocking requested last time, calculate the new inventory level (only happen when the replenishment arrives immediately)
            #println("Inventory Level after TM Replenishment: $InvLvl, send out request: $ReplReq")
        end

        # Avoid the inventory level go over the maximum values
        InvLvlA = min.(InvLvl, InitBS)

        # Get the action from the Optimal policy
        state = (InvLvlA..., InTransit...)
        #println("Period: $CyclePeriod")
        if CyclePeriod == 0
            a = Info.Decision[Info.StSp[state], CyclePeriod + 2]
            #println("Period1: ", CyclePeriod + 2)
        else
            a = Info.Decision[Info.StSp[state], Data.Period - CyclePeriod + 2]
            #println("Period1: ", (Data.Period) - CyclePeriod + 2)
        end

        # Generate demand based on the probability Distribution
        demand = zeros(Int64, Data.Nᵢ)
        for i in 1:Data.Nᵢ
            Rdm = rand(DGen[i])
            ProbCum = cumsum(Data.ProbDPattern[i])
            for j in 1:length(ProbCum)
                if Rdm <= ProbCum[j]
                    demand[i] = Data.DPattern[i][j]
                    break
                end
            end
        end
        #println("Demand: $demand")
        #println("Production quantity: $(Info.Alt[a])")

        # Calculate inventory, backorder, lost sales, production, and powder levels
        Inv = max.(InvLvl, 0)
        Backorder = abs.(min.(InvLvl, 0))
        Stockout = demand .- max.(min.(demand, InvLvl), 0)
        LostSales = max.(abs.(min.(InvLvl .- demand, 0)) .- abs.(Data.MinI), 0)
        Prod = Info.Alt[a]
        Production = (any(Prod .> 0) ? 1 : 0)
        Powder = maximum((Prod .> 0) .* Data.BH)

        # Calculate the cost for each component (quantity * cost/unit)
        InvCost = Inv .* Data.h
        BackorderCost = Backorder .* Data.b
        LostSalesCost = LostSales .* Data.ls
        ProductionCost = Production * Data.c
        PowderCost = Powder * Data.pd

        # Update the cost, ivnentory, backorder, lostsales lists
        InvCostList .+= InvCost 
        BackorderCostList .+= BackorderCost 
        LostSalesCostList .+= LostSalesCost
        InvList .+= Inv
        BackorderList .+= Backorder
        LostSalesList .+= LostSales

        # Update total cost
        TotalCost += sum(InvCost .+ BackorderCost .+ LostSalesCost) + ProductionCost + PowderCost
        TotalInv += sum(Inv)
        TotalDemand += sum(demand)
        TotalStockout += sum(Stockout)
        TotalProductionCost += ProductionCost
        TotalPowderCost += PowderCost

        # Update inventory level for the next period
        InvLvl = max.(InvLvl .- demand .+ InTransit, Data.MinI)
        ReplPeriod -= 1
        InTransit = a
        
        if any((InvLvl .- BS) .> 0)
            #println("Exceeding base stock level ($BS)!")
            count += 1
        end
    end

    return TotalCost, InvCostList, BackorderCostList, LostSalesCostList, TotalProductionCost, TotalPowderCost, TotalInv, TotalDemand, TotalStockout, InvList, BackorderList, LostSalesList, count

end


# Define the simulation function for pure base stock policy
function MDPSimAMHu(Data::DefMDPData, SimPeriod::Int64, BS::Vector{Int64}, SLT::Int64)

    seed = [1233, 8907, 234359, 9790223]     # Seeds for random number generators for the demand of each item
    DGen = []
    for i in 1:Data.Nᵢ                       # Create a random number generator for each item
        push!(DGen, Xoshiro(seed[i]))
    end
    
    InvCostList = zeros(Float64, Data.Nᵢ)
    BackorderCostList  = zeros(Float64, Data.Nᵢ)
    LostSalesCostList = zeros(Float64, Data.Nᵢ)
    InvList = zeros(Int64, Data.Nᵢ)
    BackorderList = zeros(Int64, Data.Nᵢ)
    LostSalesList = zeros(Int64, Data.Nᵢ)
    TotalCost = 0.0
    TotalInv = 0
    TotalDemand = 0
    TotalStockout = 0    
    TotalProductionCost = 0.0
    TotalPowderCost = 0.0
    count = 0    
    ReplReq = zeros(Int64, Data.Nᵢ) 
    InvLvl = BS                            # Initial inventory level set to be the base stock level
    ReplPeriod = 0
    # Simulation starts
    for n in 1:SimPeriod

        # Determine the current period in the replenishment cycle
        CyclePeriod = mod(n, Data.Period)
        #println("Period: $CyclePeriod")
        #println("Initial Inventory Level: $InvLvl")

        if ReplPeriod == 0
            InvLvl .+= ReplReq   # Given the current inventory level and restocking requested last time, calculate the new inventory level
        end

        # If the current period is 1 (The start of a new restocking cycle), Send out the restocking request
        # Also, the replenishment for TM arrives.
        if (CyclePeriod == 1) && (n!==1)
            InvLvl, ReplReq = TMRepl(InvLvl, ReplReq, BS, Data)
            ReplPeriod = SLT
            # InvLvl .+= ReplReq   # Given the current inventory level and restocking requested last time, calculate the new inventory level (only happen when the replenishment arrives immediately)
            #println("Inventory Level after TM Replenishment: $InvLvl, send out request: $ReplReq")
        end

        # Get the action from the Optimal policy
        Prod = zeros(Int64, Data.Nᵢ)
        #println("Period: $CyclePeriod")
        if CyclePeriod == 0
            Prod = FindProdQtyC2(Data, InvLvl, CyclePeriod + 2)
            #println("Period1: ", CyclePeriod + 2)
        else
            Prod = FindProdQtyC2(Data, InvLvl, Data.Period - CyclePeriod + 2)
            #println("Period1: ", (Data.Period) - CyclePeriod + 2)
        end

        # Generate demand based on the probability Distribution
        demand = zeros(Int64, Data.Nᵢ)
        for i in 1:Data.Nᵢ
            Rdm = rand(DGen[i])
            ProbCum = cumsum(Data.ProbDPattern[i])
            for j in 1:length(ProbCum)
                if Rdm <= ProbCum[j]
                    demand[i] = Data.DPattern[i][j]
                    break
                end
            end
        end
        #println("Demand: $demand")
        #println("Production quantity: $(Info.Alt[a])")

        # Calculate inventory, backorder, lost sales, production, and powder levels
        Inv = max.(InvLvl, 0)
        Backorder = abs.(min.(InvLvl, 0))
        Stockout = demand .- max.(min.(demand, InvLvl), 0)
        LostSales = max.(abs.(min.(InvLvl .- demand, 0)) .- abs.(Data.MinI), 0)
        Production = (any(Prod .> 0) ? 1 : 0)
        Powder = maximum((Prod .> 0) .* Data.BH)

        # Calculate the cost for each component (quantity * cost/unit)
        InvCost = Inv .* Data.h
        BackorderCost = Backorder .* Data.b
        LostSalesCost = LostSales .* Data.ls
        ProductionCost = Production * Data.c
        PowderCost = Powder * Data.pd

        # Update the cost, ivnentory, backorder, lostsales lists
        InvCostList .+= InvCost 
        BackorderCostList .+= BackorderCost 
        LostSalesCostList .+= LostSalesCost
        InvList .+= Inv
        BackorderList .+= Backorder
        LostSalesList .+= LostSales

        # Update total cost
        TotalCost += sum(InvCost .+ BackorderCost .+ LostSalesCost) + ProductionCost + PowderCost
        TotalInv += sum(Inv)
        TotalDemand += sum(demand)
        TotalStockout += sum(Stockout)
        TotalProductionCost += ProductionCost
        TotalPowderCost += PowderCost

        # Update inventory level for the next period
        InvLvl = max.(InvLvl .- demand .+ Prod, Data.MinI)
        ReplPeriod -= 1
        
        if any((InvLvl .- BS) .> 0)
            #println("Exceeding base stock level ($BS)!")
            count += 1
        end
    end

    return TotalCost, InvCostList, BackorderCostList, LostSalesCostList, TotalProductionCost, TotalPowderCost, TotalInv, TotalDemand, TotalStockout, InvList, BackorderList, LostSalesList, count

end

