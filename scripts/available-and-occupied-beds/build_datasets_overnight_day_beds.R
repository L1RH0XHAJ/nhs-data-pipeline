########### CLEANING OVERNIGHT AND DAY BEDS NHS CAPACITY DATA ##################

# PACKAGES AND WORKING DIRECTORY ------------------------------------------------
library(sf)
library(plyr)
library(dplyr)
library(tidyverse)
library(sjmisc)
library(foreign)
library(parallel)
library(vroom)
library(MatchIt)
library(rlist)
library(stringr)
library(data.table)
library(lubridate)
library(operator.tools)
library(attempt)
library(zoo)
library(openxlsx)
library(readxl)
library(ggplot2)
library(readODS)
library(fastDummies)
library(httr)
library(haven)
library(fixest)
library(janitor)
library(cellranger)
library(scales)
library(devtools)
library(sp)
library(sf)
library(did)
library(ggpubr)
library(modelsummary)

setwd("/Users/claraschreiner/Desktop/nhs-data-pipeline")

# FUNCTION FOR BED EXTRACTION (DAY AND OVERNIGHT) 2000 - 2010 ------------------
bed_data_extraction_0010 <- function(filepath) {
  filenames_all <- list.files(filepath, 
                              recursive=TRUE, full.names=TRUE)
  
  filenames_0010 <- filenames_all[grepl("20(0[0-9])", filenames_all)]
  filenames_0010 <- filenames_0010[grepl("NHS_Organisations_in_England", filenames_0010)]
  
  #extracting data (early 2010 data in different format)
  beds_list <- lapply(filenames_0010, 
                      function(x) if (grepl("2000-01", x) | grepl("2001-02", x)) {
                        data.table(fname = str_extract(x, "[^/]+$"), 
                                   read_excel(path = x, sheet = 1, skip = 3, na = c("-", "")))
                      }
                      else 
                      {
                        data.table(fname = str_extract(x, "[^/]+$"), 
                                   read_excel(path = x, sheet = 1, skip = 4, na = c("-", "")))
                      }
  )
  
  beds_list
}


