
#' Cross plot vars
#'
#' @param seu
#' @param resolution
#' @param mycols
#'
#' @return
#' @export
#'
#' @examples
#'
cross_plot_vars <- function(seu, resolution, mycols) {

  if ("integrated" %in% names(seu@assays)) {
    active_assay <- "integrated"
  }
  else {
    active_assay <- "gene"
  }

  cluster_resolution = paste0(active_assay,
                              "_snn_res.", resolution)
  mycols <- gsub("^seurat$", cluster_resolution, mycols)
  newcolname = paste(mycols, collapse = "_by_")

  newdata <- seu[[mycols]] %>%
    tidyr::unite(!!newcolname, mycols)

  Idents(seu) <- newdata

  return(seu)

}

#' Plot pseudotime over multiple branches
#'
#' @param cds
#' @param branches
#' @param branches_name
#' @param cluster_rows
#' @param hclust_method
#' @param num_clusters
#' @param hmcols
#' @param add_annotation_row
#' @param add_annotation_col
#' @param show_rownames
#' @param use_gene_short_name
#' @param norm_method
#' @param scale_max
#' @param scale_min
#' @param trend_formula
#' @param return_heatmap
#' @param cores
#'
#' @return
#' @export
#'
#' @examples
plot_multiple_branches_heatmap <- function(cds,
                                           branches,
                                           branches_name = NULL,
                                           cluster_rows = TRUE,
                                           hclust_method = "ward.D2",
                                           num_clusters = 6,

                                           hmcols = NULL,

                                           add_annotation_row = NULL,
                                           add_annotation_col = NULL,
                                           show_rownames = FALSE,
                                           use_gene_short_name = TRUE,

                                           norm_method = c("vstExprs", "log"),
                                           scale_max=3,
                                           scale_min=-3,

                                           trend_formula = '~sm.ns(Pseudotime, df=3)',

                                           return_heatmap=FALSE,
                                           cores=1){
  pseudocount <- 1
  if(!(all(branches %in% Biobase::pData(cds)$State)) & length(branches) == 1){
    stop('This function only allows to make multiple branch plots where branches is included in the pData')
  }

  branch_label <- branches
  if(!is.null(branches_name)){
    if(length(branches) != length(branches_name)){
      stop('branches_name should have the same length as branches')
    }
    branch_label <- branches_name
  }

  #test whether or not the states passed to branches are true branches (not truncks) or there are terminal cells
  g <- cds@minSpanningTree
  m <- NULL
  # branche_cell_num <- c()
  for(branch_in in branches) {
    branches_cells <- row.names(subset(Biobase::pData(cds), State == branch_in))
    root_state <- subset(Biobase::pData(cds), Pseudotime == 0)[, 'State']
    root_state_cells <- row.names(subset(Biobase::pData(cds), State == root_state))

    if(cds@dim_reduce_type != 'ICA') {
      root_state_cells <- unique(paste('Y_', cds@auxOrderingData$DDRTree$pr_graph_cell_proj_closest_vertex[root_state_cells, ], sep = ''))
      branches_cells <- unique(paste('Y_', cds@auxOrderingData$DDRTree$pr_graph_cell_proj_closest_vertex[branches_cells, ], sep = ''))
    }
    root_cell <- root_state_cells[which(degree(g, v = root_state_cells) == 1)]
    tip_cell <- branches_cells[which(degree(g, v = branches_cells) == 1)]

    traverse_res <- traverseTree(g, root_cell, tip_cell)
    path_cells <- names(traverse_res$shortest_path[[1]])

    if(cds@dim_reduce_type != 'ICA') {
      pc_ind <- cds@auxOrderingData$DDRTree$pr_graph_cell_proj_closest_vertex
      path_cells <- row.names(pc_ind)[paste('Y_', pc_ind[, 1], sep = '') %in% path_cells]
    }

    cds_subset <- cds[, path_cells]

    newdata <- data.frame(Pseudotime = seq(0, max(Biobase::pData(cds_subset)$Pseudotime),length.out = 100))

    tmp <- genSmoothCurves(cds_subset, cores=cores, trend_formula = trend_formula,
                           relative_expr = T, new_data = newdata)
    if(is.null(m))
      m <- tmp
    else
      m <- cbind(m, tmp)
  }

  #remove genes with no expression in any condition
  m=m[!apply(m,1,sum)==0,]

  norm_method <- match.arg(norm_method)

  # FIXME: this needs to check that vst values can even be computed. (They can only be if we're using NB as the expressionFamily)
  if(norm_method == 'vstExprs' && is.null(cds@dispFitInfo[["blind"]]$disp_func) == FALSE) {
    m = vstExprs(cds, expr_matrix=m)
  }
  else if(norm_method == 'log') {
    m = log10(m+pseudocount)
  }

  # Row-center the data.
  m=m[!apply(m,1,sd)==0,]
  m=Matrix::t(scale(Matrix::t(m),center=TRUE))
  m=m[is.na(row.names(m)) == FALSE,]
  m[is.nan(m)] = 0
  m[m>scale_max] = scale_max
  m[m<scale_min] = scale_min

  heatmap_matrix <- m

  row_dist <- as.dist((1 - cor(Matrix::t(heatmap_matrix)))/2)
  row_dist[is.na(row_dist)] <- 1

  if(is.null(hmcols)) {
    bks <- seq(-3.1,3.1, by = 0.1)
    hmcols <- colorRamps::blue2green2red(length(bks) - 1)
  }
  else {
    bks <- seq(-3.1,3.1, length.out = length(hmcols))
  }

  ph <- pheatmap(heatmap_matrix,
                 useRaster = T,
                 cluster_cols=FALSE,
                 cluster_rows=T,
                 show_rownames=F,
                 show_colnames=F,
                 clustering_distance_rows=row_dist,
                 clustering_method = hclust_method,
                 cutree_rows=num_clusters,
                 silent=TRUE,
                 filename=NA,
                 breaks=bks,
                 color=hmcols)

  annotation_col <- data.frame(Branch=factor(rep(rep(branch_label, each = 100))))
  annotation_row <- data.frame(Cluster=factor(cutree(ph$tree_row, num_clusters)))
  col_gaps_ind <- c(1:(length(branches) - 1)) * 100

  if(!is.null(add_annotation_row)) {
    old_colnames_length <- ncol(annotation_row)
    annotation_row <- cbind(annotation_row, add_annotation_row[row.names(annotation_row), ])
    colnames(annotation_row)[(old_colnames_length+1):ncol(annotation_row)] <- colnames(add_annotation_row)
    # annotation_row$bif_time <- add_annotation_row[as.character(Biobase::fData(absolute_cds[row.names(annotation_row), ])$gene_short_name), 1]
  }


  if (use_gene_short_name == TRUE) {
    if (is.null(Biobase::fData(cds)$gene_short_name) == FALSE) {
      feature_label <- as.character(Biobase::fData(cds)[row.names(heatmap_matrix), 'gene_short_name'])
      feature_label[is.na(feature_label)] <- row.names(heatmap_matrix)

      row_ann_labels <- as.character(Biobase::fData(cds)[row.names(annotation_row), 'gene_short_name'])
      row_ann_labels[is.na(row_ann_labels)] <- row.names(annotation_row)
    }
    else {
      feature_label <- row.names(heatmap_matrix)
      row_ann_labels <- row.names(annotation_row)
    }
  }
  else {
    feature_label <- row.names(heatmap_matrix)
    row_ann_labels <- row.names(annotation_row)
  }

  row.names(heatmap_matrix) <- feature_label
  row.names(annotation_row) <- row_ann_labels


  colnames(heatmap_matrix) <- c(1:ncol(heatmap_matrix))

  if(!(cluster_rows)) {
    annotation_row <- NA
  }

  ph_res <- pheatmap(heatmap_matrix[, ], #ph$tree_row$order
                     useRaster = T,
                     cluster_cols = FALSE,
                     cluster_rows = cluster_rows,
                     show_rownames=show_rownames,
                     show_colnames=F,
                     #scale="row",
                     clustering_distance_rows=row_dist, #row_dist
                     clustering_method = hclust_method, #ward.D2
                     cutree_rows=num_clusters,
                     # cutree_cols = 2,
                     annotation_row=annotation_row,
                     annotation_col=annotation_col,
                     gaps_col = col_gaps_ind,
                     treeheight_row = 20,
                     breaks=bks,
                     fontsize = 12,
                     color=hmcols,
                     silent=TRUE,
                     border_color = NA,
                     filename=NA
  )

  grid::grid.rect(gp=grid::gpar("fill", col=NA))
  grid::grid.draw(ph_res$gtable)
  if (return_heatmap){
    return(ph_res)
  }
}


