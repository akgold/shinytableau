config_ui_template <- function() {
  ns <- shiny::NS(c("shinytableau", "config"))

  shiny::fillPage(theme = shinytableau_theme(),
    shiny::fillCol(flex = c(1, NA),
      miniUI::miniContentPanel(
        shiny::uiOutput(ns("ui"))
      ),
      shiny::uiOutput(class = "button-bar", ns("footer_ui"))
    )
  )
}

tableau_config_server <- function(ui_func, server_func) {
  force(ui_func)
  force(server_func)

  ns <- shiny::NS(c("shinytableau", "config"))

  function(input, output, session) {
    shiny::isolate({
      bookmark_url <- tableau_setting("shinytableau_ui_state")
      tryCatch(
        {
          if (!is.null(bookmark_url)) {
            parts <- strsplit(bookmark_url, "?", fixed = TRUE)[[1]]
            if (length(parts) == 2) {
              qs <- shiny::parseQueryString(parts[[2]])
              qs[["_inputs_"]] <- NULL
              qs <- lapply(qs, jsonlite::parse_json, simplifyVector = TRUE)
              restore_inputs(!!!qs)
            }
          }
        },
        error = function(err) {
          shiny::printError(err)
          shiny::showNotification(
            "An error occurred while loading your current configuration. Please choose new settings and Apply.",
            type = "error"
          )
        }
      )
    })

    # The use of moduleServer here is a trick to let us independently specify
    # bookmark excludes that cannot alter or be altered by other calls to
    # setBookmarkExclude().
    shiny::moduleServer(NULL, function(input, output, session) {
      shiny::observe({
        input_names <- names(input)
        shiny::setBookmarkExclude(c(
          grep("^shinytableau-setting-", input_names, value = TRUE),
          grep("^shinytableau-config-", input_names, value = TRUE),
          "shinytableau-settings",
          "shinytableau-schema"
        ))
      })
    })

    output[[ns("ui")]] <- shiny::renderUI({
      shiny::isolate({
        ui_func(session$request)
      })
    })

    output[[ns("footer_ui")]] <- shiny::renderUI({
      shiny::tagList(
        htmltools::div(class = "button-bar-panel button-bar-left",
          shiny::actionButton(ns("apply"), "Apply")
        ),
        htmltools::div(class = "button-bar-panel button-bar-right",
          shiny::actionButton(ns("cancel"), "Cancel"),
          shiny::actionButton(ns("ok"), "OK", class = "btn-primary")
        )
      )
    })

    iv <- shinyvalidate::InputValidator$new()
    args <- list(input = input, output = output, session = session, iv = iv)
    if (!"..." %in% names(formals(server_func))) {
      args <- args[names(args) %in% names(formals(server_func))]
    }
    result <- rlang::exec(server_func, !!!args)

    if (is.function(result)) {
      save_settings <- result
    } else if (is.list(result)) {
      save_settings <- result$save_settings
    }

    if (is.null(result)) {
      save_settings <- function() {}
    } else if (!is.function(result)) {
      stop("`config_server` returned an unexpected value. It should return a ",
        "function that takes no arguments, whose purpose is to save settings. ",
        "See the Details section of ?tableau_extension.",
        call. = FALSE
      )
    }

    shiny::onBookmarked(function(url) {
      # print(url)
      update_tableau_settings_async("shinytableau_ui_state" = url, add. = TRUE)
    })

    apply_changes <- function() {
      if (iv$is_valid()) {
        promises::promise_resolve(save_settings()) %...>% {
          session$doBookmark()
        } %...>% {
          TRUE
        }
      } else {
        iv$enable()
        promises::promise_resolve(FALSE)
      }
    }

    catch_apply_error <- function(err) {
      shiny::printError(err)
      shiny::showNotification(
        htmltools::tagList(
          htmltools::strong("An error occurred while saving changes:"),
          htmltools::tags$br(),
          htmltools::tags$br(),
          as.character(conditionMessage(err))
        ),
        type = "error"
      )
    }

    shiny::observeEvent(input[[ns("ok")]], {
      apply_changes() %...>% {
        if (.) {
          tableau_close_dialog()
        }
      } %...!% catch_apply_error
    })

    shiny::observeEvent(input[[ns("cancel")]], {
      tableau_close_dialog()
    })

    shiny::observeEvent(input[[ns("apply")]], {
      apply_changes() %...!% catch_apply_error
    })
  }
}


# Config server must provide:
# - save_settings callback