# FUNCTION FOR OVERNIGHT BED CLEANING 2000 - 2010 -------------------------------
overnight_bed_data_cleaning_0010 <- function(beds_list) {
  
  #clean variable names
  beds_list <- lapply(beds_list, 
                      function(x)
                        setnames(x, names(x), make_clean_names(names(x))))
  
  #for linkage later, setting orgID to org_code
  beds_list <- lapply(beds_list, 
                      function(x)
                        setnames(x, c("org_id", "name"), c("org_code", "org_name")))
  
  #setting variable names
  beds_list <- lapply(beds_list, 
                      function(x) { 
                        if ("2000-01" %in% x$year) {
                          setnames(x, c("available_all_sectors", "occupied_all_sectors"), c("total_on_beds_available", "total_on_beds_occupied"))
                          setnames(x, c("available_general_acute", "occupied_general_acute"), c("general_acute_on_beds_available", "general_acute_on_beds_occupied"))
                          setnames(x, c("available_learning_disability", "occupied_learning_disability"), c("learn_disabil_on_beds_available", "learn_disabil_on_beds_occupied"))
                          setnames(x, c("available_maternity", "occupied_maternity"), c("maternity_on_beds_available", "maternity_on_beds_occupied"))
                          setnames(x, c("available_mental_illness", "occupied_mental_illness"), c("mental_illness_on_beds_available", "mental_illness_on_beds_occupied"))
                        }
                        else {
                          setnames(x, c("total_5", "total_14", "total_23"), c("total_on_beds_available", "total_on_beds_occupied", "total_on_beds_percent_occupied"))
                          setnames(x, c("general_acute_6", "general_acute_15", "general_acute_24"), c("general_acute_on_beds_available", "general_acute_on_beds_occupied", "general_acute_on_beds_percent_occupied"))
                          setnames(x, c("learning_disability_11", "learning_disability_20", "learning_disability_29"), c("learn_disabil_on_beds_available", "learn_disabil_on_beds_occupied", "learn_disabil_on_beds_percent_occupied"))
                          setnames(x, c("maternity_12", "maternity_21", "maternity_30"), c("maternity_on_beds_available", "maternity_on_beds_occupied", "maternity_on_beds_percent_occupied"))
                          setnames(x, c("mental_illness_10", "mental_illness_19", "mental_illness_28"), c("mental_illness_on_beds_available", "mental_illness_on_beds_occupied", "mental_illness_on_beds_percent_occupied"))
                        }
                      }
  )
  
  #making sure all trust names are capitalised for easier merging later on 
  beds_list <- lapply(beds_list, 
                      function(x) {
                        x$org_name <- toupper(x$org_name)
                        x
                      }
  )
  
  #dealing with missing rows 
  beds_list <- lapply(beds_list, 
                      function(x)
                        x <- x |> filter(!is.na(org_name)))
  
  #only selecting all common variables 
  beds_list <- lapply(beds_list, 
                      function(x) {
                        x <- x |> 
                          select(names(x)[!grepl("[0-9]", names(x))])
                        
                        if ("form" %in% names(x) & "nhs_region" %in% names(x)) {
                          x <- x |> select(-form, -nhs_region) #as one dataset has both
                        }
                        
                        else if ("form" %in% names(x)) {
                          x <- x |> select(-form)
                        }
                        
                        else if ("nhs_region" %in% names(x)) {
                          x <- x |> select(-nhs_region)
                        }
                        
                        else if ("sha" %in% names(x)) {
                          x <- x |> select(-sha)
                        }
                        
                        else {
                          x <- x
                        }
                      }
  )
  
  #making sure variables are numeric where appropriate 
  beds_list <- lapply(beds_list, 
                      function(x) {
                        x[, 5:ncol(x)] <- lapply(x[, 5:ncol(x)], function(y) as.numeric(y))
                        x
                      }
  )
  
  #adding the percent_occupied variables for 2000-01 and removing uncommon vars
  beds_list <- lapply(beds_list, 
                      function(x) {
                        if ("2000-01" %in% x$year) {
                          x <- x |> 
                            mutate(total_on_beds_percent_occupied = na_if(total_on_beds_available/total_on_beds_occupied, Inf), 
                                   general_acute_on_beds_percent_occupied = na_if(general_acute_on_beds_available/general_acute_on_beds_occupied, Inf), 
                                   learn_disabil_on_beds_percent_occupied = na_if(learn_disabil_on_beds_available/learn_disabil_on_beds_occupied, Inf), 
                                   maternity_on_beds_percent_occupied = na_if(maternity_on_beds_available/maternity_on_beds_occupied, Inf), 
                                   mental_illness_on_beds_percent_occupied = na_if(mental_illness_on_beds_available/mental_illness_on_beds_occupied, Inf)) |> 
                            select(-c(available_acute, available_geriatric, occupied_acute, occupied_geriatric)) 
                        }
                        else {
                          x 
                        }
                      })
  
  #DEALING WITH DATES 
  #data is in financial year of NHS, so Q1 is April-June, Q2 is July-September, etc. 
  #dealing with years - take the start year as the year, so 2000-01 becomes 2000, 
  #so that can merge with later dta
  beds_list <- lapply(beds_list, 
                      function(x) 
                        x <- x |> 
                        mutate(year = str_extract(year, "^[0-9]{4}")))
  
  #rbinding everything together
  beds_2000_2010 <- rbindlist(beds_list, use.names = TRUE) |>
    select(-fname) |> 
    arrange(org_code, year)
  
  beds_2000_2010
}