#' Plot Metadata Variables
#'
#' @param seu
#' @param embedding
#' @param group
#' @param ...
#'
#' @return
#' @export
#'
#' @examples
#'
#' # static mode
#' plot_var(panc8, group = "batch", return_plotly  = FALSE)
#'
#' # interactive plotly plot
#' plotly_plot <- plot_var(panc8, group = "batch")
#' print(plotly_plot)
#'
plot_var <- function(seu, embedding = "umap", group = "batch", dims = c(1,2), highlight = NULL, pt.size = 1.0, return_plotly = TRUE, ...){

  Seurat::DefaultAssay(seu) <- "gene"

  # metadata <- tibble::as_tibble(seu[[]][Seurat::Cells(seu),], rownames = "sID")
  # cellid <- metadata[["sID"]]
  # key <- rownames(metadata)

  metadata <- seu[[]][Seurat::Cells(seu),]
  key <- rownames(metadata)

  if (embedding == "umap"){
    dims = c(1,2)

  } else if (embedding == "tsne"){
    dims = c(1,2)
  }

  dims <- as.numeric(dims)

  d <- Seurat::DimPlot(object = seu, dims = dims, reduction = embedding, group.by = group, pt.size = pt.size, ...) +
    aes(key = key, cellid = key) +
    # theme(legend.text=element_text(size=10)) +
    NULL

  if (return_plotly == FALSE) return(d)

  plotly_plot <- plotly::ggplotly(d, tooltip = "cellid", height  = 500) %>%
    # htmlwidgets::onRender(javascript) %>%
    # plotly::highlight(on = "plotly_selected", off = "plotly_relayout") %>%
    plotly_settings() %>%
    plotly::toWebGL() %>%
    # plotly::partial_bundle() %>%
    identity()

}

