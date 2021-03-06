% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/plotting.R
\name{plot_all_transcripts}
\alias{plot_all_transcripts}
\title{Plot All Transcripts}
\usage{
plot_all_transcripts(seu, features, embedding = "umap")
}
\arguments{
\item{transcripts}{}
}
\value{

}
\description{
Plot All Transcripts
}
\examples{

processed_seu <- clustering_workflow(human_gene_transcript_seu)
transcripts_to_plot <- genes_to_transcripts("RXRG")
plot_all_transcripts(processed_seu, features = transcripts_to_plot)

}