# FUNCTION FOR DAY BED CLEANING 2000 - 2010 ------------------------------------
day_bed_data_cleaning_0010 <- function(beds_list) {
  
  #clean variable names
  beds_list <- lapply(beds_list, 
                      function(x)
                        setnames(x, names(x), make_clean_names(names(x))))
  
  #for linkage later, setting orgID to org_code
  beds_list <- lapply(beds_list, 
                      function(x)
                        setnames(x, c("org_id", "name"), c("org_code", "org_name")))
  
  #setting variable names
  beds_list <- lapply(beds_list, 
                      function(x) 
                        if("available_beds" %in% names(x)) {
                          setnames(x, "available_beds", "total_day_beds_available")
                        }
                      
                      else {
                        setnames(x, "total", "total_day_beds_available")
                      }
                      
  )
  
  #removing variables that aren't available later 
  beds_list <- lapply(beds_list, 
                      function(x) 
                        if("other_ages" %in% names(x)) {
                          x <- x |> select(-c(neonates_and_children, other_ages))
                        }
                      
                      else {
                        x <- x
                      }
                      
  )
  
  #making sure all trust names are capitalised for easier merging later on 
  beds_list <- lapply(beds_list, 
                      function(x) {
                        x$org_name <- toupper(x$org_name)
                        x
                      }
  )
  
  #dealing with missing rows 
  beds_list <- lapply(beds_list, 
                      function(x)
                        x <- x |> filter(!is.na(org_name)))
  
  beds_list <- lapply(beds_list, 
                      function(x) {
                        x <- x |> 
                          select(names(x)[!grepl("[0-9]", names(x))])
                        
                        if ("form" %in% names(x) & "nhs_region" %in% names(x)) {
                          x <- x |> select(-form, -nhs_region) #as one dataset has both
                        }
                        
                        else if ("form" %in% names(x)) {
                          x <- x |> select(-form)
                        }
                        
                        else if ("nhs_region" %in% names(x)) {
                          x <- x |> select(-nhs_region)
                        }
                        
                        else if ("sha" %in% names(x)) {
                          x <- x |> select(-sha)
                        }
                        
                        else {
                          x <- x
                        }
                      }
  )
  
  #DEALING WITH DATES 
  #data is in financial year of NHS, so Q1 is April-June, Q2 is July-September, etc. 
  #dealing with years - take the start year as the year, so 2000-01 becomes 2000, 
  #so that can merge with later dta
  beds_list <- lapply(beds_list, 
                      function(x) 
                        x <- x |> 
                        mutate(year = str_extract(year, "^[0-9]{4}")))
  
  #rbinding everything together
  beds_2000_2010 <- rbindlist(beds_list, use.names = TRUE) |>
    select(-fname) |> 
    arrange(org_code, year)
  
  beds_2000_2010
}

# FUNCTION FOR BED EXTRACTION (DAY AND OVERNIGHT) 2010 - 2024 ------------------
bed_data_extraction_1024 <- function(filepath) {
  filenames_all <- list.files(filepath, 
                              recursive=TRUE, full.names=TRUE)
  
  filenames_1024 <- filenames_all[!grepl("20(0[0-9])", filenames_all)]

  #extracting data (early 2010 data in different format)
  beds_list <- lapply(filenames_1024, 
                           function(x) if (grepl("Quarter_1_2010-11", x) | grepl("Quarter_2_2010-11", x)) {
                             data.table(fname = str_extract(x, "[^/]+$"), 
                                        read_excel(path = x, sheet = "NHS Trust by Sector", skip = 5, na = "-"))
                           }
                           else 
                           {
                             data.table(fname = str_extract(x, "[^/]+$"), 
                                        read_excel(path = x, sheet = "NHS Trust by Sector", skip = 14, na = "-"))
                           }
  )
  
  beds_list
}
  
