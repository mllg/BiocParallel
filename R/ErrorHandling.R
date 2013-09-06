.LastError = setRefClass("LastError",
  fields = list(
    results = "list",      # partial results
    is.error = "logical"), # flags successfull/errorneous termination
  methods = list(
    initialize = function() {
      reset()
    },
    show = function() {
      if (!length(results)) {
        message("No partial results saved")
      } else {
        n.errors = sum(is.error)
        msg = sprintf("%i/%i partial results stored.", length(is.error) - n.errors, length(is.error))
        if (n.errors > 0L) {
          n.print = min(n.errors, 10L)
          msg = paste(msg, sprintf("First %i error messages:", n.print))
          msg = c(msg, vapply(head(which(is.error), n.print),
                              function(i) sprintf("[%i]: %s", i, as.character(results[[i]])),
                              character(1L)))
          message(paste(msg, collapse = "\n"))
        }
      }
    },
    store = function(results, is.error, throw.error = FALSE) {
      if (any(is.error)) {
        .self$results = replace(results, is.error, lapply(results[is.error], .convertToSimpleError))
        .self$is.error = is.error
        if (throw.error) {
          msg = c("Errors occurred during execution. First error message:",
                  as.character(results[is.error][[1L]]),
                  "For more information, use getLastError().",
                  "To resume calculation, re-call the function and set the argument 'resume' to TRUE.")
          stop(paste(msg, collapse = "\n"))
        }
      } else {
        reset()
      }
    },
    reset = function() {
      .self$results = list()
      .self$is.error = NA
      invisible(TRUE)
    }
  )
)
LastError = .LastError()

getLastError = function() {
  getFromNamespace("LastError", "BiocParallel")
}

.convertToSimpleError = function(x) {
  x = as.character(x)
  simpleError(x)
}

.try = function(expr, debug=FALSE) {
  if (!debug)
    return(try(expr))
  handler_warning = function(w) {
    cache.warnings <<- c(cache.warnings, w)
    invokeRestart("muffleWarning")
  }

  handler_error = function(e) {
    catched.error <<- TRUE
    dump.frames(".lastDump")
    dumped = get(".lastDump", envir = .GlobalEnv)
    rm(".lastDump", envir = .GlobalEnv)
    call = sapply(sys.calls(), deparse)
    invokeRestart("abort", e, call, dumped)
  }

  handler_abort = function(e, call, dumped) {
    list(value = e, call = call, dump = dumped)
  }

  catched.error = FALSE
  cache.warnings = list()
  ret = setNames(vector("list", 5L), c("value", "warnings", "error", "call", "dump"))

  x = withRestarts(withCallingHandlers(expr, warning = handler_warning, error = handler_error), abort = handler_abort)
  if (catched.error) {
    ret[names(x)] = x
    class(ret) = "try-error"
  } else {
    ret[["value"]] = x
  }
  ret[["warnings"]] = cache.warnings
  ret
}


.resume = function(FUN, ..., MoreArgs, SIMPLIFY, USE.NAMES, BPPARAM) {
  message("Resuming previous calculation... ")
  if (length(LastError$results) != length(list(...)[[1L]]))
    stop("Cannot resume: Length mismatch in arguments")
  is.error = LastError$is.error
  results = LastError$results
  pars = c(list(FUN=FUN, MoreArgs=MoreArgs, SIMPLIFY=SIMPLIFY,
                USE.NAMES=USE.NAMES, resume=FALSE, BPPARAM=BPPARAM),
           lapply(list(...), "[", LastError$is.error))
  next.try = do.call(bpmapply, pars)

  if (inherits(next.try, "try-error")) {
    LastError$results = replace(results, is.error, LastError$results)
    LastError$is.error = replace(is.error, is.error, LastError$is.error)
    stop(as.character(next.try))
  } else {
    LastError$reset()
    return(replace(results, is.error, next.try))
  }
}