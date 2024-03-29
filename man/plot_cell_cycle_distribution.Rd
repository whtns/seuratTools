% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/plotting.R
\name{plot_cell_cycle_distribution}
\alias{plot_cell_cycle_distribution}
\title{Plot cell cycle distribution grouped by metadata}
\usage{
plot_cell_cycle_distribution(seu, features)
}
\arguments{
\item{seu}{A seurat object}

\item{features}{Features to plot (gene expression, metrics, PC scores, anything that can be retreived by Seurat::FetchData)}
}
\description{
Plot ridge plots of G1, S, and G2M phases grouped by provided metadata
}
