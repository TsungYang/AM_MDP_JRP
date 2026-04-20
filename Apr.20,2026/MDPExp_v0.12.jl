# This file is to run an experiment to the inventory level of the recurrent model

# Import packages
using CSV, DataFrames

# Import customized function
include("MDP_JRP_AM_M_v0.12.jl")
include("MDP_JRP_AM_S_v0.12.jl")
include("MDPSimulation_v0.12.jl")
include("MDP_JRP_AM_v0.12E.jl")

# Define a function to run the experiment
function MDPExp()

    # Export the results to a CSV file
    ResultsDf = DataFrame("α" => Float64[], 
                           "BaseStock" => Tuple{Int64, Int64, Int64, Int64}[], 
                           "AvgTotalCost" => Float64[], 
                           "AvgInvLvl" => Float64[],
                           "AvgStockout" => Float64[],
                           "AvgDemand" => Float64[],
                           "β" => Float64[],
                           "TotalCount" => Int64[])

    # Calculate the maximum inventory level
    DummyInv = (1, 1, 1, 1)
    Data = CreateMDPData(DummyInv)
    BSLvlList = push!([0.1:0.1:0.9;], 0.95, 0.99, 0.999)
    pushfirst!(BSLvlList, 0.05)
    SLT = Data.Period
    LT = Data.Period + SLT # Lead time  = RF(Reorder frequency) + SLT(Supply lead time)
    for BSLvl in BSLvlList
        BS = BSCal(Data, BSLvl, LT)

        # Run the simulation (Pure base stock policy)
        SimPeriod = 1000000
        
        # Initialize data and information structure
        Info = CreateMDPInfo()
        Data = CreateMDPData(Tuple(BS))
        TotalCost, TotalInv, TotalDemand, TotalStockout, count = MDPSim(Data, Info, SimPeriod, BS, SLT)
        AvgTotalCost = round((TotalCost/(SimPeriod))*Data.Period, digits=2)
        AvgInvLvl = round((TotalInv/(SimPeriod))*Data.Period, digits=2)
        AvgDemand = round((TotalDemand/(SimPeriod))*Data.Period, digits=2)
        AvgStockout = round((TotalStockout/(SimPeriod))*Data.Period, digits=2)
        β = round(1 - AvgStockout/AvgDemand, digits=2)
        TotalCount = count
        push!(ResultsDf, (BSLvl, Tuple(BS), AvgTotalCost, AvgInvLvl, AvgStockout, AvgDemand, β, TotalCount))
    end
    # Save the results to a CSV file
    CSV.write("MDPExp12LT$(LT).csv", ResultsDf)
    println("Results Exported to CSV File... \n")
end

