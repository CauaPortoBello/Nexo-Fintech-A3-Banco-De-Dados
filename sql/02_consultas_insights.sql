-- =====================================================================
-- Nexo · Projeto A3 de Banco de Dados (USJT)
-- 13 consultas para geração de insights (Apêndice A do relatório e
-- slides Q1–Q13 da apresentação)
--
-- Nota: em Q4, Q7 e Q8 os literais foram escritos em minúsculas
-- ('paga', 'debito', 'credito') para coincidir com as restrições CHECK
-- de 01_ddl_modelo_inicial.sql. Na versão do relatório/slides eles aparecem em
-- maiúsculas ('PAGO', 'DEBITO', 'CREDITO').
-- =====================================================================

-- Q1 · Ranking de clientes por saldo
-- Pergunta: Quais clientes têm mais dinheiro em conta?
-- Insight: Base para segmentar clientes e oferecer investimentos a quem tem saldo alto e investe pouco.
-- Técnicas: JOIN, SUM, COUNT, GROUP BY, RANK()
SELECT cl.cliente_id,
       cl.nome,
       COUNT(c.conta_id) AS qtd_contas,
       SUM(c.saldo)      AS saldo_total,
       RANK() OVER (ORDER BY SUM(c.saldo) DESC) AS ranking
FROM cliente cl
JOIN cliente_conta cc ON cc.cliente_id = cl.cliente_id
JOIN conta c          ON c.conta_id = cc.conta_id
GROUP BY cl.cliente_id, cl.nome
ORDER BY ranking
LIMIT 20;

-- Q2 · Funil de crédito por finalidade
-- Pergunta: De cada 100 solicitações, quantas viram análise e empréstimo, por finalidade?
-- Insight: Mostra onde o funil perde clientes e quais finalidades convertem mais.
-- Técnicas: LEFT JOIN, COUNT(DISTINCT), SUM, GROUP BY
SELECT s.finalidade,
       COUNT(DISTINCT s.solicitacao_id) AS solicitacoes,
       COUNT(DISTINCT a.analise_id)     AS analisadas,
       COUNT(DISTINCT e.emprestimo_id)  AS contratados,
       ROUND(100.0 * COUNT(DISTINCT e.emprestimo_id)
             / COUNT(DISTINCT s.solicitacao_id), 1) AS conversao_pct,
       SUM(s.valor_solicitado) AS valor_solicitado,
       SUM(e.valor_aprovado)   AS valor_aprovado
FROM solicitacao_credito s
LEFT JOIN analise_credito a ON a.solicitacao_id = s.solicitacao_id
LEFT JOIN emprestimo e      ON e.analise_id = a.analise_id
GROUP BY s.finalidade
ORDER BY conversao_pct DESC;

-- Q3 · Perfil de cada classe de risco
-- Pergunta: O que o motor de análise entrega em cada faixa de risco?
-- Insight: Valida as regras: risco maior deve ter score e limite menores e taxa maior.
-- Técnicas: JOIN, AVG, COUNT, GROUP BY
SELECT a.risco,
       COUNT(*)                            AS analises,
       ROUND(AVG(a.score_calculado), 0)    AS score_medio,
       ROUND(AVG(a.limite_recomendado), 2) AS limite_medio,
       ROUND(AVG(a.taxa_sugerida), 4)      AS taxa_media,
       ROUND(AVG(s.valor_solicitado), 2)   AS valor_pedido_medio
FROM analise_credito a
JOIN solicitacao_credito s ON s.solicitacao_id = a.solicitacao_id
GROUP BY a.risco
ORDER BY score_medio DESC;

-- Q4 · Inadimplência por faixa de atraso
-- Pergunta: Quanto da carteira está em atraso e há quantos dias?
-- Insight: Prioriza a cobrança; faixas maiores indicam perda provável.
-- Técnicas: CASE WHEN, COUNT, SUM, GROUP BY
SELECT CASE
         WHEN CURRENT_DATE - p.data_vencimento <= 30 THEN '1-30 dias'
         WHEN CURRENT_DATE - p.data_vencimento <= 60 THEN '31-60 dias'
         ELSE 'mais de 60 dias'
       END AS faixa_atraso,
       COUNT(*)             AS parcelas,
       SUM(p.valor_parcela) AS valor_em_atraso
FROM parcela_emprestimo p
WHERE p.status_pagamento <> 'paga'
  AND p.data_vencimento < CURRENT_DATE
GROUP BY 1
ORDER BY MIN(CURRENT_DATE - p.data_vencimento);

