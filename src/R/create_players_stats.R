# Author - Henrique Gomide Copyright
# TODO : Add player home_mean and away_mean, games_played, regularity, matches, price

library(tidyverse)
library(zoo)

source("~/pfc_R/lib/utils/functions.R")

# 0. Dataprep -------------------------------------------------------------
data <- readCsvInsideFolder(folderPath = "~/caRtola/data/2018/",
                            pattern = "rodada")

data$atletas.nome <- fixEncodingIssues(data$atletas.nome)
data$atletas.clube.id.full.name <- fixEncodingIssues(data$atletas.clube.id.full.name)
data$atletas.status_id <- fixEncodingIssues(data$atletas.status_id)

# Transform rodada_id into factor
data$atletas.rodada_id  <- factor(data$atletas.rodada_id,
                                  levels = c(1:max(data$atletas.rodada_id)),
                                  ordered = TRUE)

data <- dplyr::arrange(data, atletas.atleta_id, desc(atletas.rodada_id))

playerInfo <- 
  data %>%
  dplyr::select(atletas.slug, atletas.atleta_id, atletas.clube.id.full.name, 
                atletas.posicao_id, atletas.rodada_id, atletas.pontos_num, 
                atletas.status_id, atletas.apelido, atletas.preco_num)

scouts <- dplyr::select(data, 
                        atletas.rodada_id, atletas.atleta_id, CA, FC, 
                        FS, GC, I,
                        PE, RB, SG,
                        FF, FD, G, 
                        DD, GS, A,
                        FT, CV, DP,
                        PP)

scouts[,3:20] <- sapply(scouts[,3:20], function(x) ifelse(is.na(x), 0, x))

scouts <- 
  scouts %>%
  dplyr::group_by(atletas.atleta_id) %>%
  dplyr::mutate_each(funs(abs(diff(c(.,0)))), -`atletas.rodada_id`) %>%
  ungroup()

# Join with proper scouts
data <- left_join(playerInfo, scouts, by = c("atletas.atleta_id", "atletas.rodada_id"))

temp1 <- read.csv("~/caRtola/data/times_ids.csv", stringsAsFactors = FALSE)
data$atletas.clube.id.full.name <- plyr::mapvalues(data$atletas.clube.id.full.name, 
                                             from = as.vector(temp1$nome.cartola), 
                                             to = as.vector(temp1$id))
rm(temp1)

# Validation  - Compute scores
# data$computed.score <- (data$CA * -2) + (data$FC * -0.5) + (data$RB * 1.5) +
#   (data$GC * -5) + (data$CV * -5) + (data$SG * 5) +
#   (data$FS * .5) + (data$PE * -.3) + (data$A * 5) +
#   (data$FT * 3) + (data$FD * 1.2) + (data$FF * .8) +
#   (data$G * 8) + (data$I * -.5) + (data$PP * -4)

# 1. Feature Engineering ---------------------------------------------------

# 2. Remove clean sheet bonus
data$score.no.cleansheets <- (data$CA * -2) + (data$FC * -0.5) + (data$RB * 1.5) +
  (data$GC * -5) + (data$CV * -5) + #(data$SG * 5) +
  (data$FS * .5) + (data$PE * -.3) + (data$A * 5) +
  (data$FT * 3) + (data$FD * 1.2) + (data$FF * .8) +
  (data$G * 8) + (data$I * -.5) + (data$PP * -4) +
  (data$DD * 3) + (data$DP * 7) 

# Compute fouls for each round
data$faltas <- data$FC + data$CA + data$CV

# Compute shots on goal
data$shotsX <- data$G + data$FT + data$FD + data$FF

names(data)[1:6] <- c("slug", "atleta.id", "team", 
                      "posicao", "rodadaF", "pontuacao")

data$rodada <- as.integer(data$rodadaF)

data <- 
  data %>%
  group_by(atleta.id) %>% 
  arrange(rodadaF) %>%
  mutate(status = lag(atletas.status_id))

data$status <- ifelse(data$rodada == 1 & data$pontuacao != 0,  "Provável", data$status)

data <- mutate(data, pontuou = ifelse(CA + FC + FS + 
                                      GC + I + PE + 
                                      RB + SG + FF + 
                                      FD + G + DD + 
                                      GS + A + FT + 
                                      CV + DP + PP == 0,
                                      FALSE, TRUE))

# Merge matches and data frames to compute home and away scores
data <- left_join(data, matches[, c("round", "mando", "id", "date")], 
                   by = c("rodada" = "round", "team" = "id"))