# Define a function to run the experiment
function MDPExpAMM()

    # Export the results to a CSV file
    ResultsDf = DataFrame("α" => Float64[], 
                           "BaseStock" => Tuple{Int64, Int64, Int64, Int64}[], 
                           "AvgTotalCost" => Float64[], 
                           "AvgTotalInvLvl" => Float64[],
                           "AvgTotalStockout" => Float64[],
                           "AvgTotalDemand" => Float64[],
                           "β" => Float64[],
                           "AvgInvCost" => Tuple{Float64, Float64, Float64, Float64}[],
                           "AvgBkCost" => Tuple{Float64, Float64, Float64, Float64}[],
                           "AvgLSCost" => Tuple{Float64, Float64, Float64, Float64}[],
                           "AvgProdCost" => Float64[],
                           "AvgPowderCost" => Float64[],
                           "AvgInvLvl" => Tuple{Float64, Float64, Float64, Float64}[],
                           "AvgBkLvl" => Tuple{Float64, Float64, Float64, Float64}[],
                           "AvgLsLvl" => Tuple{Float64, Float64, Float64, Float64}[],
                           "TotalCount" => Int64[])

    DummyInv = (1, 1, 1, 1)
    DummyData = CreateMDPData(DummyInv)
    # Calculate the maximum inventory level
    SLT = DummyData.Period
    LT = DummyData.Period + SLT # Lead time  = RF(Reorder frequency) + SLT(Supply lead time)
    InitBS = BSCal(DummyData, 0.999999999999999, LT)
    InitInfo = CreateMDPInfo()
    InitData = CreateMDPData(Tuple(InitBS))
    Info, Data = MDP_JRP_AM_M_v0_12(InitData, InitInfo)
    BSLvlList = push!([0.1:0.1:0.9;], 0.95, 0.99, 0.999)
    pushfirst!(BSLvlList, 0.05)
    for BSLvl in BSLvlList
        BS = BSCal(Data, BSLvl, LT)
    
        # Run the simulation 
        SimPeriod = 1000000
        
        # Initialize data and information structure
        Data = CreateMDPData(Tuple(BS))
        TotalCost, InvCostList, BackorderCostList, LostSalesCostList, TotalProductionCost, TotalPowderCost, TotalInv, TotalDemand, TotalStockout, InvList, BackorderList, LostSalesList, count = MDPSimAMM(Data, Info, SimPeriod, BS, InitBS, SLT)
        AvgTotalCost = round((TotalCost/(SimPeriod))*Data.Period, digits=2)
        AvgTotalInvLvl = round((TotalInv/(SimPeriod))*Data.Period, digits=2)
        AvgTotalDemand = round((TotalDemand/(SimPeriod))*Data.Period, digits=2)
        AvgTotalStockout = round((TotalStockout/(SimPeriod))*Data.Period, digits=2)
        AvgInvCost = round.((InvCostList./(SimPeriod)).*Data.Period, digits=2)
        AvgBkCost = round.((BackorderCostList./(SimPeriod)).*Data.Period, digits=2)
        AvgLsCost = round.((LostSalesCostList./(SimPeriod)).*Data.Period, digits=2)
        AvgProductionCost = round.((TotalProductionCost./(SimPeriod)).*Data.Period, digits=2)
        AvgPowderCost = round.((TotalPowderCost./(SimPeriod)).*Data.Period, digits=2)
        AvgInv = round.((InvList./(SimPeriod)).*Data.Period, digits=2)
        AvgBk = round.((BackorderList./(SimPeriod)).*Data.Period, digits=2)
        AvgLs = round.((LostSalesList./(SimPeriod))*Data.Period, digits=2)

        β = round(1 - AvgTotalStockout/AvgTotalDemand, digits=2)
        TotalCount = count
        push!(ResultsDf, (BSLvl, Tuple(BS), AvgTotalCost, AvgTotalInvLvl, AvgTotalStockout, AvgTotalDemand, β, Tuple(AvgInvCost), 
            Tuple(AvgBkCost), Tuple(AvgLsCost), AvgProductionCost, AvgPowderCost, Tuple(AvgInv), Tuple(AvgBk), Tuple(AvgLs),  TotalCount))
    end
    # Save the results to a CSV file
    CSV.write("MDPExp12AMMLT$(LT)_Cmplt.csv", ResultsDf)
    println("Results Exported to CSV File... \n")
end