#' Plotly settings
#'
#' @param plotly_plot
#' @param width
#' @param height
#'
#' @return
#'
#' @examples
plotly_settings <- function(plotly_plot, width = 600, height = 700){
  plotly_plot %>%
    plotly::layout(dragmode = "lasso") %>%
    plotly::config(
      toImageButtonOptions = list(
        format = "png",
        filename = "myplot",
        width = width,
        height = height
      )) %>%
    identity()
}


#' plot Violin plot
#'
#' @param seu
#' @param plot_var
#' @param plot_vals
#' @param features
#' @param assay
#' @param ...
#'
#' @return
#' @export
#'
#' @examples
#'
#' plot_violin(panc8, plot_var = "batch", features = c("NRL"))
#'
plot_violin <- function(seu, plot_var = "batch", plot_vals = NULL, features = "RXRG", assay = "gene", ...){

  if (is.null(plot_vals)) {
    plot_vals = unique(seu[[]][[plot_var]])
    plot_vals <- plot_vals[!is.na(plot_vals)]
  }
  seu <- seu[, seu[[]][[plot_var]] %in% plot_vals]
  vln_plot <- Seurat::VlnPlot(seu, features = features, group.by = plot_var, assay = assay, pt.size = 1, ...) +
    geom_boxplot(width = 0.2) +
    # labs(title = "Expression Values for each cell are normalized by that cell's total expression then multiplied by 10,000 and natural-log transformed") +
    # stat_summary(fun.y = mean, geom = "line", size = 4, colour = "black") +
    NULL

  print(vln_plot)

}


