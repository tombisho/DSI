#' Data assignment
#'
#' Assign a table or an expression result to a R symbol in the Datashield R session.
#'
#' @param conns \code{\link{DSConnection-class}} object or a list of \code{\link{DSConnection-class}}s.
#' @param symbol Name of the R symbol.
#' @param value Fully qualified name of a table reference in data repositories (see
#'   \code{\link{datashield.assign.table}} for more details) or a R expression with allowed assign
#'  functions calls.
#' @param variables List of variable names or Javascript expression that selects the variables of a table
#'   (ignored if value does not refere to a table). See javascript documentation:
#'   \url{http://opaldoc.obiba.org/en/latest/magma-user-guide/variable/}
#' @param missings If TRUE, missing values will be pushed from data repository to R, default is FALSE.
#'   Ignored if value is an R expression.
#' @param identifiers Name of the identifiers mapping to use when assigning entities to R (if supported
#'   by data repository).
#' @param id.name Name of the column that will contain the entity identifiers. If not specified, the identifiers
#'   will be the data frame row names. When specified this column can be used to perform joins between data frames.
#' @param async Whether the result of the call should be retrieved asynchronously (TRUE means that calls are parallelized over
#'   the connections, when the connection supports that feature, with an extra overhead of requests).
#'
#' @examples
#' \dontrun{
#' # assign a list of variables from table HOP
#' datashield.assign(conn, symbol="D", value="demo.HOP",
#'   variables=list("GENDER","LAB_GLUC"))
#'
#' # assign all the variables matching 'LAB' from table HOP
#' datashield.assign(conn, symbol="D", value="demo.HOP",
#'   variables="name().matches('LAB_')")
#' }
#' @export
datashield.assign <- function(conns, symbol, value, variables=NULL, missings=FALSE, identifiers=NULL, id.name=NULL, async=TRUE) {
  .clearLastErrors()
  if(is.language(value) || is.function(value)) {
    datashield.assign.expr(conns, symbol, value, async)
  } else {
    datashield.assign.table(conns, symbol, value, variables, missings, identifiers, id.name, async)
  }
}

