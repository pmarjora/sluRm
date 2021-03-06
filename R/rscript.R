#' List loaded packages together with `lib.loc`
#' @noRd
list_loaded_pkgs <- function() {

  # Getting the name spaces
  pkgs <- rev(sessionInfo()$otherPkgs)

  # Session

  structure(
    lapply(pkgs, function(p) {
      gsub(sprintf("/%s/.+", p$Package), "", attr(p, "file"))
    }),
    names = names(pkgs),
    class = "sluRm_loaded_packages"
  )

}

#' Creates an R script
#' @noRd
#' @param pkgs A named list of R packages to load.
rscript_header <- function(pkgs, seeds = NULL) {

  # For testing purposes, the instalation of the package is somewhere else
  if ("sluRm" %in% names(pkgs))
    pkgs[names(pkgs) == "sluRm"] <- NULL

  sprintf("library(%s, lib.loc = \"%s\")", names(pkgs), unlist(pkgs))

}

#' General purpose function to write R scripts
#'
#' This function will create an object of class `sluRm_rscript` that can be used
#' to write the R component in a batch job.
#' @param pkgs A named list with packages to be included. Each element of the list
#' must be a path to the R library, while the names of the list are the names of
#' the R packages to be loaded.
#'
#' @return An environment of class `sluRm_rscript`. This has the following accesible
#' components:
#'
#' - `add_rds` Add rds files to be loaded in each job.", `x` is a named list
#'   with the objects that should be loaded in the jobs. If `index = TRUE` the
#'   function assumes that the user will be accessing a particular subset of `x`
#'   during the job, which is accessed according to `INDICES[[ARRAY_ID]]`. The
#'   option `compress` is passed to [saveRDS].
#'
#'   One important side effect is that when this function is called, the object
#'   will be saved in the current job directory, this is `opts_sluRm$get_chdir()`.
#'
#' - `append` Adds a line to the R script. Its only argument, `x` is a character
#'   vector that will be added to the R script.
#'
#' - `rscript` A character vector. This is the actual R script that will be written
#'   at the end.
#'
#' - `finalize` Adds the final line of the R script. This function receives a
#'   character scalar `x` which is used as the name of the object to be saved.
#'   If missing, the function will save a NULL object. The `compress` argument
#'   is passed to [saveRDS].
#'
#' - `set_seed` Adds a vector of seeds to be used across the jobs. This vector
#'   of seeds should be of length `njobs`. The other two parameters of the
#'   function are passed to [set.seed].
#'
#' - `write` Finalizes the process by writing the R script in the corresponding
#'   folder to be used with Slurm.
#'
#' @export
new_rscript <- function(pkgs = list_loaded_pkgs()) {

  # Creating the environment
  env <- new.env(parent = emptyenv())

  # The first statement is the task id number
  env$rscript <- rscript_header(pkgs)
  env$rscript <- paste0("Slurm_env <- ", paste(deparse(Slurm_env), collapse="\n"))
  env$rscript <- c(
    env$rscript,
    sprintf("%-16s <- as.integer(Slurm_env(\"SLURM_ARRAY_TASK_ID\"))", "ARRAY_ID")
    )

  # Function to append a line
  env$append <- function(x) {

    # In case of multiple statements
    if (length(x) > 1)
      return(invisible(sapply(x, env$append)))

    env$rscript <- c(env$rscript, x)
    invisible()
  }

  # Function to finalize the Rscript
  env$finalize <- function(x, compress = TRUE) {


    env$append(
      sprintf(
        "saveRDS(%s, %s, compress = %s)",
        if (missing(x)) "NULL" else x,
        paste0("sprintf(\"", snames("rds"), "\", ARRAY_ID)"),
        ifelse(compress, "TRUE", "FALSE")
    ))

    invisible()
  }

  env$add_rds <- function(x, index = FALSE, compress = TRUE) {

    # Checking
    if (!is.list(x))
      stop("`x` must be a list.", call. = FALSE)
    if (!length(names(x)))
      stop("`x` must be a named list.", call. = FALSE)

    # Saving the objects
    save_objects(x, compress = compress)

    for (i in seq_along(x)) {
      # Writing the line
      line <- sprintf(
        "%-16s <- readRDS(\"%s/%s/%1$s.rds\")",
        names(x)[i],
        opts_sluRm$get_chdir(),
        opts_sluRm$get_job_name()
      )

      if (index)
        line <- paste0(line, "[INDICES[[ARRAY_ID]]]")

      env$rscript  <- c(env$rscript, line)
      env$robjects <- c(env$robjects, names(x)[i])
    }

    invisible()

  }

  env$set_seed <- function(x, kind = NULL, normal.kind = NULL) {

    # Reading the seeds
    env$add_rds(list(seeds = x), index = FALSE)
    line <- sprintf("set.seed(seeds[ARRAY_ID], kind = %s, normal.kind = %s)",
                    ifelse(length(kind), kind, "NULL"),
                    ifelse(length(normal.kind), normal.kind, "NULL"))

    # Don't want the seed to be kept in the list
    env$robjects <- env$robjects[1L:(length(env$robjects) - 1L)]
    env$rscript <- c(env$rscript, line)

    invisible()

  }

  env$write <- function() {
    writeLines(env$rscript, snames("r"))
  }

  structure(env, class = "sluRm_rscript")

}


print.sluRm_rscript <- function(x, ...) {

  cat(x$dat, sep = "\n")

  invisible(x)

}