# FUNCTION FOR BED CLEANING (DAY AND OVERNIGHT) 2010 - 2024 --------------------
bed_data_cleaning_1024 <- function(beds_list, filepath) {
  
  #clean variable names
  beds_list <- lapply(beds_list, 
                      function(x)
                        setnames(x, names(x), make_clean_names(names(x))))
  
  #removing empty columns
  beds_list <- lapply(beds_list, 
                 function(x)
                   x <- x[, -c("x11", "x17")]) 
  
  #setting variable names, accounting for day or overnight beds
  beds_list <- lapply(beds_list, 
                      function(x) { 
                        if (grepl("overnight", filepath)) {
                          setnames(x, c("total_6", "total_12", "total_18"), c("total_on_beds_available", "total_on_beds_occupied", "total_on_beds_percent_occupied"))
                          setnames(x, c("general_acute_7", "general_acute_13", "general_acute_19"), c("general_acute_on_beds_available", "general_acute_on_beds_occupied", "general_acute_on_beds_percent_occupied"))
                          setnames(x, c("learning_disabilities_8", "learning_disabilities_14", "learning_disabilities_20"), c("learn_disabil_on_beds_available", "learn_disabil_on_beds_occupied", "learn_disabil_on_beds_percent_occupied"))
                          setnames(x, c("maternity_9", "maternity_15", "maternity_21"), c("maternity_on_beds_available", "maternity_on_beds_occupied", "maternity_on_beds_percent_occupied"))
                          setnames(x, c("mental_illness_10", "mental_illness_16", "mental_illness_22"), c("mental_illness_on_beds_available", "mental_illness_on_beds_occupied", "mental_illness_on_beds_percent_occupied"))
                        }
                        else {
                          setnames(x, c("total_6", "total_12", "total_18"), c("total_day_beds_available", "total_day_beds_occupied", "total_day_beds_percent_occupied"))
                          setnames(x, c("general_acute_7", "general_acute_13", "general_acute_19"), c("general_acute_day_beds_available", "general_acute_day_beds_occupied", "general_acute_day_beds_percent_occupied"))
                          setnames(x, c("learning_disabilities_8", "learning_disabilities_14", "learning_disabilities_20"), c("learn_disabil_day_beds_available", "learn_disabil_day_beds_occupied", "learn_disabil_day_beds_percent_occupied"))
                          setnames(x, c("maternity_9", "maternity_15", "maternity_21"), c("maternity_day_beds_available", "maternity_day_beds_occupied", "maternity_day_beds_percent_occupied"))
                          setnames(x, c("mental_illness_10", "mental_illness_16", "mental_illness_22"), c("mental_illness_day_beds_available", "mental_illness_day_beds_occupied", "mental_illness_day_beds_percent_occupied"))
                        }
                        }
  )
  
  #harmonising variable names across lists
  beds_list <- lapply(beds_list, 
                      function(x)
                        if ("period" %in% names(x)) {
                          setnames(x, "period", "period_end")
                          }
                      else 
                        {
                          x <- x
                          }
  )
  
  #making sure all trust names are capitalised for easier merging later on 
  beds_list <- lapply(beds_list, 
                      function(x) {
                        x$org_name <- toupper(x$org_name)
                        x
                      }
  )
  
  #removing strategic health authorities/ats/regions - can't find lookup now (shas abolished 2013) 
  #(can always merge regions back on with trust lookup)
  beds_list <- lapply(beds_list, 
                      function(x)
                        x[, -4])
  
  #dealing with missing rows 
  beds_list <- lapply(beds_list, 
                      function(x)
                        x <- x |> filter(!is.na(period_end)))
  
  #dealing with the dates 
  #data is in financial year of NHS, so Q1 is April-June, Q2 is July-September, etc. 
  #want to redo so have year and quarter in month terms, so Q1 is Jan-Mar
  #also need to separate out the years, so e.g. Q1 2019-20 becomes Q2 2019
  
  #dealing with years 
  beds_list <- lapply(beds_list, 
                      function(x) 
                        x <- x |> 
                        mutate(start_year = str_extract(year, "^[0-9]{4}"), 
                               end_year = as.numeric(str_extract(year, "[0-9]{2}$")) + 2000))
  
  #dealing with quarters - NHS financial year 
  beds_list <- lapply(beds_list,
                      function(x)
                        x <- x |>
                        mutate(quarter = ifelse(period_end == "June", "Q1",
                                                ifelse(period_end == "September", "Q2",
                                                       ifelse(period_end == "December", "Q3", "Q4")))))
  
  #assigning years to quarters
  beds_list <- lapply(beds_list,
                      function(x)
                        x <- x |>
                        mutate(year = ifelse(quarter == "Q4", end_year, start_year)) |>
                        select(-c(start_year, end_year)))
  
  #dealing with quarters - calendar year 
  # beds_list <- lapply(beds_list,
  #                     function(x)
  #                       x <- x |>
  #                       mutate(quarter = ifelse(period_end == "June", "Q2",
  #                                               ifelse(period_end == "September", "Q3",
  #                                                      ifelse(period_end == "December", "Q4", "Q1")))))
  #assigning years to quarters
  # beds_list <- lapply(beds_list, 
  #                     function(x) 
  #                       x <- x |> 
  #                       mutate(year = ifelse(quarter == "Q1", end_year, start_year)) |> 
  #                       select(-c(start_year, end_year)))
  
  #rbinding everything together 
  beds_2010_2024 <- rbindlist(beds_list) |> 
    select(-fname) |> 
    arrange(org_code, year, quarter)
  
  beds_2010_2024
}