#' Plot Feature
#'
#' Plots gene or transcript expression overlaid on a given embedding.
#' If multiple features are supplied the joint density of all features
#' will be plotted using [Nebulosa](https://www.bioconductor.org/packages/devel/bioc/html/Nebulosa.html)
#'
#' @param seu
#' @param embedding
#' @param features
#' @param dims
#'
#' @return
#' @export
#' @importFrom ggplot2 aes
#'
#' @examples
#'
#' # static, single feature
#' plot_feature(panc8, embedding = "umap", features = c("NRL"), return_plotly = FALSE)
#' # static, multi-feature
#' plot_feature(panc8, embedding = "umap", features = c("RXRG", "NRL"), return_plotly = FALSE)
#' # interactive, multi-feature
#' plotly_plot <- plot_feature(panc8, embedding = "umap", features = c("RXRG", "NRL"))
#' print(plotly_plot)
#'
plot_feature <- function(seu, embedding = c("umap", "pca", "tsne"), features, dims = c(1,2), return_plotly = TRUE, pt.size = 1.0){

  Seurat::DefaultAssay(seu) <- "gene"

  metadata <- seu[[]][Seurat::Cells(seu),]
  key <- rownames(metadata)

  if (embedding %in% c("tsne", "umap")){
    dims = c(1,2)
  }

  dims <- as.numeric(dims)

  if(length(features) == 1){

  fp <- Seurat::FeaturePlot(object = seu, features = features, dims = dims, reduction = embedding, pt.size = pt.size, blend = FALSE)	+
    ggplot2::aes(key = key, cellid = key, alpha = 0.7)
  } else if(length(features) > 1){
    nebulosa_plots <- Nebulosa::plot_density(object = seu, features = features, dims = dims, reduction = embedding, size = pt.size, joint = TRUE, combine = FALSE)

    fp <- dplyr::last(nebulosa_plots) +
      ggplot2::aes(key = key, cellid = key, alpha = 0.7)
  }

  if (return_plotly == FALSE) return(fp)

  plotly_plot <- plotly::ggplotly(fp, tooltip = "cellid", height = 500) %>%
    plotly_settings() %>%
    plotly::toWebGL() %>%
    # plotly::partial_bundle() %>%
    identity()

}

#' Plot Ridges
#'
#' Plot ridge plots for cell cycle scoring
#'
#' @param seu
#' @param features
#'
#' @return
#' @export
#'
#' @examples
plot_ridge <- function(seu, features){

  cc_genes_path <- "~/single_cell_projects/resources/regev_lab_cell_cycle_genes.txt"
  cc.genes <- readLines(con = cc_genes_path)
  s.genes <- cc.genes[1:43]
  g2m.genes <- cc.genes[44:97]

  seu <- CellCycleScoring(object = seu, s.genes, g2m.genes,
                          set.ident = TRUE)

  RidgePlot(object = seu, features = features)

  # plotly::ggplotly(r, height = 750)
  #
}


