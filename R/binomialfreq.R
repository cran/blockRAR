#' @title Block Design for Response-Adaptive Randomization for Binomial Data
#'
#' @description Simulation for binomial counts for block design for
#'    response-adaptive randomization with time as a confounding
#' @param p_treatment scalar. Proportion of events under the treatment arm.
#' @param p_control scalar. Proportion of events under the control arm.
#' @param N_total scalar. Total sample size.
#' @param block_number scalar. Number of blocks or time levels. The default is set to 4.
#'   If \code{block_number} is set to 1. This is a traditional RCT design.
#' @param drift scalar. The increase or decrease in proportion of event over time.
#'   In this case, the proportion of failure changes in each block by the number of
#'   patient accured over the total sample size. The full drift effect is seen in the
#'   final block.
#' @param simulation scalar. Number of simulation to be ran. The default is set to 10000.
#' @param conf_int scalar. Confidence level of the interval.
#' @param alternative character. A string specifying the alternative hypothesis,
#'    must be one of "less" or "greater" (default).
#' @param correct logical. A logical indicating whether to apply continuity correction
#'    when computing the test statistic: one half is subtracted from all |O - E|
#'    differences; however, the correction will not be bigger than the differences themselves.
#' @param replace logical. should sampling be with replacement? If replace is set to
#'    FALSE (default), the 0 for control, 1 for treatment is replicated to the closest
#'    integer and this vector is sampled with no replacement. If replace is set to TRUE,
#'    the sampling is done based on randomization ratio provided with replacement.
#' @param early_stop logical. A logical indicating whether the trials are stopped early
#'    for success or futility.
#' @param size_equal_randomization scalar. The number of run in patients because adaptive
#'    randomization is applied.
#' @param min_patient_earlystop scalar. Minimum number of patients before early stopping
#'    rule is applied.
#' @param max_prob scalar. The maximum probability for assigning to treatment/control
#'    group is 0.8.
#'
#'
#' @return a list with details on the simulation.
#' \describe{
#'   \item{\code{power}}{
#'     scalar. The power of the trial, ie. the proportion of success over the
#'     number of simulation ran.}
#'   \item{\code{p_control_estimate}}{
#'     scalar. The estimated proportion of events under the control group.}
#'   \item{\code{p_treatment_estimate}}{
#'     scalar. The estimated proportion of events under the treatment group.}
#'   \item{\code{N_enrolled}}{
#'     vector. The number of patients enrolled in the trial (sum of control
#'     and experimental group for each simulation. )}
#'   \item{\code{N_control}}{
#'     vector. The number of patients enrolled in the control group for
#'     each simulation.}
#'   \item{\code{N_control}}{
#'     vector. The number of patients enrolled in the experimental group for
#'     each simulation.}
#'   \item{\code{randomization_ratio}}{
#'     matrix. The randomization ratio allocated for each block.}
#' }
#'
#' @importFrom stats rbinom mantelhaen.test chisq.test
#' @importFrom ldbounds bounds
#' @importFrom dplyr mutate group_by summarize
#' @importFrom tibble as.tibble
#'
#' @export binomialfreq
#'
#' @examples
#' binomialfreq(p_control = 0.7, p_treatment = 0.65, N_total = 200,
#'             block_number = 2, simulation = 100)
#' binomialfreq(p_control = 0.5, p_treatment = 0.40, N_total = 200,
#'             block_number = 2, simulation = 100, drift = -0.15)

