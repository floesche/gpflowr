# voodoo to mimic Python behaviour in R6 classes:
# enable R6 classes to define their own dollar behaviour via methods,  provide a
# `with` functionsimilar to Python's, and provide a functor to mimic the
# @property decorator

has <- function (x, name, which = c('element', 'attribute')) {
  # test whether object `x` has either an element or an attribute `name` (a
  # string)
  expr <- switch(match.arg(which),
                 element = parse(text = "x[[name]]"),
                 attribute = parse(text = "x[[name]]"))

  # return null if the object is missing, or the expression errors
  result <- tryCatch(eval(expr),
                     error = function (cond) NULL)

  !is.null(result)

}


# overload the dollar for R6 objects, so that they can define their own dollar
# methods as member functions. If they don't provide one, default to standard
# subsetting/insertion

`$.R6` <- function (x, i) {
  # dollar extraction
  if (has(x, '$'))
    return (x[['$']](x, i))
  else
    return (x[[i]])
}

`$<-.R6` <- function (x, i, value) {
  # dollar insertion
  if (has(x, '$'))
    return (x[['$']](x, i, value))
  else {
    x[[i]] <- value
    return (x)
  }
}

with.R6 <- function (data, expr, as = NULL, ...) {
  # define a simple `with` syntax for R6 objects to safely execute modified
  # code, then clean up. This leans heavily on the `with` generic in the
  # tensorflow R API, but: 1) requires `as` and 2) acts on and returns R
  # objects, rather than interfacing with the python context manager. The `%as%`
  # operator from the tensorflow R API can be used to generate `data`, in which
  # case, it defines `as`, and the environment in data. If that syntax isn't
  # used, the `as` argument must be used instead, and `expr` is executed in the
  # parent environment.

  # get the as argument
  if (!missing(as)) {
    as <- deparse(substitute(as))
    as <- gsub("\"", "", as)
  }
  else {
    as <- attr(data, "as")
  }

  if (is.null(as)) {
    stop ("'as' must be provided, either via the argument 'as' or the '%as%' syntax")
  }

  # find the environment to execute in (parent if the %as% syntax wasn't used)
  envir <- attr(data, "as_envir")
  if (is.null(envir)) {
    envir <- parent.frame()
  }

  # set up object to restore `as``
  asRestore <- NULL
  if (exists(as, envir = envir))
    asRestore <- get(as, envir = envir)

  # on leaving this function, rewrite `as` with the restore point
  on.exit({
    remove(list = as, envir = envir)
    if (!is.null(asRestore))
      assign(as, asRestore, envir = envir)
  })

  # write/overwite `as` in the target environment and execute the expression
  assign(as, data, envir = envir)
  force(expr)

}

# Python uses the @property decorator to flag values and assign them
# getters/setters. In R6, this is better ahndled via active classes.
# E.g.:
#
# foo <- R6Class('foo',
#                public = list(x = NULL),
#                active = list(
#                  apples = function (value) {
#                    if (missing(value))
#                      return (self$x)
#                    else
#                      self$x <- value
#                  }
#                ))
#
# This is a bit clunky, and often we don't want to assign any more complex
# getter/setters than this. Therefore, we can define a default method here, to
# tidy up later code. E.g.
#
# foo <- R6Class('foo',
#                public = list(x = NULL),
#                active = list(
#                  apples = property('x')
#                ))

# functor to return a default active function
property <- function (name, public = TRUE) {

  obj <- paste(ifelse(public,
                      'self',
                      'private'),
               name,
               sep = '$')

  fun_text <- sprintf('fun <- function (value) {
                      if (missing(value)) { return (%s) }
                      else {%s <- value}}', obj, obj)

  fun <- eval(parse(text = fun_text))
  fun

  }