# This file is to create a customized data structure for passing data into the following modules

# Import pacjages
using DataStructures, Random, Statistics, Distributions

# Define the structure
mutable struct DefMDPData
    Nᵢ::Int64                   # Number of items
    Period::Int64               # Maximum period during a replenishment cycle
    MinI::NTuple{4, Int64}                 # Minimum inventory level
    MaxI::NTuple{4, Int64}                # Maximum inventory level
    c::Float64                  # Fixed production cost for a single layer
    pd::Float64                 # Powder cost
    h::NTuple{4, Float64}                    # Holding Cost
    b::NTuple{4, Float64}                    # Backorder Cost
    ls::NTuple{4, Float64}                   # Lost Sales Cost
    ep::NTuple{4, Float64}                   # End of period backorder penalty cost
    w::NTuple{4, Float64}                    # Weight of each item
    v::Float64                               # Emergency shipment cost per unit weight
    PeriodE::Int64                           # Shipment time for the emergency shipment 
    Cap::Int64                  # The maximum number of products can be built in a single layer
    BH::NTuple{4, Int64}                   # Build height for each item
    DPattern::Vector{NTuple{3, Int64}}        # Demand Pattern for each item
    ProbDPattern::Vector{NTuple{3, Float64}}    # Probability Distribution for each item's demand pattern
    D::Vector{NTuple{4, Int64}}                   # Demand Distribution 
    ProbD::Vector{Float64}                # Probability of each demand pattern
end

# Define a function to create the data structure
function CreateMDPData(MaxI::NTuple)
    Nᵢ = 4
    Period = 5
    MinI = (-2, -2, -2, -2)
    #MaxI = (5, 7, 6, 3)
    c = 5.0
    pd = 10.0
    h = (1, 1, 1, 1)
    b = (5, 10, 15, 20)
    ls = (50, 50, 50, 50)
    ep = (5, 10, 15, 20)
    w = (2, 2, 1, 1)
    v = 10
    PeriodE = 2
    Cap = 10
    BH = (2, 2, 1, 1)
    DPattern = [(0, 1, 2), (0, 1, 2), (0, 1, 2), (0, 1, 2)]
    ProbDPattern = [(0.5, 0.3, 0.2), (0.3, 0.1, 0.6), (0.4, 0.3, 0.3), (0.3, 0.5, 0.2)]
    #DPattern = [(0, 1), (0, 1), (0, 1), (0, 1)]
    #ProbDPattern = [(0.5, 0.5), (0.3, 0.7), (0.4, 0.6), (0.8, 0.2)]
    D = Vector{NTuple{4, Int64}}()        # Create an array to store tuples of demand patterns
    ProbD = Float64[]   # Create an array to store the probability (Float64) of each demand pattern
    
    # Generate all possible demand patterns and their probabilities
    for idx1 in 1:length(DPattern[1])
        for idx2 in 1:length(DPattern[2])
            for idx3 in 1:length(DPattern[3])
                for idx4 in 1:length(DPattern[4])
                    push!(D, (DPattern[1][idx1], DPattern[2][idx2], DPattern[3][idx3], DPattern[4][idx4]))
                    push!(ProbD, ProbDPattern[1][idx1]*ProbDPattern[2][idx2]*ProbDPattern[3][idx3]*ProbDPattern[4][idx4])
                end
            end
        end
    end
    return DefMDPData(Nᵢ, Period, MinI, MaxI, c, pd, h, b, ls, ep, w, v, PeriodE, Cap, BH, DPattern, ProbDPattern, D, ProbD)
end