# Define a function to run the experiment
function MDPExpAMS()

    # Export the results to a CSV file
    ResultsDf = DataFrame("α" => Float64[], 
                           "BaseStock" => Tuple{Int64, Int64, Int64, Int64}[], 
                           "AvgTotalCost" => Float64[], 
                           "AvgTotalInvLvl" => Float64[],
                           "AvgTotalStockout" => Float64[],
                           "AvgTotalDemand" => Float64[],
                           "β" => Float64[],
                           "AvgInvCost" => Tuple{Float64, Float64, Float64, Float64}[],
                           "AvgBkCost" => Tuple{Float64, Float64, Float64, Float64}[],
                           "AvgLSCost" => Tuple{Float64, Float64, Float64, Float64}[],
                           "AvgProdCost" => Float64[],
                           "AvgPowderCost" => Float64[],
                           "AvgInvLvl" => Tuple{Float64, Float64, Float64, Float64}[],
                           "AvgBkLvl" => Tuple{Float64, Float64, Float64, Float64}[],
                           "AvgLsLvl" => Tuple{Float64, Float64, Float64, Float64}[],
                           "TotalCount" => Int64[])

    DummyInv = (1, 1, 1, 1)
    DummyData = CreateMDPData(DummyInv)
    # Calculate the maximum inventory level
    SLT = DummyData.Period
    LT = DummyData.Period + SLT # Lead time  = RF(Reorder frequency) + SLT(Supply lead time)
    InitBS = BSCal(DummyData, 0.999999999999999, LT)
    InitInfo = CreateMDPInfo()
    InitData = CreateMDPData(Tuple(InitBS))
    Info, Data = MDP_JRP_AM_S_v0_12(InitData, InitInfo)
    BSLvlList = push!([0.1:0.1:0.9;], 0.95, 0.99, 0.999)
    pushfirst!(BSLvlList, 0.05)
    for BSLvl in BSLvlList
        BS = BSCal(Data, BSLvl, LT)
    
        # Run the simulation 
        SimPeriod = 1000000
        
        # Initialize data and information structure
        Data = CreateMDPData(Tuple(BS))
        TotalCost, InvCostList, BackorderCostList, LostSalesCostList, TotalProductionCost, TotalPowderCost, TotalInv, TotalDemand, TotalStockout, InvList, BackorderList, LostSalesList, count = MDPSimAMS(Data, Info, SimPeriod, BS, InitBS, SLT)
        AvgTotalCost = round((TotalCost/(SimPeriod))*Data.Period, digits=2)
        AvgTotalInvLvl = round((TotalInv/(SimPeriod))*Data.Period, digits=2)
        AvgTotalDemand = round((TotalDemand/(SimPeriod))*Data.Period, digits=2)
        AvgTotalStockout = round((TotalStockout/(SimPeriod))*Data.Period, digits=2)
        AvgInvCost = round.((InvCostList./(SimPeriod)).*Data.Period, digits=2)
        AvgBkCost = round.((BackorderCostList./(SimPeriod)).*Data.Period, digits=2)
        AvgLsCost = round.((LostSalesCostList./(SimPeriod)).*Data.Period, digits=2)
        AvgProductionCost = round.((TotalProductionCost./(SimPeriod)).*Data.Period, digits=2)
        AvgPowderCost = round.((TotalPowderCost./(SimPeriod)).*Data.Period, digits=2)
        AvgInv = round.((InvList./(SimPeriod)).*Data.Period, digits=2)
        AvgBk = round.((BackorderList./(SimPeriod)).*Data.Period, digits=2)
        AvgLs = round.((LostSalesList./(SimPeriod))*Data.Period, digits=2)

        β = round(1 - AvgTotalStockout/AvgTotalDemand, digits=2)
        TotalCount = count
        push!(ResultsDf, (BSLvl, Tuple(BS), AvgTotalCost, AvgTotalInvLvl, AvgTotalStockout, AvgTotalDemand, β, Tuple(AvgInvCost), 
            Tuple(AvgBkCost), Tuple(AvgLsCost), AvgProductionCost, AvgPowderCost, Tuple(AvgInv), Tuple(AvgBk), Tuple(AvgLs),  TotalCount))
    end
    # Save the results to a CSV file
    CSV.write("MDPExp12AMSLT$(LT)_Cmplt.csv", ResultsDf)
    println("Results Exported to CSV File... \n")
end