#' Plot Cluster Marker Genes
#'
#' Plot a dot plot of n marker features grouped by cell metadata
#' available methods are wilcoxon rank-sum test implemented in
#' [presto](https://github.com/immunogenomics/presto) and specificity scores implemented in [genesorteR](https://github.com/mahmoudibrahim/genesorteR)
#'
#' @param seu
#' @param marker_method
#' @param metavar
#' @param num_markers
#' @param selected_values
#' @param return_plotly
#' @param featureType
#' @param hide_pseudo
#' @param ...
#'
#' @return
#' @export
#'
#' @examples
#'
#' # interactive mode using "presto"
#' plot_markers(panc8, metavar = "tech", marker_method = "presto", return_plotly = TRUE)
#'
#' # static mode using "presto"
#' plot_markers(panc8, metavar = "tech", marker_method = "genesorteR", return_plotly = FALSE)
#'
plot_markers <- function(seu, metavar = "batch", num_markers = 5, selected_values = NULL, return_plotly = TRUE, marker_method = c("presto", "genesorteR"), seurat_assay = "gene", hide_pseudo = FALSE, unique_markers = FALSE, ...){
  Idents(seu) <- seu[[metavar]]

  # by default only resolution markers are calculated in pre-processing
  seu <- find_all_markers(seu, metavar, seurat_assay = seurat_assay)

  markers <- seu@misc$markers[[metavar]][[marker_method]] %>%
    dplyr::mutate(dplyr::across(.fns = as.character))

  if(hide_pseudo){

    markers <- purrr::map(markers, c)
    markers <- purrr::map(markers, ~.x[!.x %in% pseudogenes[[seurat_assay]]])

    min_length <- min(purrr::map_int(markers, length))

    markers <- purrr::map(markers, head, min_length) %>%
      dplyr::bind_cols()

  }

  if(unique_markers){
    markers <-
      markers %>%
      dplyr::mutate(precedence = row_number()) %>%
      pivot_longer(-precedence, names_to = "group", values_to = "markers") %>%
      dplyr::arrange(markers, precedence) %>%
      dplyr::group_by(markers) %>%
      dplyr::filter(row_number() == 1) %>%
      dplyr::arrange(group, precedence) %>%
      tidyr::drop_na() %>%
      dplyr::group_by(group) %>%
      dplyr::mutate(precedence = row_number()) %>%
      tidyr::pivot_wider(names_from = "group", values_from = "markers") %>%
      dplyr::select(-precedence)
  }

  sliced_markers <-
    markers %>%
    dplyr::slice_head(n = num_markers) %>%
    tidyr::pivot_longer(everything(), names_to = "group", values_to = "feature") %>%
    dplyr::arrange(group) %>%
    # dplyr::top_n(n = num_markers, wt = logFC) %>%
    identity()

  if(!is.null(selected_values)){
    seu <- seu[,Idents(seu) %in% selected_values]
    sliced_markers <- sliced_markers %>%
      dplyr::filter(group %in% selected_values)
  }

  sliced_markers <- dplyr::pull(sliced_markers, feature)

  sliced_markers <- unique(sliced_markers[sliced_markers %in% rownames(seu)])

  seu[[metavar]][is.na(seu[[metavar]])] <- "NA"
  Idents(seu) <- metavar

  markerplot <- DotPlot(seu, features = sliced_markers, group.by = metavar, dot.scale = 3) +
    ggplot2::theme(axis.text.x = ggplot2::element_text(size = 10, angle = 45, vjust = 1, hjust=1),
          axis.text.y = ggplot2::element_text(size = 10)) +
    ggplot2::scale_y_discrete(position = "right") +
    ggplot2::coord_flip() +
    NULL

  if (return_plotly == FALSE) return(markerplot)

  plot_height = (150*num_markers)
  plot_width = (100*length(levels(Idents(seu))))

  markerplot <- plotly::ggplotly(markerplot, height = plot_height, width = plot_width) %>%
    plotly_settings() %>%
    plotly::toWebGL() %>%
    # plotly::partial_bundle() %>%
    identity()

  return(list(plot = markerplot, markers = markers))

}

#' Plot Read Count
#'
#' @param seu
#' @param metavar
#' @param color.by
#' @param yscale
#' @param return_plotly
#'
#' @return
#' @export
#'
#' @examples
#' #interactive plotly
#' plot_readcount(panc8)
#' # static plot
#' plot_readcount(panc8, return_plotly = FALSE)
#'
#' @importFrom ggplot2 ggplot aes geom_bar theme labs scale_y_log10
plot_readcount <- function(seu, metavar = "nCount_RNA", color.by = "batch", yscale = "linear", return_plotly = TRUE, ...){

  seu_tbl <- tibble::rownames_to_column(seu[[]], "SID") %>%
    dplyr::select(SID, !!as.symbol(metavar), !!as.symbol(color.by))

  rc_plot <-
    ggplot(seu_tbl, aes(x = reorder(SID, -!!as.symbol(metavar)),
                        y = !!as.symbol(metavar), fill = !!as.symbol(color.by))) +
    geom_bar(position = "identity", stat = "identity") +
    theme(axis.text.x = element_blank()) + labs(title = metavar,
                                                x = "Sample") +
    NULL

  if(yscale == "log"){
    rc_plot <-
      rc_plot +
      scale_y_log10()
  }

  if (return_plotly == FALSE) return(rc_plot)

  rc_plot <- plotly::ggplotly(rc_plot, tooltip = "cellid", height  = 500) %>%
    # htmlwidgets::onRender(javascript) %>%
    # plotly::highlight(on = "plotly_selected", off = "plotly_relayout") %>%
    plotly_settings() %>%
    plotly::toWebGL() %>%
    # plotly::partial_bundle() %>%
    identity()

}


