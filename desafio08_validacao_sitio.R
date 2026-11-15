# =============================================================================
# Desafio 08 — Classificação de sítio: validação e preparação da base
#              para o modelo de Clutter
# Projeto C531 — talhões 1, 2, 3 e 6 — 9 parcelas permanentes
#
# Objetivo: reproduzir, de forma independente, o índice de local (S) das
# parcelas a partir de Hd × idade (método da curva-guia, Chapman-Richards),
# identificar a idade-índice que melhor reproduz o S fornecido na base e
# gerar a base consolidada para o Desafio 09.
#
# Regra central: a coluna S NÃO entra no ajuste. Ela é usada apenas na
# etapa de comparação (escolha da idade-índice e tabela final).
#
# Como executar (a partir da pasta desafio-08-validacao-sitio/):
#   Rscript desafio08_validacao_sitio.R
# Pacotes: readxl, ggplot2
# =============================================================================

suppressPackageStartupMessages({
  library(readxl)
  library(ggplot2)
})

arquivo_dados <- "dados/Dados_Clutter_original.xlsx"
pasta_saida   <- "saidas"
dir.create(pasta_saida, showWarnings = FALSE)

# Grade de idades-índice a testar (anos) e classes de sítio da base (m)
idades_indice <- seq(4, 7, by = 0.5)
classes_s     <- c(20, 22, 24, 26)

# -----------------------------------------------------------------------------
# 1. Leitura e padronização da base
# -----------------------------------------------------------------------------
ler_base <- function(arquivo) {
  dados <- as.data.frame(read_excel(arquivo))
  names(dados) <- c("projeto", "talhao", "parcela", "id", "b", "hd", "v", "s")
  dados$id_parcela <- paste0("T", dados$talhao, "-P", dados$parcela)
  dados
}

dados <- ler_base(arquivo_dados)

cat("Base:", nrow(dados), "medições em",
    length(unique(dados$id_parcela)), "parcelas\n")
cat("Idade (anos): de", round(min(dados$id), 2), "a", round(max(dados$id), 2), "\n")
cat("Hd (m): de", min(dados$hd), "a", max(dados$hd), "\n\n")

# -----------------------------------------------------------------------------
# 2. FUNÇÃO: ajuste da curva-guia (Chapman-Richards) aos dados agrupados
#    Hd = b0 * (1 - exp(-b1 * idade))^b2
#    Usa apenas id e hd (S não entra no ajuste).
# -----------------------------------------------------------------------------
ajustar_curva_guia <- function(dados,
                               inicio = list(b0 = 30, b1 = 0.3, b2 = 1.2)) {
  modelo <- nls(hd ~ b0 * (1 - exp(-b1 * id))^b2,
                data = dados[, c("id", "hd")],
                start = inicio,
                control = nls.control(maxiter = 500))

  res   <- residuals(modelo)
  n     <- length(res)
  p     <- length(coef(modelo))
  sqres <- sum(res^2)
  sqtot <- sum((dados$hd - mean(dados$hd))^2)
  syx   <- sqrt(sqres / (n - p))

  list(
    modelo   = modelo,
    coef     = coef(modelo),
    metricas = c(
      n          = n,
      r2         = 1 - sqres / sqtot,
      r2_ajust   = 1 - (sqres / (n - p)) / (sqtot / (n - 1)),
      syx_m      = syx,
      syx_pct    = 100 * syx / mean(dados$hd),
      rmse_m     = sqrt(sqres / n),
      aic        = AIC(modelo)
    )
  )
}

# Função auxiliar: forma da curva de Chapman-Richards (sem a assíntota)
forma_cr <- function(idade, b1, b2) (1 - exp(-b1 * idade))^b2

# -----------------------------------------------------------------------------
# 3. FUNÇÃO: índice de local de cada parcela para uma idade-índice (Ii)
#    Método da curva-guia (anamórfico):
#      S = Hd * [ (1 - exp(-b1*Ii)) / (1 - exp(-b1*idade)) ]^b2
#    Para cada parcela usa-se a medição com idade mais próxima de Ii.
# -----------------------------------------------------------------------------
calcular_sitio <- function(dados, coef, ii) {
  b1 <- coef[["b1"]]
  b2 <- coef[["b2"]]
  partes <- lapply(split(dados, dados$id_parcela), function(d) {
    linha <- d[which.min(abs(d$id - ii)), ]
    data.frame(
      talhao       = linha$talhao,
      parcela      = linha$parcela,
      id_parcela   = linha$id_parcela,
      idade_usada  = linha$id,
      hd_usada     = linha$hd,
      s_fornecido  = linha$s,          # usado só para comparação
      s_calculado  = linha$hd * forma_cr(ii, b1, b2) / forma_cr(linha$id, b1, b2)
    )
  })
  out <- do.call(rbind, partes)
  out$diferenca <- out$s_calculado - out$s_fornecido
  out[order(out$talhao, out$parcela), ]
}

# Classe de sítio mais próxima entre as classes da base
classificar <- function(s, classes = classes_s) {
  classes[apply(abs(outer(s, classes, "-")), 1, which.min)]
}