# Create scouts with mean
scouts.mean <- 
  data %>%
  group_by(atleta.id) %>% 
  filter(pontuou == TRUE) %>%
  arrange(rodadaF) %>%
  mutate_at(.vars = c("shotsX", "faltas", "RB", 
                      "PE", "A", "I",
                      "FS", "FF", "G",
                      "DD", "DP", 
                      "score.no.cleansheets",
                      "pontuacao"), .funs = cummean) %>%
  
  dplyr::select(c("atleta.id", "rodada",
                  "shotsX", "faltas", "RB", 
                  "PE", "A", "I",
                  "FS", "FF", "G",
                  "DD", "DP",
                  "score.no.cleansheets",
                  "pontuacao"))

names(scouts.mean)[3:15] <- paste0(names(scouts.mean)[3:15], "_mean") 

data <- left_join(data, scouts.mean, by = c("rodada", "atleta.id"))

# Create home and away features
createHomeAndAwayScouts <- function(){
  scouts.home.away <- 
    data %>%
    group_by(atleta.id, mando) %>%
    filter(pontuou == TRUE) %>%
    arrange(rodadaF) %>%
    mutate_at(.vars = c("score.no.cleansheets","pontuacao"), 
              .funs = cummean) %>%
    dplyr::select("atleta.id", "mando", "rodada", 
                  "score.no.cleansheets","pontuacao")
  
  names(scouts.home.away)[4:5] <- paste0(names(scouts.home.away)[4:5], ".mean") 
  
  scouts.home.away <- gather(scouts.home.away, 
                             key = vars,
                             value = "valores",
                             -mando,
                             -rodada,
                             -atleta.id) 
  
  scouts.home.away <- unite(scouts.home.away, 
                            col = "var",
                            "vars", "mando",
                            sep = ".")
  
  scouts.home.away <- spread(scouts.home.away,
                             key = var,
                             value = valores)
  
  scouts.home.away <- scouts.home.away %>%
    dplyr::select(-score.no.cleansheets.mean.NA, 
                  -pontuacao.mean.NA)
  
  scouts.home.away <- scouts.home.away %>%
    fill(pontuacao.mean.casa, pontuacao.mean.fora,
         score.no.cleansheets.mean.casa, score.no.cleansheets.mean.fora)
  
  return(scouts.home.away)
  
}

scouts.home.away <- createHomeAndAwayScouts()

players.list <- 
  data %>%
  dplyr::group_by(atleta.id) %>%
  dplyr::filter(pontuou == TRUE) %>%
  dplyr::summarise(n.jogos = n(),
                   rodada  = max(rodada)) %>%
  dplyr::filter(n.jogos >= 10)

n.games.scouts.home.away <- left_join(players.list, scouts.home.away,
                              by = c("atleta.id" = "atleta.id",
                                     "rodada" = "rodada"))

data <- left_join(data, n.games.scouts.home.away, 
                  by = c("atleta.id" = "atleta.id",
                         "rodada" = "rodada"))

df.model <- 
  data %>%
  dplyr::filter(atleta.id %in% players.list$atleta.id) %>%
  dplyr::filter(rodada > 10 & pontuou == TRUE) %>%
  dplyr::mutate(diff.home.away = score.no.cleansheets.mean.casa - score.no.cleansheets.mean.fora)

df.model$diff.home.away.scalled <- scale(df.model$diff.home.away)

# Get last know stats for each player ---------------------------------------------------------
df.agg <- 
  df.model %>%
  dplyr::group_by(atleta.id) %>%
  dplyr::filter(rodadaF == max(rodadaF))

df.cartola.2018 <- 
  df.agg %>%
  select(slug, atleta.id, atletas.apelido, 
         team, posicao, atletas.preco_num, 
         pontuacao_mean, score.no.cleansheets_mean, diff.home.away.scalled, n.jogos,
         pontuacao.mean.casa, pontuacao.mean.fora,
         shotsX_mean, faltas_mean, RB_mean,
         PE_mean, A_mean, I_mean, 
         FS_mean, FF_mean, G_mean,
         DD_mean, DP_mean)

names(df.cartola.2018) <- c("player_slug", "player_id", "player_nickname",
                            "player_team", "player_position", "price_cartoletas",
                            "score_mean", "score_no_cleansheets_mean", "diff_home_away_s", "n_games",
                            "score_mean_home", "score_mean_away",
                            "shots_x_mean", "fouls_mean",
                            "RB_mean", "PE_mean", "A_mean",
                            "I_mean", "FS_mean", "FF_mean",
                            "G_mean", "DD_mean", "DP_mean")

write.csv(df.cartola.2018,
          "~/caRtola/data/2018/2018-medias-jogadores.csv", 
          row.names = FALSE)