-- Q5 · Cartão próximo do limite
-- Pergunta: Quem usou 80% ou mais do limite do cartão no mês?
-- Insight: Alimenta o alerta de uso elevado do cartão e o score projetado.
-- Técnicas: JOIN, CASE WHEN, filtro com WHERE
SELECT cl.nome,
       ca.cartao_id,
       ca.tipo_cartao,
       ca.limite,
       f.valor_total,
       ROUND(100.0 * f.valor_total / ca.limite, 1) AS uso_pct,
       CASE
         WHEN f.valor_total >= ca.limite THEN 'ESTOURADO'
         WHEN f.valor_total >= 0.9 * ca.limite THEN 'CRITICO'
         ELSE 'ATENCAO'
       END AS situacao
FROM fatura f
JOIN cartao ca        ON ca.cartao_id = f.cartao_id
JOIN cliente_conta cc ON cc.conta_id = ca.conta_id
JOIN cliente cl       ON cl.cliente_id = cc.cliente_id
WHERE f.mes_referencia = '2026-10'
  AND f.valor_total >= 0.8 * ca.limite
ORDER BY uso_pct DESC;

-- Q6 · Maior peso de parcelas no mês
-- Pergunta: Quais clientes têm mais parcelas vencendo neste mês?
-- Insight: Mostra quem tem mais compromisso no mês e merece acompanhamento.
-- Técnicas: JOIN, SUM, GROUP BY, DENSE_RANK()
SELECT cl.nome,
       COUNT(p.parcela_id)  AS qtd_parcelas,
       SUM(p.valor_parcela) AS parcelas_do_mes,
       DENSE_RANK() OVER (ORDER BY SUM(p.valor_parcela) DESC) AS posicao
FROM parcela_emprestimo p
JOIN emprestimo e          ON e.emprestimo_id = p.emprestimo_id
JOIN analise_credito a     ON a.analise_id = e.analise_id
JOIN solicitacao_credito s ON s.solicitacao_id = a.solicitacao_id
JOIN cliente cl            ON cl.cliente_id = s.cliente_id
WHERE TO_CHAR(p.data_vencimento, 'YYYY-MM') = TO_CHAR(CURRENT_DATE,
     'YYYY-MM')
GROUP BY cl.cliente_id, cl.nome
ORDER BY posicao;

-- Q7 · Gastos por categoria e mês
-- Pergunta: Quais categorias mais pesam nos gastos de cada mês?
-- Insight: Revela categorias que pressionam o orçamento; a posição 1 é onde mais se gastou.
-- Técnicas: JOIN, SUM, GROUP BY, RANK() com PARTITION BY
SELECT TO_CHAR(t.data_hora, 'YYYY-MM') AS mes,
       cat.nome                        AS categoria,
       COUNT(*)                        AS qtd,
       SUM(t.valor)                    AS total_gasto,
       RANK() OVER (PARTITION BY TO_CHAR(t.data_hora, 'YYYY-MM')
                    ORDER BY SUM(t.valor) DESC) AS posicao_no_mes
FROM transacao t
JOIN categoria_transacao cat ON cat.categoria_id = t.categoria_id
WHERE t.tipo_operacao = 'debito'
GROUP BY TO_CHAR(t.data_hora, 'YYYY-MM'), cat.nome
ORDER BY mes DESC, posicao_no_mes;

-- Q8 · Fluxo de caixa mensal por cliente
-- Pergunta: O cliente gasta mais do que recebe em cada mês?
-- Insight: Meses seguidos de saldo líquido negativo são um sinal precoce de risco.
-- Técnicas: JOIN, CASE WHEN dentro de SUM, GROUP BY
SELECT cc.cliente_id,
       TO_CHAR(t.data_hora, 'YYYY-MM') AS mes,
       SUM(CASE WHEN t.tipo_operacao = 'credito' THEN t.valor ELSE 0 END)
            AS entradas,
       SUM(CASE WHEN t.tipo_operacao = 'debito'  THEN t.valor ELSE 0 END)
            AS saidas,
       SUM(CASE WHEN t.tipo_operacao = 'credito'
            THEN t.valor ELSE -t.valor END) AS saldo_liquido
FROM transacao t
JOIN cliente_conta cc ON cc.conta_id = t.conta_id
GROUP BY cc.cliente_id, TO_CHAR(t.data_hora, 'YYYY-MM')
ORDER BY cc.cliente_id, mes;

-- Q9 · Investimentos por perfil
-- Pergunta: Em que produtos cada perfil de investidor mais aplica?
-- Insight: Detecta desalinhamentos, como perfil conservador em renda variável.
-- Técnicas: JOIN, COUNT, SUM, GROUP BY, RANK() com PARTITION BY
SELECT cl.perfil_investidor,
       i.tipo_investimento,
       COUNT(*)              AS aplicacoes,
       SUM(i.valor_aplicado) AS total_aplicado,
       RANK() OVER (PARTITION BY cl.perfil_investidor
                    ORDER BY SUM(i.valor_aplicado) DESC)
                         AS posicao_no_perfil
