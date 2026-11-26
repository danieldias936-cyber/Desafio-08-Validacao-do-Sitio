# Desafio 08 — Classificação de sítio: validação e preparação da base para o modelo de Clutter

Projeto C531 (talhões 1, 2, 3 e 6), 9 parcelas permanentes e 43 medições.

O objetivo é reproduzir de forma independente o índice de local (S) das parcelas a partir da altura dominante (Hd) e da idade, pelo método da curva-guia, comparar o resultado com o S fornecido em `Dados_Clutter_original.xlsx` e gerar a base consolidada que será usada no Desafio 09.

## Estrutura da pasta

```
desafio-08-validacao-sitio/
├── README.md
├── relatorio.md                      # relatório curto (gráfico, tabela e discussão)
├── Relatorio_Desafio08.docx          # mesmo relatório em Word
├── desafio08_validacao_sitio.R       # script comentado
├── dados/
│   └── Dados_Clutter_original.xlsx
└── saidas/
    ├── curva_guia_ajustada.csv       # coeficientes, idade-índice e métricas  (saída exigida)
    ├── comparacao_sitio.csv          # talhao, parcela, s_fornecido, s_calculado, diferenca  (saída exigida)
    ├── base_consolidada_sitio.csv    # talhao, parcela, id, hd, b, v, s  (saída exigida)
    ├── teste_idades_indice.csv       # critérios para cada idade-índice testada
    ├── comparacao_sitio_detalhada.csv
    ├── sensibilidade_formulacao.csv  # Chapman-Richards × Schumacher
    ├── sitio_por_talhao.csv
    ├── feixe_curvas_sitio.png
    ├── selecao_idade_indice.png
    └── log_execucao.txt
```

## Como executar

Na pasta `desafio-08-validacao-sitio/`:

```bash
Rscript desafio08_validacao_sitio.R
```

O script precisa dos pacotes `readxl` e `ggplot2` e foi testado no R 4.3.3. Em Linux, convém rodar com locale UTF-8 (`LC_ALL=C.UTF-8`) para que os acentos dos gráficos saiam corretos.

## Funções do script

| Função | O que faz |
|---|---|
| `ler_base()` | Lê a planilha e padroniza os nomes das colunas |
| `ajustar_curva_guia()` | Ajusta Chapman-Richards, Hd = b0·(1 − exp(−b1·idade))^b2, aos dados agrupados das 9 parcelas, usando **apenas idade e Hd**, e calcula R², R² ajustado, Syx, Syx%, RMSE e AIC |
| `calcular_sitio()` | Para uma idade-índice Ii, calcula o S de cada parcela por S = Hd·[(1 − exp(−b1·Ii)) / (1 − exp(−b1·idade))]^b2, usando a medição mais próxima de Ii |
| `testar_idades_indice()` | Repete o cálculo para Ii de 4 a 7 anos, em passos de 0,5, e resume os desvios em relação ao S fornecido |
| `gerar_feixe()` | Gera as curvas de índice de local para S = 20, 22, 24 e 26 m |

## Critério de seleção da idade-índice

A coluna S **não entra no ajuste**. Ela é usada somente depois, para comparar.

Para cada idade-índice testada, calcula-se o S de cada parcela e compara-se com o S fornecido na base. O critério principal é a **menor soma de quadrados dos desvios**:

SQD(Ii) = Σ (S calculado − S fornecido)², somada sobre as 9 parcelas.

Como apoio, também são registrados o viés médio, o desvio absoluto médio e máximo e o número de parcelas cuja classe mais próxima (20, 22, 24 ou 26 m) coincide com a da base.

**Resultado:** a idade-índice selecionada é **6,5 anos**, com SQD = 23,29 m², viés médio de −0,08 m e 5 das 9 parcelas na mesma classe da base. A seleção é pouco nítida: 5,5 anos (SQD = 26,61) e 7,0 anos (SQD = 29,18) ficam próximos. Os detalhes estão em `relatorio.md`.

## Base para o Desafio 09

O arquivo `saidas/base_consolidada_sitio.csv` mantém a base original (talhao, parcela, id, hd, b, v, s) com o **S fornecido**, conforme a especificação do desafio. O S recalculado e as diferenças estão em `saidas/comparacao_sitio.csv`, para consulta.
