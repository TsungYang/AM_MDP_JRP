# This file is to create a function that estimates the total cost, inventory cost, and backorder cost of a 
# production quantity


# Create function
function DemandGenerator(DGen, Pattern, ProbD)
    Demand = 0
    Rdm = rand(DGen)
    ProbCum = cumsum(ProbD)
    for j in 1:length(ProbCum)
        if Rdm <= ProbCum[j]
            Demand = Pattern[j]
            break
        end
    end
    return Demand
end

# create function
function EstimatePre(i, Data, CurrInv)

    seed = [23423, 700234, 92397, 110907]
    DGen = Xoshiro(seed[i])
    Replicates = 500
    EndBkList = Vector{Int64}(undef, Replicates)

    for rep in 1:Replicates
        InvLvl = CurrInv
        d = DemandGenerator(DGen, Data.DPattern[i], Data.ProbDPattern[i])
        InvLvl -= d
        EndBkList[rep] = abs.(min.(InvLvl, 0))
    end
    AvgEndBk = mean(EndBkList)
    
    return AvgEndBk
end

# create function
function Estimate(i, period, Data, CurrInv, ProdQty)

    seed = [23423, 700234, 92397, 110907]
    DGen = Xoshiro(seed[i])
    Replicates = 100
    InvList = Vector{Int64}(undef, Replicates)
    BkList = Vector{Int64}(undef, Replicates)
    EndInvList = Vector{Int64}(undef, Replicates)
    EndBkList = Vector{Int64}(undef, Replicates)

    for rep in 1:Replicates
        InvLvl = CurrInv
        Inv = 0
        Bk = 0
        for prd in 1:period
            if prd == 1
                d = DemandGenerator(DGen, Data.DPattern[i], Data.ProbDPattern[i])
                InvLvl -= d
                InvLvl += ProdQty
            else
                Inv += max.(InvLvl, 0)
                Bk += abs.(min.(InvLvl, 0))
                d = DemandGenerator(DGen, Data.DPattern[i], Data.ProbDPattern[i])
                InvLvl -= d
            end
        end
        InvList[rep] = Inv
        BkList[rep] = Bk
        EndInvList[rep] = max.(InvLvl, 0)
        EndBkList[rep] = abs.(min.(InvLvl, 0))
    end
    AvgInv = mean(InvList)
    AvgBk = mean(BkList)
    AvgEndInv = mean(EndInvList)
    AvgEndBk = mean(EndBkList)
    return AvgInv, AvgBk, AvgEndInv, AvgEndBk
end
#Estimate(1, 2, Data, -2, 2)