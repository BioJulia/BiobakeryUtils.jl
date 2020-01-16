
"""
Given a file path or paths to abundance tables (eg humann2 or metaphlan2),
create abundance table. Table is presumed to have samples in columns and
features in rows. First column is taken as feature IDs.
"""
function import_abundance_table(file::AbstractString; delim::Char='\t')
    @info "Importing abundance table" file
    df = CSV.File(file, delim=delim) |> DataFrame
    rename!(df, names(df)[1] => :col1)
    return df
end


function import_abundance_tables(files::Array{<:AbstractString, 1}; delim::Char='\t')
    @info "Importing abundance tables"
    fulltable = DataFrame(col1=String[])
    for t in files
        df = import_abundance_table(t, delim=delim)
        fulltable = join(fulltable, df, on=:col1, kind=:outer)
    end

    # replace all missing values (from joins) with 0.
    fulltable = map(c -> eltype(c) <: Union{<:Number, Missing} ? collect(Missings.replace(c, 0)) : c, eachcol(fulltable))
    return fulltable
end


function clean_abundance_tables(files::Array{String, 1};
                        delim::Char='\t',
                        col1::Symbol=:taxon,
                        suffix::String="_taxonomic_profile")
    @info "Cleaning"
    t = import_abundance_tables(files, delim=delim)

    rename!(t, :col1 => col1)
    rename!(n-> Symbol(replace(String(n), suffix => "")), t)

    return t
end


function rm_strat!(df::DataFrame; col::Union{Int, Symbol}=1)
    filter!(row->!occursin(r"\|", row[1]), df)
end


function permanova(dm::Array{<:Real,2}, metadata::AbstractVector, nperm::Int=999;
                    label=nothing, datafilter=x->true)
    size(dm,1) != size(dm,2) && throw(ArgumentError("dm must be symetrical distance matrix"))
    size(dm,2) != length(metadata) && throw(ArgumentError("Metadata does not match the size of distance matrix"))
    let notmissing = map(!ismissing, metadata)
        metadata = metadata[notmissing]
        dm = dm[notmissing, notmissing]
    end

    filt = map(datafilter, metadata)
    r_dm = dm[filt, filt]
    metadata = metadata[filt]
    @rput r_dm
    @rput metadata
    reval("library(vegan)")

    reval("p <- adonis(r_dm ~ metadata, permutations = $nperm)")

    @rget p

    p = p[:aov_tab]
    if !isnothing(label)
        p[!,:label] = fill(label, size(p, 1))
    end

    return p
end


function permanova(dm, metadata::AbstractDataFrame, nperm=10000;
            datafilter=x->true,
            label=nothing,
            fields=names(metadata))

    let notmissing = map(row->all(!ismissing, row[fields]), eachrow(metadata))
        metadata = metadata[notmissing, :]
        dm = dm[notmissing, notmissing]
    end

    fields = join(String.(fields), " + ")

    filt = map(datafilter, eachrow(metadata))
    r_meta = metadata[filt, :]
    r_dm = dm[filt,filt]
    @rput r_meta
    @rput r_dm
    reval("library(vegan)")
    reval("p <- adonis(r_dm ~ $fields, data=r_meta, permutations = $nperm)")

    @rget p
    p = p[:aov_tab]
    if !isnothing(label)
        p[!,:label] = fill(label, size(p, 1))
    end

    return p
end
#==============
PanPhlAn Utils
==============#

function panphlan_calcs(df::DataFrame)
    abun = abundancetable(df)
    dm = pairwise(Jaccard(), abun, dims=2)
    rowdm = pairwise(Jaccard(), abun, dims=1)
    col_clust = hclust(dm, :single)
    row_clust = hclust(rowdm, :single)
    optimalorder!(col_clust, dm)
    optimalorder!(row_clust, rowdm)

    mds = fit(MDS, dm, distances=true)

    return abun, dm, col_clust, row_clust, mds
end
