#' Functio to write out a bash file calling R for slurm
#' @param njobs Integer, number of jobs to specify.
#' @param Rscript_flags Character specifying flags to pass to Rscript.
#' @param ... List of arguments passed to `SBATCH` (see details).
#'
#' @details
#' The `...` argument allows passing options via `SBATCH` in the script, for
#' example, if the user wants to use account `user1` and require a minimum of
#' 2 CPUS per node, the user can pass the argument:
#'
#' ```
#' list(account="user1", mincpus=2)
#' ```
#'
#' Which will translate into
#'
#' ```
#' #SBATCH --account="user1"
#' #SBATCH --mincpus=2
#' ```
#'
#' In the bash file. Available options can be found
#' https://slurm.schedmd.com/sbatch.html#OPTIONS.
#' @noRd
new_bash <- function(njobs = 2) {

  # Creating the new environment -----------------------------------------------
  env <- new.env(parent = emptyenv())
  env$dat <- "#!/bin/sh"

  # Appending data -------------------------------------------------------------
  env$append <- function(x) {
    if (length(x) > 1)
      return(invisible(sapply(x, env$append)))

    env$dat <- c(env$dat, x)

    invisible()
  }

  # Adding SBATCH options ------------------------------------------------------
  env$add_SBATCH <- function(x) {

    # Adding whatever options are there
    if (length(x))
      env$append(paste("#SBATCH", parse_flags(x)))

    invisible()
  }

  # Finalizing the script ------------------------------------------------------
  env$finalize <- function(Rscript_flags) {

    Rscript_flags <- parse_flags(Rscript_flags)

    env$dat <- c(
      env$dat,
      sprintf("%s/bin/Rscript %s %s", R.home(), Rscript_flags, snames("r"))
    )

    invisible()
  }

  env$write <- function() {
    writeLines(env$dat, snames("sh"))
  }


  # This bit is key (we need this info to properly track the job) --------------
  env$add_SBATCH(
    list(
      `job-name` = opts_sluRm$get_job_name(),
      output     = snames("out"),
      array      = sprintf("1-%i", njobs)
    )
  )


  env

}
