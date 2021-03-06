#' Run Seurat Integration
#'
#' run batch correction, followed by:
#' 1) stashing of batches in metadata 'batch'
#' 2) clustering with resolution 0.2 to 2.0 in increments of 0.2
#' 3) saving to <proj_dir>/output/sce/<feature>_seu_<suffix>.rds
#'
#' @param suffix a suffix to be appended to a file save in output dir
#' @param seu_list
#' @param resolution
#' @param algorithm
#' @param organism
#' @param ...
#'
#' @return
#' @export
#'
#' @examples
#'
#' batches <- panc8 %>%
#'   Seurat::SplitObject(split.by = "tech")
#'
#' integrated_seu <- seurat_integration_pipeline(batches)
seurat_integration_pipeline <- function(seu_list, resolution = seq(0.2, 2.0, by = 0.2), suffix = "", algorithm = 1, organism = "human", annotate_cell_cycle = FALSE, annotate_percent_mito = FALSE, ...) {
  experiment_names <- names(seu_list)

  organisms <- case_when(
    grepl("Hs", experiment_names) ~ "human",
    grepl("Mm", experiment_names) ~ "mouse"
  )

  names(organisms) <- experiment_names

  organisms[is.na(organisms)] <- organism

  integrated_seu <- seurat_integrate(seu_list, organism = organism, ...)

  # cluster merged seurat objects
  integrated_seu <- seurat_cluster(integrated_seu, resolution = resolution, algorithm = algorithm, ...)

  integrated_seu <- find_all_markers(integrated_seu)

  #   enriched_seu <- tryCatch(getEnrichedPathways(integrated_seu), error = function(e) e)
  #   enrichr_available <- !any(class(enriched_seu) == "error")
  #   if(enrichr_available){
  #     integrated_seu <- enriched_seu
  #   }

  # add read count column
  integrated_seu <- add_read_count_col(integrated_seu)

  # annotate cell cycle scoring to seurat objects
  if (annotate_cell_cycle) {
    integrated_seu <- annotate_cell_cycle(integrated_seu, ...)
  }

  # annotate mitochondrial percentage in seurat metadata
  if (annotate_percent_mito) {
    integrated_seu <- add_percent_mito(integrated_seu, ...)
  }

  # annotate excluded cells
  # integrated_seu <- annotate_excluded(integrated_seu, excluded_cells)

  return(integrated_seu)
}

#' Run Seurat Pipeline
#'
#' Preprocess, Cluster and Reduce Dimensions for a single seurat object
#'
#' @param seu
#' @param assay
#' @param resolution
#' @param reduction
#' @param organism
#'
#' @return
#' @export
#'
#' @examples
#'
#' processed_seu <- seurat_pipeline(panc8)
#'
seurat_pipeline <- function(seu, assay = "gene", resolution = 0.6, reduction = "pca", organism = "human", ...) {

  assays <- names(seu@assays)

  assays <- assays[assays %in% c("gene", "transcript")]

  for (assay in assays) {
    seu[[assay]] <- seurat_preprocess(seu[[assay]], scale = TRUE)
  }

  # PCA
  seu <- seurat_reduce_dimensions(seu, check_duplicates = FALSE, reduction = reduction, ...)

  seu <- seurat_cluster(seu = seu, resolution = resolution, reduction = reduction, ...)

  for (assay in assays) {
    seu <- find_all_markers(seu, resolution = resolution, seurat_assay = assay)
  }

  # if (feature == "gene"){
  #   enriched_seu <- tryCatch(getEnrichedPathways(seu), error = function(e) e)
  #   enrichr_available <- !any(class(enriched_seu) == "error")
  #   if(enrichr_available){
  #     seu <- enriched_seu
  #   }
  # }

  # annotate low read count category in seurat metadata
  seu <- seuratTools::add_read_count_col(seu)

  # annotate cell cycle scoring to seurat objects
  seu <- annotate_cell_cycle(seu, organism = organism, ...)

  # annotate mitochondrial percentage in seurat metadata
  seu <- add_percent_mito(seu, organism = organism)

  return(seu)
}