#' Plot Annotated Complexheatmap from Seurat object
#'
#' @param object
#' @param features
#' @param cells
#' @param group.by
#' @param slot
#' @param assay
#' @param group.bar.height
#' @param cluster_columns FALSE
#' @param col_dendrogram
#' @param column_split
#' @param mm_col_dend
#' @param ...
#'
#' @return
#' @export
#'
#' @examples
#'
#' # plot top 50 variable genes
#' top_50_features <- VariableFeatures(panc8)[1:50]
#' seu_complex_heatmap(panc8, features = top_50_features)
#'
seu_complex_heatmap <- function(seu, features = NULL, cells = NULL, group.by = "ident",
                                slot = "scale.data", assay = NULL, group.bar.height = 0.01,
                                cluster_columns = FALSE, column_split = NULL, col_dendrogram = "ward.D2", mm_col_dend = 30, ...)
{
  cells <- cells %||% colnames(x = seu)
  if (is.numeric(x = cells)) {
    cells <- colnames(x = seu)[cells]
  }
  assay <- assay %||% Seurat::DefaultAssay(object = seu)
  Seurat::DefaultAssay(object = seu) <- assay
  features <- features %||% VariableFeatures(object = seu)
  features <- rev(x = unique(x = features))
  possible.features <- rownames(x = GetAssayData(object = seu,
                                                 slot = slot))
  if (any(!features %in% possible.features)) {
    bad.features <- features[!features %in% possible.features]
    features <- features[features %in% possible.features]
    if (length(x = features) == 0) {
      stop("No requested features found in the ", slot,
           " slot for the ", assay, " assay.")
    }
    warning("The following features were omitted as they were not found in the ",
            slot, " slot for the ", assay, " assay: ", paste(bad.features,
                                                             collapse = ", "))
  }
  data <- as.data.frame(x = t(x = as.matrix(x = GetAssayData(object = seu,
                                                             slot = slot)[features, cells, drop = FALSE])))
  seu <- suppressMessages(expr = StashIdent(object = seu,
                                               save.name = "ident"))

  if (col_dendrogram %in% c("ward.D", "single", "complete", "average", "mcquitty",
                            "median", "centroid", "ward.D2")){
    cluster_columns <-
      Seurat::Embeddings(seu, "pca") %>%
      dist() %>%
      hclust(col_dendrogram)
  } else {
    ordered_meta <- seu[[col_dendrogram]][order(seu[[col_dendrogram]]), ,drop = FALSE]
    column_split <- ordered_meta[,1]
    cells <- rownames(ordered_meta)
    data <- data[cells,]

    group.by = union(group.by, col_dendrogram)
  }

  group.by <- group.by %||% "ident"
  groups.use <- seu[[group.by]][cells, , drop = FALSE]

  groups.use <- groups.use %>%
    tibble::rownames_to_column("sample_id") %>%
    dplyr::mutate(across(where(is.character), as.factor)) %>%
    data.frame(row.names = 1) %>%
    identity()

  # factor colors
  groups.use.factor <- groups.use[sapply(groups.use, is.factor)]
  ha_cols.factor <- NULL
  if (length(groups.use.factor) > 0){
    ha_col_names.factor <- lapply(groups.use.factor, levels)

    ha_cols.factor <- purrr::map(ha_col_names.factor, ~scales::hue_pal()(length(.x))) %>%
      purrr::map2(ha_col_names.factor, set_names)
  }

  # numeric colors
  groups.use.numeric <- groups.use[sapply(groups.use, is.numeric)]
  ha_cols.numeric <- NULL
  if (length(groups.use.numeric) > 0){
    numeric_col_fun = function(myvec, color){
      circlize::colorRamp2(range(myvec), c("white", color))
    }

    ha_col_names.numeric <- names(groups.use.numeric)
    ha_col_hues.numeric <- scales::hue_pal()(length(ha_col_names.numeric))

    ha_cols.numeric  <- purrr::map2(groups.use[ha_col_names.numeric], ha_col_hues.numeric, numeric_col_fun)
  }

  ha_cols <- c(ha_cols.factor, ha_cols.numeric)

  column_ha = ComplexHeatmap::HeatmapAnnotation(df = groups.use, height = unit(group.bar.height, "points"), col = ha_cols)

  hm <- ComplexHeatmap::Heatmap(t(data), name = "log expression", top_annotation = column_ha,
                                cluster_columns = cluster_columns,
                                show_column_names = FALSE,
                                column_dend_height = unit(mm_col_dend, "mm"),
                                column_split = column_split,
                                column_title = NULL,
                                ...)

  return(hm)

}



