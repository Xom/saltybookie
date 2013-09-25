library('Matrix')
library('glmnet')

matches <- read.table("matches.in.csv", header = TRUE, sep = ",", strip.white = TRUE, comment.char = "")

n <- length(matches$mid)

winnerloser <- as.factor(c(as.character(matches$winner), as.character(matches$loser)))
charnames <- attr(winnerloser, "levels")
winners <- winnerloser[1:n]
losers <- winnerloser[(n+1):(n*2)]
w <- table(winners)
l <- table(losers)

odds <- seq(1, n, 2)
evens <- seq(2, n, 2)
y <- factor(rep(1, n), c(0, 1))
y[evens] <- 0

m <- Matrix(0, nrow = n, ncol = length(charnames), sparse = TRUE)
m[cbind(odds, winners[odds])] <- 1
m[cbind(odds, losers[odds])] <- m[cbind(odds, losers[odds])] - 1
m[cbind(evens, losers[evens])] <- 1
m[cbind(evens, winners[evens])] <- m[cbind(evens, winners[evens])] - 1

weigh <- matches$X5.0 + 1

ridgemodel <- glmnet(m, y, family = "binomial", intercept = FALSE, alpha = 0, weights = weigh)
ratings <- ridgemodel$beta[,95]

scores <- -log(1 + exp(ratings[losers] - ratings[winners]))
chardevs <- rep(0, length(charnames))
for(i in 1:n) {
  chardevs[winners[i]] <- chardevs[winners[i]] + scores[i]
  chardevs[losers[i]] <- chardevs[losers[i]] + scores[i]
}
chardevs <- chardevs / (w + l)
chardevratios <- pmax(0.1, 1 - (chardevs / log(0.5)))
downweigh <- chardevratios[winners] * chardevratios[losers]

ridgemodel <- glmnet(m, y, family = "binomial", intercept = FALSE, alpha = 0, weights = (weigh * downweigh))
ratings <- ridgemodel$beta[,96]

bests <- rep(0, length(charnames))
worsts <- rep(0, length(charnames))
for(i in 1:n) {
  bests[winners[i]] <- if ((bests[winners[i]] == 0) || (ratings[losers[i]] > ratings[bests[winners[i]]])) losers[i] else bests[winners[i]]
  worsts[losers[i]] <- if ((worsts[losers[i]] == 0) || (ratings[winners[i]] < ratings[worsts[losers[i]]])) winners[i] else worsts[losers[i]]
}

# old, kludgy, and effective
lassomodel <- glmnet(m, y, family = "binomial", intercept = FALSE, alpha = 1, weights = weigh)
lassocoefs <- predict(lassomodel, m, s = 0.00004, type = "coefficients", exact = TRUE)
lassocoefs <- lassocoefs[2:length(lassocoefs)]
wellrated <- (w > 0) & (l > 0) & (abs(lassocoefs - lassomodel$beta[,length(lassomodel$lambda)]) < 0.73)

results <- cbind(1:length(charnames), w, l, ratings, bests, worsts, wellrated, chardevs)

write.csv(results)