# Define a function to run the experiment
function MDPExpE()

    # Export the results to a CSV file
    ResultsDf = DataFrame("α" => Float64[], 
                           "BaseStock" => Tuple{Int64, Int64, Int64, Int64}[], 
                           "AvgTotalCost" => Float64[], 
                           "AvgTotalInvLvl" => Float64[],
                           "AvgTotalStockout" => Float64[],
                           "AvgTotalDemand" => Float64[],
                           "β" => Float64[],
                           "AvgInvCost" => Tuple{Float64, Float64, Float64, Float64}[],
                           "AvgBkCost" => Tuple{Float64, Float64, Float64, Float64}[],
                           "AvgLSCost" => Tuple{Float64, Float64, Float64, Float64}[],
                           "AvgProdCost" => Float64[],
                           "AvgPowderCost" => Float64[],
                           "AvgInvLvl" => Tuple{Float64, Float64, Float64, Float64}[],
                           "AvgBkLvl" => Tuple{Float64, Float64, Float64, Float64}[],
                           "AvgLsLvl" => Tuple{Float64, Float64, Float64, Float64}[],
                           "TotalCount" => Int64[])

    DummyInv = (1, 1, 1, 1)
    DummyData = CreateMDPData(DummyInv)
    # Calculate the maximum inventory level
    SLT = DummyData.Period
    LT = DummyData.Period + SLT # Lead time  = RF(Reorder frequency) + SLT(Supply lead time)
    InitBS = BSCal(DummyData, 0.999999999999999, LT)
    InitInfo = CreateMDPInfoE()
    InitData = CreateMDPData(Tuple(InitBS))
    Info, Data = MDP_JRP_AM_v0_12E(InitData, InitInfo)
    #BSLvlList = push!([0.1:0.1:0.9;], 0.95, 0.99, 0.999)
    BSLvlList = [0.05]
    #pushfirst!(BSLvlList, 0.05)
    for BSLvl in BSLvlList
        BS = BSCal(Data, BSLvl, LT)
    
        # Run the simulation 
        SimPeriod = 1000000
        
        # Initialize data and information structure
        Data = CreateMDPData(Tuple(BS))
        TotalCost, InvCostList, BackorderCostList, LostSalesCostList, TotalProductionCost, TotalPowderCost, TotalInv, TotalDemand, TotalStockout, InvList, BackorderList, LostSalesList, count = MDPSimE(Data, Info, SimPeriod, BS, InitBS, SLT)
        AvgTotalCost = round((TotalCost/(SimPeriod))*Data.Period, digits=2)
        AvgTotalInvLvl = round((TotalInv/(SimPeriod))*Data.Period, digits=2)
        AvgTotalDemand = round((TotalDemand/(SimPeriod))*Data.Period, digits=2)
        AvgTotalStockout = round((TotalStockout/(SimPeriod))*Data.Period, digits=2)
        AvgInvCost = round.((InvCostList./(SimPeriod)).*Data.Period, digits=2)
        AvgBkCost = round.((BackorderCostList./(SimPeriod)).*Data.Period, digits=2)
        AvgLsCost = round.((LostSalesCostList./(SimPeriod)).*Data.Period, digits=2)
        AvgProductionCost = round.((TotalProductionCost./(SimPeriod)).*Data.Period, digits=2)
        AvgPowderCost = round.((TotalPowderCost./(SimPeriod)).*Data.Period, digits=2)
        AvgInv = round.((InvList./(SimPeriod)).*Data.Period, digits=2)
        AvgBk = round.((BackorderList./(SimPeriod)).*Data.Period, digits=2)
        AvgLs = round.((LostSalesList./(SimPeriod))*Data.Period, digits=2)

        β = round(1 - AvgTotalStockout/AvgTotalDemand, digits=2)
        TotalCount = count
        push!(ResultsDf, (BSLvl, Tuple(BS), AvgTotalCost, AvgTotalInvLvl, AvgTotalStockout, AvgTotalDemand, β, Tuple(AvgInvCost), 
            Tuple(AvgBkCost), Tuple(AvgLsCost), AvgProductionCost, AvgPowderCost, Tuple(AvgInv), Tuple(AvgBk), Tuple(AvgLs),  TotalCount))
    end
    # Save the results to a CSV file
    CSV.write("MDPExp12ELT$(LT)_Cmplt.csv", ResultsDf)
    println("Results Exported to CSV File... \n")
end