FROM investimento i
JOIN cliente cl ON cl.cliente_id = i.cliente_id
GROUP BY cl.perfil_investidor, i.tipo_investimento
ORDER BY cl.perfil_investidor, posicao_no_perfil;

-- Q10 · Score atual vs. média das análises
-- Pergunta: O score do cliente é coerente com as análises de crédito?
-- Insight: Diferença grande revela score desatualizado ou mudança de comportamento.
-- Técnicas: JOIN, AVG, MAX, GROUP BY
SELECT cl.nome,
       cl.score_atual,
       ROUND(AVG(a.score_calculado), 0) AS media_score_analises,
       cl.score_atual - ROUND(AVG(a.score_calculado), 0) AS diferenca,
       MAX(a.data_analise) AS ultima_analise
FROM cliente cl
JOIN solicitacao_credito s ON s.cliente_id = cl.cliente_id
JOIN analise_credito a     ON a.solicitacao_id = s.solicitacao_id
GROUP BY cl.cliente_id, cl.nome, cl.score_atual
ORDER BY diferenca;

-- Q11 · Transações fora do padrão
-- Pergunta: Quais transações são muito maiores que o normal da conta?
-- Insight: Acima de 3 vezes a média da conta: ponto de partida para alerta de fraude.
-- Técnicas: Função de janela AVG() OVER (PARTITION BY), CASE WHEN
SELECT t.conta_id,
       t.transacao_id,
       t.data_hora,
       t.valor,
       ROUND(AVG(t.valor) OVER (PARTITION BY t.conta_id), 2)
            AS media_da_conta,
       ROUND(t.valor / AVG(t.valor) OVER (PARTITION BY t.conta_id), 1)
            AS vezes_a_media,
       CASE
         WHEN t.valor > 3 * AVG(t.valor) OVER (PARTITION BY t.conta_id)
              THEN 'ATIPICA'
         ELSE 'normal'
       END AS classificacao
FROM transacao t
ORDER BY vezes_a_media DESC
LIMIT 20;

-- Q12 · Retorno projetado por risco
-- Pergunta: Quanto de juros a carteira deve render por classe de risco?
-- Insight: Se risco alto não rende mais que baixo, a taxa sugerida precisa de revisão.
-- Técnicas: JOIN, SUM, COUNT(DISTINCT), GROUP BY
SELECT a.risco,
       COUNT(DISTINCT e.emprestimo_id) AS emprestimos,
       SUM(p.valor_parcela)            AS total_a_receber,
       ROUND(SUM(e.valor_aprovado / e.prazo_meses), 2) AS principal,
       ROUND(SUM(p.valor_parcela) - SUM(e.valor_aprovado / e.prazo_meses),
            2) AS juros_projetados,
       ROUND(100.0 * (SUM(p.valor_parcela)
                      - SUM(e.valor_aprovado / e.prazo_meses))
             / SUM(e.valor_aprovado / e.prazo_meses), 1) AS retorno_pct
FROM emprestimo e
JOIN analise_credito a     ON a.analise_id = e.analise_id
JOIN parcela_emprestimo p  ON p.emprestimo_id = e.emprestimo_id
GROUP BY a.risco
ORDER BY retorno_pct DESC;

-- Q13 · Uso do cheque especial
-- Pergunta: Quais contas estão no negativo e quanto do limite já usaram?
-- Insight: Sinal claro de aperto financeiro e chance de oferecer crédito mais barato.
-- Técnicas: JOIN, CASE WHEN, filtro com WHERE
SELECT c.conta_id,
       c.agencia,
       c.numero_conta,
       c.saldo,
       cc.limite_cheque_especial,
       ROUND(100.0 * ABS(c.saldo) / cc.limite_cheque_especial, 1)
            AS uso_limite_pct,
       CASE
         WHEN ABS(c.saldo) >= cc.limite_cheque_especial
              THEN 'LIMITE ESGOTADO'
         WHEN ABS(c.saldo) >= 0.5 * cc.limite_cheque_especial
              THEN 'USO ALTO'
         ELSE 'USO MODERADO'
       END AS situacao
FROM conta c
JOIN conta_corrente cc ON cc.conta_id = c.conta_id
WHERE c.saldo < 0
  AND cc.limite_cheque_especial > 0
ORDER BY uso_limite_pct DESC;