binomialfreq <- function(
  p_control,
  p_treatment,
  N_total,
  block_number             = 4,
  drift                    = 0,
  simulation               = 10000,
  conf_int                 = 0.95,
  alternative              = "greater",
  correct                  = FALSE,
  replace                  = TRUE,
  early_stop               = FALSE,
  size_equal_randomization = 20,
  min_patient_earlystop    = 20,
  max_prob                 = 0.8
){
   # stop if proportion of control is not between 0 and 1.
  if((p_control <= 0 | p_control >= 1)){
    stop("The proportion of event for the control group needs to between 0 and 1!")
  }

  # stop if proportion of treatment is not between 0 and 1.
  if((p_treatment <= 0 | p_treatment >= 1)){
    stop("The proportion of event for the treatment group needs to between 0 and 1!")
  }

  ## make sure sample size is an integer!
  if((N_total <= 0 | N_total %% 1 != 0)){
    stop("The sample size needs to be a positive integer!")
  }

  # the number of blocks need to be an integer.
  if((block_number <= 0 | block_number %% 1 != 0)){
    stop("The number of blocks needs to be a positve integer!")
  }

  # the number of blocks is bigger than the sample size.
  if(N_total/ block_number < 1){
    stop("The number of blocks is greater than sample size!")
  }

  # number of simulation needs to be a positive integer.
  if((simulation <= 0 | simulation %% 1 != 0)){
    stop("The number of simulation needs to be a positve integer!")
  }

  # the confidence interval needs to be between 0 and 1.
  if((conf_int <= 0 | conf_int >= 1)){
    stop("The confidence interval needs to between 0 and 1!")
  }

  # the alternative is either less or greater, two-sided not acceptable.
  if((alternative != "less" & alternative != "greater")){
    stop("The alternative can only be less or greater!")
  }

  # sampling accept either true or false
  if((replace != "TRUE" & replace != "FALSE")){
    stop("The replacement for sampling is either TRUE or FALSE!")
  }

  # the drift value cant make the prop of control/treatment exceed 1 or below 0.
  if(drift + p_control >= 1 | drift + p_control <= 0 |
     drift + p_treatment >= 1 | drift + p_treatment <= 0){
    stop("The drift value is too high causing the proportion of event to exceed 1
         in either the control or treatment group, pick a lower value for drift!")
  }

  # if
  if(!(early_stop == FALSE | early_stop == TRUE)){
    stop("Early stopping can be only TRUE or FALSE!")
  }

  # if number of patient in each block is 2 or smaller, sampling is done with replacement
  if(replace == FALSE & N_total / block_number <= 2){
    replace <- TRUE
  }

  # total sample size is divided equally into blocks
  group <- rep(floor(N_total / block_number), block_number)

  # if the remainder of total sample size divided by block number is not 0,
  # randomly add patients to each block
  if((N_total - sum(group)) > 0){
    index <- sample(1:block_number, N_total - sum(group))
    group[index] <- group[index] + 1
  }

  # if we allow early stopping, compute the lan-demets bound
  if(early_stop){
    # divided time equally between 0 and 1 with the number of blocks
    time <- cumsum(group)[cumsum(group) > min_patient_earlystop] / N_total
    #using lan-demets bound, computing the early stopping criteria for the number of blocks
    bounds <- bounds(time, iuse = c(1, 1), alpha = c((1 - conf_int) / 2, (1 - conf_int) / 2))$upper.bounds
  }

  #assigning power to 0
  power <- 0

  # assigning overall variables as NULL and drift for patient by patient
  N_control            <- NULL
  N_treatment          <- NULL
  sample_size          <- NULL
  p_control_estimate   <- NULL
  p_treatment_estimate <- NULL
  prop_diff_estimate   <- NULL
  drift_p              <- seq(drift / N_total, drift,  length.out = N_total)
  early_stopping       <- rep(0, simulation)
  randomization        <- array(NA, c(simulation, block_number))

  # looping overall all simulation
  for(k in 1:simulation){

    # assigning variables as NULL for each simulation
    data_total            <- data.frame()
    test_stat             <- 0
    index                 <- block_number

    #looping over all blocks
    for(i in 1:block_number){
      # create a data summary from previos block or if its null, create an empty
      # summary
      if(nrow(data_total) != 0 & nrow(data_total) >= min_patient_earlystop){
        y_ctr     <- sum(as.numeric(as.character(data_total$outcome[data_total$treatment == 0])))
        N_ctr     <- length(as.numeric(as.character(data_total$outcome[data_total$treatment == 0])))
        y_trt     <- sum(as.numeric(as.character(data_total$outcome[data_total$treatment == 1])))
        N_trt     <- length(as.numeric(as.character(data_total$outcome[data_total$treatment == 1])))
      }
      else{
        y_ctr     <- 0
        N_ctr    <- 0
        y_trt     <- 0
        N_trt     <- 0
      }

      # if the alternative is greater, use proportion to set randomization ratio
      if(alternative == "greater"){
        prob_trt <- (y_trt + 1) / (N_trt + 2) /
                    ((y_trt + 1) / (N_trt + 2) + (y_ctr + 1) / (N_ctr + 2))
      }
      # if the alternative is greater, use 1 - proportion to set randomization ratio
      else{
        prob_trt <- (1 - (y_trt + 1) / (N_trt + 2)) /
                   (1 - (y_trt + 1) / (N_trt + 2) + (1 - (y_ctr + 1) / (N_ctr + 2)))
      }

      # maximum probability assigning to the treatment group is 0.8
      if(prob_trt > max_prob){
        prob_trt <- max_prob
      }

      # maximum probability assigning to the control group is 0.8
      else if(prob_trt < (1 - max_prob)){
        prob_trt <- 1 - max_prob
      }

      # storing info of prob_trt
      randomization[k, i] <- prob_trt

      # generate data frame treatment assignment based on sampling and
      # alternative hypothesis. leave the outcome variable empty.
      data <- data.frame(
        treatment =
          if(replace == TRUE){
            sample(0:1, replace = T, group[i], prob = c(1 - prob_trt, prob_trt))
          }
        else{
            sampling <- rep(c(0, 1), round(c(group[i] * (1 - prob_trt) - 0.0001,
                                           group[i] * prob_trt + 0.0001)))
            sample(sampling, length(sampling))
        },
        outcome = rep(NA, group[i]))

      # fill in the outcome variable based on the treatment assignement and proportion
      # of event in respective arm
      data$outcome <- rbinom(nrow(data), 1, prob = data$treatment * p_treatment +
                               (1 - data$treatment) * p_control +
                               drift_p[((1:nrow(data)) + nrow(data_total))])

      # bind the data with previous block if available
      data_total <- rbind(data_total, data)

      # convert the data_total to factor for outcome and treatment
      data_total$treatment <- as.factor(data_total$treatment)
      data_total$outcome <- as.factor(data_total$outcome)

      # making sure outcome level of 1 is present, even if its not present in the data
      if(is.na(match("1", levels(data_total$outcome)))){
        data_total$outcome <- factor(data_total$outcome,
                                     levels=c(levels(data_total$outcome), "1"))
      }

      # making sure outcome level of 0 is present, even if its not present in the data
      if(is.na(match("0", levels(data_total$outcome)))){
        data_total$outcome <- factor(data_total$outcome,
                                     levels=c(levels(data_total$outcome), "0"))
      }

      # making sure the treatment group is present, even if its not present in the data
      if(is.na(match("1", levels(data_total$treatment)))){
        data_total$treatment <- factor(data_total$treatment,
                                     levels=c(levels(data_total$treatment), "1"))
      }

      # making sure the control group is present, even if its not present in the data
      if(is.na(match("0", levels(data_total$treatment)))){
        data_total$treatment <- factor(data_total$treatment,
                                     levels=c(levels(data_total$treatment), "0"))
      }

      # if one treatment is not present or one type of outcome is not present,
      # set the test_statistics to 0.
      if(all(data_total$outcome == 1) | all(data_total$outcome == 0) |
         all(data_total$treatment == 1) | all(data_total$treatment == 0)){
        test_stat <- 0
      }
      # else compute the test statistics
      else{
        test_stat <- sqrt(as.numeric(chisq.test(data_total$treatment,
                                                data_total$outcome,
                                                correct = correct)$statistic))
      }

      if(N_total / block_number > min_patient_earlystop){
        bound_index <- i
      }
      else{
        bound_index <- i - min_patient_earlystop / (N_total / block_number)
      }

      # if we allow early stopping and the
      # the test_statistics exceed the lan-demets bound, quit the loop
      if(early_stop & (nrow(data_total) > min_patient_earlystop) & (nrow(data_total) < N_total)){
        if(test_stat > bounds[bound_index]){
          index               <- i
          early_stopping[k]   <- 1
          randomization[k, (i + 1):block_number] <- 0
          break
        }
      }

    }

    # adding the time factor to the data using group function
    data_total <- data_total %>%
      mutate(time = factor(rep(1:index, group[1:index])))

    # summarizing the data by treatment group
    ctrl_prop <- mean(as.numeric(as.character(data_total$outcome[data_total$treatment == 0])))
    trt_prop <- mean(as.numeric(as.character(data_total$outcome[data_total$treatment == 1])))

    # estimating prop_difference
    prop_diff <- prop_strata(treatment = data_total$treatment,
                             outcome   = data_total$outcome,
                             block     = data_total$time)

    # if number of block is 1 or if any block has only one patients, then use chisq.test
    if(all(data_total$time == 1) | N_total / block_number <  2){
      # if the prop is in the right direction, compute p-value
      if(((ctrl_prop - trt_prop >= 0) & alternative == "less") |
         ((trt_prop - ctrl_prop >= 0) & alternative == "greater")){
        p.val <- chisq.test(data_total$treatment, data_total$outcome,
                            correct = correct)$p.value / 2
      }
      else{
        p.val <- 1
      }
    }
    # compute mantelhaen.test for number of block > 1.
    else{
      p.val <- mantelhaen.test(table(data_total), alternative = alternative,
                               correct = correct)$p.val
    }

    # compute the sample size for control, treatment and proportion for
    # control and treatment estimate
    N_control            <- c(N_control, sum(data_total$treatment == 0))
    N_treatment          <- c(N_treatment, sum(data_total$treatment == 1))
    sample_size          <- c(sample_size, nrow(data_total))
    p_control_estimate   <- c(p_control_estimate, ctrl_prop)
    p_treatment_estimate <- c(p_treatment_estimate, trt_prop)
    prop_diff_estimate   <- c(prop_diff_estimate, prop_diff)

    # compute the power if p-value is smaller than 0.05
    if(p.val < (1 - conf_int)){
      power <- power + 1
    }

  }

  #return all the output in a list
  output <- list(
    power                 = power / simulation,
    p_control_estimate    = p_control_estimate ,
    p_treatment_estimate  = p_treatment_estimate,
    prop_diff_estimate    = prop_diff_estimate,
    N_enrolled            = sample_size,
    N_control             = N_control,
    N_treatment           = N_treatment,
    early_stop            = early_stopping,
    randomization_ratio   = randomization
    )

  return(output)
}

## quiets concerns of R CMD check re: the .'s that appear in pipelines
if(getRversion() >= "2.15.1")  utils::globalVariables(c("treatment", "outcome"))