# Define a function to run the experiment
function MDPExpAMHu()

    # Export the results to a CSV file
    ResultsDf = DataFrame("α" => Float64[], 
                           "BaseStock" => Tuple{Int64, Int64, Int64, Int64}[], 
                           "AvgTotalCost" => Float64[], 
                           "AvgTotalInvLvl" => Float64[],
                           "AvgTotalStockout" => Float64[],
                           "AvgTotalDemand" => Float64[],
                           "β" => Float64[],
                           "AvgInvCost" => Tuple{Float64, Float64, Float64, Float64}[],
                           "AvgBkCost" => Tuple{Float64, Float64, Float64, Float64}[],
                           "AvgLSCost" => Tuple{Float64, Float64, Float64, Float64}[],
                           "AvgProdCost" => Float64[],
                           "AvgPowderCost" => Float64[],
                           "AvgInvLvl" => Tuple{Float64, Float64, Float64, Float64}[],
                           "AvgBkLvl" => Tuple{Float64, Float64, Float64, Float64}[],
                           "AvgLsLvl" => Tuple{Float64, Float64, Float64, Float64}[],
                           "TotalCount" => Int64[])
    #=
    DummyInv = (1, 1, 1, 1)
    DummyData = CreateMDPData(DummyInv)
    # Calculate the maximum inventory level
    SLT = DummyData.Period
    LT = DummyData.Period + SLT # Lead time  = RF(Reorder frequency) + SLT(Supply lead time)
    InitBS = BSCal(DummyData, 0.999999999999999, LT)
    InitInfo = CreateMDPInfo()
    InitData = CreateMDPData(Tuple(InitBS))
    Info, Data = MDP_JRP_AM_v0_7(InitData, InitInfo)
    =#
    BSLvlList = push!([0.1:0.1:0.9;], 0.95, 0.99, 0.999)
    pushfirst!(BSLvlList, 0.05)
    DummyInv = (1, 1, 1, 1)
    DummyData = CreateMDPData(DummyInv)
    SLT = DummyData.Period
    LT = DummyData.Period + SLT # Lead time  = RF(Reorder frequency) + SLT(Supply lead time)
    for BSLvl in BSLvlList
        BS = BSCal(DummyData, BSLvl, LT)
    
        # Run the simulation 
        SimPeriod = 1000000
        
        # Initialize data and information structure
        Data = CreateMDPData(Tuple(BS))
        TotalCost, InvCostList, BackorderCostList, LostSalesCostList, TotalProductionCost, TotalPowderCost, TotalInv, TotalDemand, TotalStockout, InvList, BackorderList, LostSalesList, count = MDPSimAMHu(Data, SimPeriod, BS, SLT)
        AvgTotalCost = round((TotalCost/(SimPeriod))*Data.Period, digits=2)
        AvgTotalInvLvl = round((TotalInv/(SimPeriod))*Data.Period, digits=2)
        AvgTotalDemand = round((TotalDemand/(SimPeriod))*Data.Period, digits=2)
        AvgTotalStockout = round((TotalStockout/(SimPeriod))*Data.Period, digits=2)
        AvgInvCost = round.((InvCostList./(SimPeriod)).*Data.Period, digits=2)
        AvgBkCost = round.((BackorderCostList./(SimPeriod)).*Data.Period, digits=2)
        AvgLsCost = round.((LostSalesCostList./(SimPeriod)).*Data.Period, digits=2)
        AvgProductionCost = round.((TotalProductionCost./(SimPeriod)).*Data.Period, digits=2)
        AvgPowderCost = round.((TotalPowderCost./(SimPeriod)).*Data.Period, digits=2)
        AvgInv = round.((InvList./(SimPeriod)).*Data.Period, digits=2)
        AvgBk = round.((BackorderList./(SimPeriod)).*Data.Period, digits=2)
        AvgLs = round.((LostSalesList./(SimPeriod))*Data.Period, digits=2)

        β = round(1 - AvgTotalStockout/AvgTotalDemand, digits=2)
        TotalCount = count
        push!(ResultsDf, (BSLvl, Tuple(BS), AvgTotalCost, AvgTotalInvLvl, AvgTotalStockout, AvgTotalDemand, β, Tuple(AvgInvCost), 
            Tuple(AvgBkCost), Tuple(AvgLsCost), AvgProductionCost, AvgPowderCost, Tuple(AvgInv), Tuple(AvgBk), Tuple(AvgLs),  TotalCount))
    end
    # Save the results to a CSV file
    CSV.write("MDPExp12AMC2.5LT$(LT)V2_Cmplt.csv", ResultsDf)
    println("Results Exported to CSV File... \n")
end

println("Threads available: ", Threads.nthreads())
#@time MDPExp()
#@time MDPExpAMM()
#@time MDPExpAMS()
#@time MDPExpE()
@time MDPExpAMHu()