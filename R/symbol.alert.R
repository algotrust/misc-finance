#!/usr/bin/env Rscript
# (c) Copyright 2014 mkfs <https://github.com/mkfs>
# R script for daily stock-symbol-alert cron job.
# Usage:
#   R --vanilla -e "source('/home/repo/misc-finance/R/symbol.alert.R'); symbol.alert('/home/me/symbol.alert.dat', 'me@gmail.com')"
# Note that input file is tab-delimited with the following columns:
#   Symbol	BuyAt	SellAt

library(quantmod)
library(sendmailR)

# Generate a dataframe containing the Symbol, BuyAt, SellAt, and quote columns.
# The first three are retrieved from a tab-delimited input file (i.e. of stock
# symbols to monitor); the quote columns are retrieved from Yahoo Finance.
symbol.retrieve.for.file <- function(filename, header=FALSE, sep = "\t") {
	watch.df <- read.delim(filename, header=header, sep=sep)
	colnames(watch.df) <- c('Symbol', 'BuyAt', 'SellAt')

	quote.df <- getQuote(paste(watch.df$Symbol, collapse=';'))
	quote.df$Symbol <- rownames(quote.df)

	merge(watch.df, quote.df)
}

# Check if Last price of symbol is <= BuyAt or >= SellAt
# Note that if a symbol's SellAt is zero, it is treated as infinite
# (i.e. "never sell")
symbol.check.last <- function(filename, header=FALSE, sep = "\t") {
	df <- symbol.retrieve.for.file(filename, header, sep)
	df[(df$Last <= df$BuyAt) | (df$SellAt > 0 & df$Last >= df$SellAt), ]
}

# Settings for email alerts
symbol.alert.from <- "r.misc.finance@nospam.org"
symbol.alert.subject <- "[R-misc-finance] Stock Symbol Alert"
symbol.alert.server <- 'ASPMX.L.GOOGLE.COM'	# SMTP server: gmail

# Generate a report for dataframe of stock alerts. This just captures the
# result of printing a dataframe.
symbol.alert.report <- function(df) {
	# Note: format() could be use, but that will not strip row names
	capture.output(print(df, row.names=FALSE))
}

# Check if the symbols in the input file have exceeded their BuyAt or SellAt
# thresholds. If one or more symbols do so, they are emailed to the provided
# address or printed to STDOUT (if not email is provided).
# The verbose flag can be used to debug sendmail() problems.
symbol.alert <- function(filename, email=NULL, verbose=FALSE) {
	df <- symbol.check.last(filename)

	if (nrow(df) == 0) {
		return(df)
	}

	if ( is.null(email) ) {
		print(df)
	} else {
		sendmail(paste('<', symbol.alert.from, '>', sep=''), 
			 paste('<', email, '>', sep=''),
			 symbol.alert.subject,
			 symbol.alert.report(df),
			 control=list(smtpServer=symbol.alert.server), 
			 verbose=verbose)
	}

	return(df)
}

# As with symbol.alert, but use Gmail via Curl to send email.
# username doubles as both Gmail sign-in and From: email address.
# If to.email is blank, username will be used.
# Note: this requires the Curl command-line utility be installed and in PATH.
symbol.alert.gmail <- function(filename, username, password, to.email=NULL,
                               verbose=FALSE) {
  df <- symbol.check.last(filename)
  
  if (nrow(df) == 0) {
    return(df)
  }
  
  email.data <- paste( paste('Subject:', symbol.alert.subject), '',
                       paste(symbol.alert.report(df), collapse="\n"), '', 
                       sep="\r\n" )
  
  if ( is.null(to.email) ) to.email <- username
  
  # Not the best validation: caller beware
  username <- gsub('([^\\])(\\\\)*"', '\\1"', username)
  password <- gsub('([^\\])(\\\\)*"', '\\1"', password)
  to.email <- gsub('([^\\])(\\\\)*"', '\\1"', to.email)

  cmd <- paste('curl -n --ssl-reqd --mail-from "<',
               username,
               '>" --mail-rcpt "<',
               to.email,
               '>" --url ',
               'smtp://smtp.gmail.com:587',
               ' --user "', username, ':', password, 
               '" -T -', sep='')
  
  system(cmd, input=email.data, show.output.on.console=verbose)
}