#' Table assignment
#'
#' Assign a table to a R symbol in the Datashield R session.
#'
#' @param conns \code{\link{DSConnection-class}} object or a list of \code{\link{DSConnection-class}}s.
#' @param symbol Name of the R symbol.
#' @param table Fully qualified name of a table in the data repository (can be a vector or must be
#'   the same in each data repository); or a named list of fully qualified table names (one per server
#'   name); or a data frame with 'server' and 'table' columns (such as the one that is used in
#'   \code{\link{datashield.login}})
#' @param variables List of variable names or Javascript expression that selects the variables of
#'   a table. See javascript documentation:
#'   \url{http://opaldoc.obiba.org/en/latest/magma-user-guide/variable/}
#' @param missings If TRUE, missing values will be pushed from data repository to R, default is FALSE.
#'   Ignored if value is an R expression.
#' @param identifiers Name of the identifiers mapping to use when assigning entities to R (if supported
#'   by the data repository).
#' @param id.name Name of the column that will contain the entity identifiers. If not specified, the identifiers
#'   will be the data frame row names. When specified this column can be used to perform joins between data frames.
#' @param async Whether the result of the call should be retrieved asynchronously. When TRUE (default) the calls are parallelized over
#'   the connections, when the connection supports that feature, with an extra overhead of requests.
#'
#' @examples
#' \dontrun{
#' # assign a list of variables from table HOP
#' datashield.assign.table(conn, symbol="D", table="demo.HOP",
#'   variables=list("GENDER","LAB_GLUC"))
#'
#' # assign all the variables matching 'LAB' from table HOP
#' datashield.assign.table(conn, symbol="D", table="demo.HOP",
#'   variables="name().matches('LAB_')")
#'
#' # assign the tables that are defined in the logindata ('server' and 'table' columns are
#' # expected) data frame that is used in datashield.login() function. Connections names
#' # and server names must match.
#' datashield.assign.table(conns, "D", logindata)
#'
#' # assign the tables that are defined in the provided named list. Connections names
#' # and server names must match.
#' datashield.assign.table(conns, "D", list(server1="datashield.CNSIM1", server2="datashield.CNSIM2"))
#' }
#' @export
datashield.assign.table <- function(conns, symbol, table, variables=NULL, missings=FALSE, identifiers=NULL, id.name=NULL, async=TRUE) {
  .clearLastErrors()
  if (is.null(table) || length(table) == 0) {
    stop("Not a valid table name", call.=FALSE)
  }

  # prepare tables as a named list
  tables <- .asNamedListOfTables(conns, table)

  if (is.list(conns)) {
    results <- list()
    async <- lapply(conns, function(conn) { ifelse(async, dsIsAsync(conn)$assignTable, FALSE) })
    pb <- .newProgress(total = 1 + length(conns))
    # async first
    for (n in names(conns)) {
      if(async[[n]]) {
        tryCatch({
          results[[n]] <- dsAssignTable(conns[[n]], symbol, tables[[n]], variables, missings, identifiers, id.name, async=TRUE)
        }, error = function(e) {
          .appendError(n, e$message)
        })
      }
    }
    # not async (blocking calls)
    for (n in names(conns)) {
      if(!async[[n]]) {
        tryCatch({
          .tickProgress(pb, tokens = list(what = paste0("Assigning ", conns[[n]]@name, " (", symbol, " <- `", tables[[n]], "`)")))
          results[[n]] <- dsAssignTable(conns[[n]], symbol, tables[[n]], variables, missings, identifiers, id.name, async=FALSE)
        }, error = function(e) {
          .appendError(n, e$message)
        })
      }
    }
    lapply(names(conns), function(n) {
      if (!.hasLastErrors(n)) {
        tryCatch({
          if(async[[n]]) .tickProgress(pb, tokens = list(what = paste0("Assigning table ", conns[[n]]@name, " (", symbol, " <- `", tables[[n]], "`)")))
          dsGetInfo(results[[n]])
          dsFetch(results[[n]])
        }, error = function(e) {
          .appendError(n, e$message)
        })
      }
    })
    ignore <- .tickProgress(pb, tokens = list(what = paste0("Assigned all table (", symbol, " <- ...)")))
  } else {
    tryCatch({
      res <- dsAssignTable(conns, symbol, tables[[conns@name]], variables, missings, identifiers, id.name)
      dsGetInfo(res)
      ignore <- dsFetch(res)
    }, error = function(e) {
      .appendError(conns@name, e$message)
    })
  }
  .checkLastErrors()
  invisible(NULL)
}


#' Resource assignment
#'
#' Assign a resource object of class 'ResourceClient' to a R symbol in the Datashield R session.
#'
#' @param conns \code{\link{DSConnection-class}} object or a list of \code{\link{DSConnection-class}}s.
#' @param symbol Name of the R symbol.
#' @param resource Fully qualified name of a resource reference in the data repository (can be a vector or must be
#'   the same in each data repository); or a named list of fully qualified resource names (one per server
#'   name); or a data frame with 'server' and 'resource' columns (such as the one that is used in
#'   \code{\link{datashield.login}})
#' @param async Whether the result of the call should be retrieved asynchronously. When TRUE (default) the calls are parallelized over
#'   the connections, when the connection supports that feature, with an extra overhead of requests.
#'
#' @examples
#' \dontrun{
#' # assign a resource HOP
#' datashield.assign.resource(conn, symbol="rsrc", resource="demo.HOP")
#'
#' # assign the tables that are defined in the logindata ('server' and 'resource' columns are
#' # expected) data frame that is used in datashield.login() function. Connections names
#' # and server names must match.
#' datashield.assign.resource(conns, "rsrc", logindata)
#'
#' # assign the resources that are defined in the provided named list. Connections names
#' # and server names must match.
#' datashield.assign.resource(conns, "rsrc",
#'   list(server1="datashield.CNSIM1", server2="datashield.CNSIM2"))
#' }
#' @export
datashield.assign.resource <- function(conns, symbol, resource, async=TRUE) {
  .clearLastErrors()
  if (is.null(resource) || length(resource) == 0) {
    stop("Not a valid resource name", call.=FALSE)
  }

  # prepare resources as a named list
  resources <- .asNamedListOfResources(conns, resource)

  if (is.list(conns)) {
    results <- list()
    async <- lapply(conns, function(conn) { ifelse(async, dsIsAsync(conn)$assignResource, FALSE) })
    pb <- .newProgress(total = 1 + length(conns))
    # async first
    for (n in names(conns)) {
      if(async[[n]]) {
        tryCatch({
          results[[n]] <- dsAssignResource(conns[[n]], symbol, resources[[n]], async=TRUE)
        }, error = function(e) {
          .appendError(n, e$message)
        })
      }
    }
    # not async (blocking calls)
    for (n in names(conns)) {
      if(!async[[n]]) {
        tryCatch({
          .tickProgress(pb, tokens = list(what = paste0("Assigning ", conns[[n]]@name, " (", symbol, " <- `", resources[[n]], "`)")))
          results[[n]] <- dsAssignResource(conns[[n]], symbol, resources[[n]], async=FALSE)
        }, error = function(e) {
          .appendError(n, e$message)
        })
      }
    }
    lapply(names(conns), function(n) {
      if (!.hasLastErrors(n)) {
        tryCatch({
          if(async[[n]]) .tickProgress(pb, tokens = list(what = paste0("Assigning resource ", conns[[n]]@name, " (", symbol, " <- `", resources[[n]], "`)")))
          dsGetInfo(results[[n]])
          dsFetch(results[[n]])
        }, error = function(e) {
          .appendError(n, e$message)
        })
      }
    })
    ignore <- .tickProgress(pb, tokens = list(what = paste0("Assigned all resource (", symbol, " <- ...)")))
  } else {
    tryCatch({
      res <- dsAssignResource(conns, symbol, resources[[conns@name]])
      dsGetInfo(res)
      ignore <- dsFetch(res)
    }, error = function(e) {
      .appendError(conns@name, e$message)
    })
  }
  .checkLastErrors()
  invisible(NULL)
}