#' Plot Transcript Composition
#'
#' plot the proportion of reads of a given gene map to each transcript
#'
#' @param seu
#' @param gene_symbol
#' @param group.by
#' @param standardize
#'
#' @return
#' @export
#'
#' @examples
#' plot_transcript_composition(human_gene_transcript_seu, "RXRG", group.by = "gene_snn_res.0.6")
#'
plot_transcript_composition <- function(seu, gene_symbol, group.by = "batch", standardize = FALSE, drop_zero = FALSE){


  transcripts <- annotables::grch38 %>%
    dplyr::filter(symbol == gene_symbol) %>%
    dplyr::left_join(annotables::grch38_tx2gene, by = "ensgene") %>%
    dplyr::pull(enstxp)

  metadata <- seu@meta.data
  metadata$sample_id <- NULL
  metadata <-
    metadata %>%
    tibble::rownames_to_column("sample_id") %>%
    dplyr::select(sample_id, group.by = {{group.by}})

  data <- GetAssayData(seu, assay = "transcript", slot = "data")[transcripts,]

  data <- t(expm1(as.matrix(data)))

  data <-
    data %>%
    as.data.frame() %>%
    tibble::rownames_to_column("sample_id") %>%
    tidyr::pivot_longer(cols = starts_with("ENST"),
                        names_to = "transcript",
                        values_to = "expression") %>%
    dplyr::left_join(metadata, by = "sample_id") %>%
    dplyr::mutate(group.by = as.factor(group.by),
                  transcript = as.factor(transcript))

  data <- dplyr::group_by(data, group.by, transcript)

  # drop zero values

  if(drop_zero){
    data <- dplyr::filter(data, expression != 0)
  }

  data <- dplyr::summarize(data, expression = mean(expression))

  position <- ifelse(standardize, "fill", "stack")

  p <- ggplot(
    data=data,
    aes(x = group.by, y= expression, fill = transcript)) +
    # stat_summary(fun = "mean", geom = "col") +
    geom_col(stat = "identity", position = position) +
    theme_minimal() +
    theme(axis.title.x = element_blank(),
          axis.text.x = element_text(
            angle=45, hjust = 1, vjust = 1, size=12)) +
    labs(title = paste("Mean expression by", group.by, "-", gene_symbol), subtitle = "data scaled by library size then ln transformed") +
    NULL

  return(list(plot = p, data = data))

}

#' Plot All Transcripts
#'
#' @param seu
#' @param transcripts
#'
#' @return
#' @export
#'
#' @examples
#'
#' processed_seu <- clustering_workflow(human_gene_transcript_seu)
#' transcripts_to_plot <- genes_to_transcripts("RXRG")
#' plot_all_transcripts(processed_seu, features = transcripts_to_plot)
#'
plot_all_transcripts <- function(seu, features, embedding = "umap"){

  transcript_cols <- as.data.frame(t(as.matrix(seu[["transcript"]][features,])))

  seu <- AddMetaData(seu, transcript_cols)

  pList <- purrr::map(features, ~plot_feature(seu,
                                              embedding = embedding,
                                              features = .x, return_plotly = FALSE))
  names(pList) <- features

  return(pList)

}