# -----------------------------------------------------------------------------
# 4. ROTINA: teste das idades-índice e seleção da melhor
#    Critério principal: menor soma de quadrados dos desvios (SQD) entre
#    S calculado e S fornecido. Critérios auxiliares: viés médio, desvio
#    absoluto médio e número de parcelas na mesma classe da base.
# -----------------------------------------------------------------------------
testar_idades_indice <- function(dados, coef, idades) {
  resumo <- lapply(idades, function(ii) {
    s <- calcular_sitio(dados, coef, ii)
    data.frame(
      idade_indice      = ii,
      sqd               = sum(s$diferenca^2),
      vies_medio        = mean(s$diferenca),
      desvio_abs_medio  = mean(abs(s$diferenca)),
      desvio_abs_max    = max(abs(s$diferenca)),
      parcelas_mesma_classe = sum(classificar(s$s_calculado) == s$s_fornecido)
    )
  })
  do.call(rbind, resumo)
}

# -----------------------------------------------------------------------------
# 5. FUNÇÃO: feixe de curvas de índice de local
#    Hd(t) = S * [ (1 - exp(-b1*t)) / (1 - exp(-b1*Ii)) ]^b2
# -----------------------------------------------------------------------------
gerar_feixe <- function(coef, ii, classes = classes_s,
                        idades = seq(2, 7.5, by = 0.05)) {
  b1 <- coef[["b1"]]
  b2 <- coef[["b2"]]
  do.call(rbind, lapply(classes, function(s) {
    data.frame(s = s, idade = idades,
               hd = s * forma_cr(idades, b1, b2) / forma_cr(ii, b1, b2))
  }))
}

# =============================================================================
# EXECUÇÃO
# =============================================================================

# --- Ajuste da curva-guia -----------------------------------------------------
ajuste <- ajustar_curva_guia(dados)
cat("Curva-guia (Chapman-Richards):\n")
print(summary(ajuste$modelo)$coefficients)
cat("\n")
print(round(ajuste$metricas, 4))
cat("\n")

# --- Teste das idades-índice --------------------------------------------------
teste <- testar_idades_indice(dados, ajuste$coef, idades_indice)
ii_sel <- teste$idade_indice[which.min(teste$sqd)]
cat("Teste das idades-índice:\n")
print(format(teste, digits = 4), row.names = FALSE)
cat("\nIdade-índice selecionada (menor SQD):", ii_sel, "anos\n\n")
write.csv(round(teste, 4), file.path(pasta_saida, "teste_idades_indice.csv"), row.names = FALSE)

# --- Comparação final de S ----------------------------------------------------
comp <- calcular_sitio(dados, ajuste$coef, ii_sel)
comp$classe_calculada <- classificar(comp$s_calculado)
cat("Comparação S fornecido × S calculado (Ii =", ii_sel, "anos):\n")
print(format(comp, digits = 4), row.names = FALSE)

comparacao_sitio <- data.frame(
  talhao      = comp$talhao,
  parcela     = comp$parcela,
  s_fornecido = comp$s_fornecido,
  s_calculado = round(comp$s_calculado, 2),
  diferenca   = round(comp$diferenca, 2)
)
write.csv(comparacao_sitio, file.path(pasta_saida, "comparacao_sitio.csv"), row.names = FALSE)

# Versão detalhada (idade e Hd usadas, classe mais próxima)
write.csv(transform(comp, s_calculado = round(s_calculado, 2), diferenca = round(diferenca, 2)),
          file.path(pasta_saida, "comparacao_sitio_detalhada.csv"), row.names = FALSE)

# --- Curva-guia ajustada: coeficientes, idade-índice e métricas ---------------
cf <- summary(ajuste$modelo)$coefficients
curva_guia <- data.frame(
  item  = c("modelo", "b0", "b1", "b2",
            "ep_b0", "ep_b1", "ep_b2",
            "idade_indice_selecionada_anos", "criterio_selecao",
            names(ajuste$metricas)),
  valor = c("Hd = b0*(1-exp(-b1*idade))^b2",
            signif(cf[, 1], 6), signif(cf[, 2], 6),
            ii_sel, "menor soma de quadrados dos desvios (S calculado - S fornecido)",
            signif(ajuste$metricas, 6))
)
write.csv(curva_guia, file.path(pasta_saida, "curva_guia_ajustada.csv"), row.names = FALSE)

# --- Base consolidada para o Desafio 09 ---------------------------------------
base_consolidada <- dados[, c("talhao", "parcela", "id", "hd", "b", "v", "s")]
write.csv(base_consolidada, file.path(pasta_saida, "base_consolidada_sitio.csv"), row.names = FALSE)

