% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/workflow.R
\name{clustering_workflow}
\alias{clustering_workflow}
\title{Clustering Workflow}
\usage{
clustering_workflow(
  proj_dir,
  feature_seus = NULL,
  excluded_cells,
  cell_cycle = T,
  resolution = seq(0.2, 2, by = 0.2),
  ...
)
}
\arguments{
\item{proj_dir}{home directory of current project}

\item{excluded_cells}{named list of cells to exclude}

\item{...}{}
}
\value{

}
\description{
Integrate multiple seurat objects and save to file
}