# EXTRACTING AND CLEANING OVERNIGHT BEDS DATA 2000 - 2010 ----------------------
filepath_overnight <- file.path(getwd(), "rawdata/available-and-occupied-beds/overnight")
overnight_beds_0010_uncleaned <- bed_data_extraction_0010(filepath_overnight)
overnight_beds_0010_cleaned <- overnight_bed_data_cleaning_0010(overnight_beds_0010_uncleaned)

# EXTRACTING AND CLEANING DAY BEDS DATA 2000 - 2010 ----------------------------
filepath_day <- file.path(getwd(), "rawdata/available-and-occupied-beds/day")
day_beds_0010_uncleaned <- bed_data_extraction_0010(filepath_day)
day_beds_0010_cleaned <- day_bed_data_cleaning_0010(day_beds_0010_uncleaned)

# EXTRACTING AND CLEANING DAY BEDS DATA 2010 - 2024 ----------------------------
filepath_overnight <- file.path(getwd(), "rawdata/available-and-occupied-beds/overnight")
overnight_beds_1024_uncleaned <- bed_data_extraction_1024(filepath_overnight)
overnight_beds_1024_cleaned <- bed_data_cleaning_1024(overnight_beds_1024_uncleaned, filepath_overnight)

# EXTRACTING AND CLEANING DAY BEDS DATA 2010 - 2024 ----------------------------
filepath_day <- file.path(getwd(), "rawdata/available-and-occupied-beds/day")
day_beds_1024_uncleaned <- bed_data_extraction_1024(filepath_day)
day_beds_1024_cleaned <- bed_data_cleaning_1024(day_beds_1024_uncleaned, filepath_day)

# LINKING AND OUTPUTTING DAY AND OVERNIGHT BEDS DATA 2000 - 2010 ---------------
beds_0010 <- join(overnight_beds_0010_cleaned, day_beds_0010_cleaned) |> 
  arrange(org_code, year) 

write.csv(beds_0010, file.path(getwd(), "data/available-and-occupied-beds/overnight_day_beds_2000_10_clean.csv"), row.names = FALSE)

# LINKING AND OUTPUTTING DAY AND OVERNIGHT BEDS DATA 2010 - 2024 ---------------
beds_1024 <- join(overnight_beds_1024_cleaned, day_beds_1024_cleaned) |> 
  arrange(org_code, year, quarter)

write.csv(beds_1024, file.path(getwd(), "data/available-and-occupied-beds/overnight_day_beds_2010_24_clean.csv"), row.names = FALSE)

# LINKING BEDS DATA 2000 - 2024, ACCOUNTING FOR ORG CHANGES AND OUTPUTTING------
beds_0024 <- rbind(beds_1024, beds_0010, fill = TRUE) |> 
  arrange(org_code, year, quarter)

#loading trust_lookup_uncomplicated (for now)
trust_lookup_uncomplicated <- read.csv("data/org-changes/trust_lookup_uncomplicated_changes.csv")

#getting name file, as names will be taken out temporarily 
name_code_lookup <- beds_0024 |> 
  select(org_code, org_name) |> 
  unique() |> 
  group_by(org_code) |> 
  slice(1)

beds_0024 <- beds_0024 |> 
  select(-org_name) #taking out names temporarily
beds_0024$year <- as.numeric(beds_0024$year)

#identifying the problematic trusts 
problematic_trusts <- trust_lookup_uncomplicated |> 
  filter(problematic == 1)

problematic_trusts <- unique(c(problematic_trusts$old_code, problematic_trusts$final_code)) 

#creating variable to indicate problematic trusts 
beds_0024 <- beds_0024 |> 
  mutate(exp_problematic_org_change = ifelse(org_code %in% problematic_trusts, 1, 0))

#removing problematic trusts from lookup 
trust_lookup_uncomplicated <- trust_lookup_uncomplicated |> 
  filter(problematic == 0) |> 
  select(-problematic)

#separating out the affected trusts from beds 
all_affected_trusts <- unique(c(trust_lookup_uncomplicated$old_code, trust_lookup_uncomplicated$final_code))
beds_0024_orgchanges <- beds_0024 |> 
  filter(org_code %in% all_affected_trusts)
beds_0024 <- beds_0024 |> 
  filter(org_code %!in% all_affected_trusts)