# --- Análises complementares (apoio à discussão) ------------------------------
# (a) Robustez do ajuste a diferentes valores iniciais do nls
inicios <- list(c(25, 0.5, 1.5), c(40, 0.1, 0.8), c(50, 0.05, 0.7))
robustez <- do.call(rbind, lapply(inicios, function(st) {
  m <- try(nls(hd ~ b0 * (1 - exp(-b1 * id))^b2, data = dados,
               start = list(b0 = st[1], b1 = st[2], b2 = st[3]),
               control = nls.control(maxiter = 1000)), silent = TRUE)
  if (inherits(m, "try-error")) return(NULL)
  data.frame(b0_ini = st[1], b1_ini = st[2], b2_ini = st[3],
             b0 = coef(m)[["b0"]], b1 = coef(m)[["b1"]], b2 = coef(m)[["b2"]],
             sq_residuos = deviance(m))
}))
cat("\nRobustez a valores iniciais (mesma solução = ajuste estável):\n")
print(format(robustez, digits = 5), row.names = FALSE)

# (b) Formulação alternativa: modelo de Schumacher, ln(Hd) = a + b/idade,
#     com S = Hd * exp[b * (1/Ii - 1/idade)]. Testa se outra formulação
#     reproduziria melhor o S da base.
schum <- lm(log(hd) ~ I(1 / id), data = dados)
bs <- coef(schum)[[2]]
sqd_schum <- sapply(idades_indice, function(ii) {
  d2 <- do.call(rbind, lapply(split(dados, dados$id_parcela), function(d) d[which.min(abs(d$id - ii)), ]))
  sum((d2$hd * exp(bs * (1 / ii - 1 / d2$id)) - d2$s)^2)
})
sensibilidade <- data.frame(idade_indice = idades_indice,
                            sqd_chapman_richards = teste$sqd,
                            sqd_schumacher = sqd_schum)
cat("\nSensibilidade à formulação (SQD por idade-índice):\n")
print(format(sensibilidade, digits = 4), row.names = FALSE)
cat("Schumacher: a =", round(coef(schum)[[1]], 4), "; b =", round(bs, 4),
    "; R² =", round(summary(schum)$r.squared, 4), "\n")
write.csv(round(sensibilidade, 4), file.path(pasta_saida, "sensibilidade_formulacao.csv"), row.names = FALSE)

# (c) S calculado médio por talhão (o S fornecido é constante dentro do talhão)
por_talhao <- aggregate(cbind(s_fornecido, s_calculado) ~ talhao, data = comp, FUN = mean)
por_talhao$s_calc_min <- aggregate(s_calculado ~ talhao, data = comp, FUN = min)$s_calculado
por_talhao$s_calc_max <- aggregate(s_calculado ~ talhao, data = comp, FUN = max)$s_calculado
cat("\nS calculado por talhão (média, mínimo e máximo das parcelas):\n")
print(format(por_talhao, digits = 4), row.names = FALSE)
write.csv(round(por_talhao, 3), file.path(pasta_saida, "sitio_por_talhao.csv"), row.names = FALSE)

# --- Gráficos -----------------------------------------------------------------
feixe <- gerar_feixe(ajuste$coef, ii_sel)
dados$S_base <- factor(dados$s)

g <- ggplot() +
  geom_line(data = feixe, aes(idade, hd, group = s), colour = "grey35", linewidth = 0.7) +
  geom_text(data = subset(feixe, idade == max(idade)),
            aes(idade, hd, label = paste0("S = ", s)), hjust = -0.1, size = 3.2) +
  geom_line(data = dados, aes(id, hd, group = id_parcela, colour = S_base),
            linewidth = 0.4, alpha = 0.6) +
  geom_point(data = dados, aes(id, hd, colour = S_base, shape = S_base), size = 2.2) +
  geom_vline(xintercept = ii_sel, linetype = "dashed", colour = "grey50") +
  annotate("text", x = ii_sel, y = 6, label = paste0("Ii = ", ii_sel, " anos"),
           hjust = -0.1, size = 3.2, colour = "grey30") +
  scale_x_continuous(limits = c(2, 8.3), breaks = 2:8) +
  scale_y_continuous(limits = c(5, 32)) +
  labs(x = "Idade (anos)", y = "Altura dominante, Hd (m)",
       colour = "S fornecido (m)", shape = "S fornecido (m)",
       title = "Feixe de curvas de índice de local (curva-guia de Chapman-Richards)",
       subtitle = "Pontos: medições das 9 parcelas, identificadas pelo S fornecido na base") +
  theme_bw(base_size = 11) +
  theme(legend.position = "bottom")
ggsave(file.path(pasta_saida, "feixe_curvas_sitio.png"), g, width = 7.5, height = 5.5, dpi = 300)

g2 <- ggplot(teste, aes(idade_indice, sqd)) +
  geom_line() + geom_point(size = 2) +
  geom_point(data = subset(teste, idade_indice == ii_sel), colour = "red", size = 3) +
  labs(x = "Idade-índice testada (anos)",
       y = "SQD entre S calculado e S fornecido (m²)",
       title = "Seleção da idade-índice") +
  theme_bw(base_size = 11)
ggsave(file.path(pasta_saida, "selecao_idade_indice.png"), g2, width = 6, height = 4, dpi = 300)

cat("\nArquivos gravados em", pasta_saida, ":\n")
print(list.files(pasta_saida))
