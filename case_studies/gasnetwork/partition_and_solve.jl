#create gasnetwork optigraph model
include((@__DIR__)*"/gasnetwork.jl")

#Obtain a hyergraph representation of the gas_network
hypergraph,hyper_map = gethypergraph(gas_network)

#Setup node and edge weights
n_vertices = length(vertices(hypergraph))
node_sizes = [num_variables(node) for node in all_nodes(gas_network)]
edge_weights = [num_linkconstraints(edge) for edge in all_edges(gas_network)]

#Use KaHyPar to partition the hypergraph
node_vector = KaHyPar.partition(hypergraph,n_parts,configuration = :edge_cut,
imbalance = max_imbalance, node_sizes = node_sizes, edge_weights = edge_weights)

#Create an optigraph partition
partition = Partition(gas_network,node_vector,hyper_map)

#Setup subgraphs based on partition
make_subgraphs!(gas_network,partition)

#Combine the subgraphs into model-nodes
combined_graph , combine_map  = aggregate(gas_network,0)

#scale the objective function on each optinode
for node in all_nodes(combined_graph)
    @objective(node,Min,1e-6*objective_function(node))
end

##############################
# Solve with PIPS-NLP
##############################
#get the julia ids of the mpi workers
julia_workers = sort(collect(values(manager.mpi2j)))

#Distribute the optigraph among the workers
#Here, we create the variable `pipsgraph` on each worker
remote_references = PipsSolver.distribute(combined_graph,julia_workers,remote_name = :pipsgraph)

#Solve with PIPS-NLP on each mpi rank
@mpi_do manager begin
    using MPI
    PipsSolver.pipsnlp_solve(pipsgraph)
end