#linking on the changed trusts 
setnames(trust_lookup_uncomplicated, "old_code", "org_code")
beds_0024_orgchanges <- join(beds_0024_orgchanges, trust_lookup_uncomplicated)

#getting indicator of period where something changed - can merge this back on later
  #IMPORTANT: this is the period BEFORE the organisational change happens 
change_indicator <- beds_0024_orgchanges |> 
  filter(!is.na(final_code)) |> 
  group_by(org_code, final_code) |> 
  mutate(change_year = max(year)) |> 
  mutate(quarter = ifelse(!is.na(quarter), str_extract(quarter, "[0-9]+"), quarter)) |> 
  mutate(change_quarter = ifelse(year == change_year & !is.na(quarter), max(as.numeric(quarter), na.rm = TRUE), NA)) |> 
  fill(change_quarter, .direction = "up") |> 
  ungroup() |> 
  select(final_code, change_year, change_quarter, experiences_split) |> 
  unique() |> 
  rename(year = change_year, 
         quarter = change_quarter, 
         org_code = final_code) |> 
  mutate(quarter = ifelse(!is.na(quarter), paste0("Q", quarter), quarter))

#making the date the first period with the new organisational arrangement 
change_indicator <- change_indicator |> 
  mutate(year = ifelse(is.na(quarter) & experiences_split == 0, year + 1, year))

change_indicator <- change_indicator |> 
  mutate(date = ifelse(!is.na(quarter) & experiences_split == 0, paste0(year, quarter), NA)) |> 
  mutate(date = yq(date) + months(3)) |> 
  mutate(quarter = ifelse(!is.na(date), quarter(date), quarter), 
         year = ifelse(!is.na(date), year(date), year))|> 
  mutate(quarter = ifelse(!is.na(quarter), paste0("Q", quarter), quarter)) |> 
  select(-date)

#changing names to final name 
beds_0024_orgchanges <- beds_0024_orgchanges |> 
  mutate(org_code = ifelse(!is.na(final_code), final_code, org_code))

#aggregating by trust, returning NA still if ALL values are NA 
beds_0024_orgchanges <- beds_0024_orgchanges |> 
  group_by(year, quarter, org_code, period_end, exp_problematic_org_change) |> 
  summarise(across(ends_with(c("available", "s_occupied")), ~ifelse(all(is.na(.)), NA, sum(., na.rm=TRUE))))

#adding the percent_occupied variables back in 
for (category in c("total_", "general_acute_", "learn_disabil_", "maternity_", "mental_illness_")) {
  for (type in c("day_", "on_")) {
   available_var <- paste0(category, type, "beds_available")
   occupied_var <- paste0(category, type, "beds_occupied")
   percent_var <- paste0(category, type, "beds_percent_occupied")
    
   beds_0024_orgchanges <- beds_0024_orgchanges |> 
     mutate(!!percent_var := !!sym(occupied_var) / !!sym(available_var)) |> 
     mutate(!!percent_var := ifelse(!!sym(percent_var) == "NaN", NA, !!sym(percent_var)))
  }
}

#linking all back together 
beds_0024 <- rbind(beds_0024, beds_0024_orgchanges) |> 
  arrange(org_code, year, quarter) 

#merging on information on changes and names 
beds_0024 <- join(beds_0024, name_code_lookup)

#creating new variables 
  # - unproblematic_org_change to indicate exact period when unproblematic org_change happens 
  # - exp_unproblematic_org_change to flag trusts that undergo unproblematic org change at some point
beds_0024 <- join(beds_0024, change_indicator)|> 
  rename(unproblematic_org_change = experiences_split) |> 
  mutate(unproblematic_org_change = ifelse(!is.na(unproblematic_org_change), 1, 0)) |> 
  group_by(org_code) |> 
  mutate(exp_unproblematic_org_change = ifelse(any(unproblematic_org_change == 1), 1, 0))
  

write.csv(beds_0024, file.path(getwd(), "data/available-and-occupied-beds/overnight_day_beds_2000_24_clean.csv"), row.names = FALSE)

# SOME NOTES ON THIS -----------------------------------------------------------
# - sometimes not all trusts have day beds available; in this case, they are coded as NA rather than as 0
# - only data from 2010 onwards is quarterly
# - data is in financial year; for yearly data, the year is coded as the start year, so e.g. 2000-01 is coded as year=2000