#' Expression result assignment
#'
#' Assign the result of the execution of an expression to a R symbol in the Datashield R session.
#'
#' @param conns \code{\link{DSConnection-class}} object or a list of \code{\link{DSConnection-class}}s.
#' @param symbol Name of the R symbol.
#' @param expr R expression with allowed assign functions calls.
#' @param async Whether the result of the call should be retrieved asynchronously. When TRUE (default) the calls are parallelized over
#'   the connections, when the connection supports that feature, with an extra overhead of requests.
#'
#' @examples
#' \dontrun{
#' # assign a G symbol
#' datashield.assign.expr(conns, symbol = "G", expr = quote(as.numeric(D$GENDER)))
#' }
#' @export
datashield.assign.expr <- function(conns, symbol, expr, async=TRUE) {
  .clearLastErrors()
  if (is.list(conns)) {
    results <- list()
    async <- lapply(conns, function(conn) { ifelse(async, dsIsAsync(conn)$assignExpr, FALSE) })
    pb <- .newProgress(total = 1 + length(conns))
    # async first
    for (n in names(conns)) {
      if(async[[n]]) {
        tryCatch({
          results[[n]] <- dsAssignExpr(conns[[n]], symbol, expr, async=TRUE)
        }, error = function(e) {
          .appendError(n, e$message)
        })
      }
    }
    dexpr <- .deparse(expr)
    # not async (blocking calls)
    for (n in names(conns)) {
      if(!async[[n]]) {
        tryCatch({
          .tickProgress(pb, tokens = list(what = paste0("Assigning expr. ", conns[[n]]@name, " (", symbol, " <- ", dexpr, ")")))
          results[[n]] <- dsAssignExpr(conns[[n]], symbol, expr, async=FALSE)
        }, error = function(e) {
          .appendError(n, e$message)
        })
      }
    }
    lapply(names(conns), function(n) {
      tryCatch({
        if (!.hasLastErrors(n)) {
          if(async[[n]]) .tickProgress(pb, tokens = list(what = paste0("Assigning ", conns[[n]]@name, " (", symbol, " <- ", dexpr, ")")))
          dsFetch(results[[n]])
        }
      }, error = function(e) {
        .appendError(n, e$message)
      })
    })
    ignore <- .tickProgress(pb, tokens = list(what = paste0("Assigned expr. (", symbol, " <- ", dexpr, ")")))
  } else {
    tryCatch({
      res <- dsAssignExpr(conns, symbol, expr)
      ignore <- dsFetch(res)
    }, error = function(e) {
      .appendError(conns@name, e$message)
    })
  }
  .checkLastErrors()
  invisible(NULL)
}
