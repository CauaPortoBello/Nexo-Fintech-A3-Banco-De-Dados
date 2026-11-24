-- =====================================================================
-- Nexo · Projeto A3 de Banco de Dados (USJT)
-- Script DDL do modelo inicial do grupo: tipos, tabelas, restrições e índices
-- SGBD: PostgreSQL 16 (executado de ponta a ponta em PostgreSQL 16, sem erros)
--
-- Este é o modelo inicial (DER em modelagem/versao-inicial/). O modelo final
-- descrito no relatório (Figura 1 e Quadro 2) evoluiu a partir dele.
--
-- Execução (banco vazio, para no primeiro erro):
--   createdb nexo
--   psql -d nexo -v ON_ERROR_STOP=1 -1 -f sql/01_ddl_modelo_inicial.sql
-- =====================================================================

CREATE TYPE perfil_investidor_enum AS ENUM ('conservador', 'moderado', 'agressivo');
CREATE TYPE tipo_conta_enum        AS ENUM ('corrente', 'poupanca', 'investimento');
CREATE TYPE risco_enum             AS ENUM ('baixo', 'medio', 'alto');

CREATE TABLE cliente (
    cliente_id         INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome                VARCHAR NOT NULL,
    cpf                 VARCHAR NOT NULL UNIQUE,
    data_nascimento     DATE,
    email               VARCHAR UNIQUE,
    telefone            VARCHAR,
    perfil_investidor   perfil_investidor_enum,
    score_atual         INT,
    data_cadastro       DATE NOT NULL DEFAULT CURRENT_DATE
);
COMMENT ON TABLE cliente IS 'Titular cadastrado na Nexo. O perfil_investidor é autodeclarado e usado para orientar recomendações de investimento.';

CREATE TABLE conta (
    conta_id        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo_conta      tipo_conta_enum NOT NULL,
    agencia         VARCHAR,
    numero_conta    VARCHAR NOT NULL UNIQUE,
    saldo           DECIMAL(14,2) NOT NULL DEFAULT 0,
    data_abertura   DATE NOT NULL DEFAULT CURRENT_DATE
);
COMMENT ON TABLE conta IS 'Entidade genérica de conta. Especializada em conta_corrente, conta_poupanca ou conta_investimento conforme tipo_conta.';

CREATE TABLE categoria_transacao (
    categoria_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome            VARCHAR NOT NULL,
    tipo            VARCHAR NOT NULL CHECK (tipo IN ('entrada', 'saida'))
);

CREATE TABLE conta_corrente (
    conta_id                INT PRIMARY KEY REFERENCES conta(conta_id) ON DELETE CASCADE,
    limite_cheque_especial  DECIMAL(14,2)
);
COMMENT ON TABLE conta_corrente IS 'Subtipo de conta. Existe somente quando conta.tipo_conta = corrente.';

CREATE TABLE conta_poupanca (
    conta_id        INT PRIMARY KEY REFERENCES conta(conta_id) ON DELETE CASCADE,
    dia_aniversario INT CHECK (dia_aniversario BETWEEN 1 AND 31)
);
COMMENT ON TABLE conta_poupanca IS 'Subtipo de conta. Existe somente quando conta.tipo_conta = poupanca.';

CREATE TABLE conta_investimento (
    conta_id            INT PRIMARY KEY REFERENCES conta(conta_id) ON DELETE CASCADE,
    perfil_risco_conta  VARCHAR
);
COMMENT ON TABLE conta_investimento IS 'Subtipo de conta. Existe somente quando conta.tipo_conta = investimento.';

--   3b) N:N — cliente <-> conta (contas conjuntas), via tabela associativa

CREATE TABLE cliente_conta (
    cliente_id          INT NOT NULL REFERENCES cliente(cliente_id) ON DELETE CASCADE,
    conta_id            INT NOT NULL REFERENCES conta(conta_id) ON DELETE CASCADE,
    tipo_titularidade   VARCHAR NOT NULL CHECK (tipo_titularidade IN ('titular', 'cotitular')),
    PRIMARY KEY (cliente_id, conta_id)
);
COMMENT ON TABLE cliente_conta IS 'Entidade associativa que resolve o relacionamento N:N entre cliente e conta (contas conjuntas).';

--   3c) 1:N — dependentes de conta / cliente

CREATE TABLE transacao (
    transacao_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    conta_id        INT NOT NULL REFERENCES conta(conta_id) ON DELETE CASCADE,
    categoria_id    INT REFERENCES categoria_transacao(categoria_id) ON DELETE SET NULL,
    tipo_operacao   VARCHAR NOT NULL CHECK (tipo_operacao IN ('debito', 'credito')),
    valor           DECIMAL(14,2) NOT NULL,
    data_hora       TIMESTAMP NOT NULL,
    descricao       VARCHAR
);

CREATE TABLE cartao (
    cartao_id           INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    conta_id            INT NOT NULL REFERENCES conta(conta_id) ON DELETE CASCADE,
    numero_mascarado    VARCHAR,
    tipo_cartao         VARCHAR NOT NULL CHECK (tipo_cartao IN ('credito', 'debito')),
    limite              DECIMAL(14,2),
    validade            DATE
);

CREATE TABLE fatura (
    fatura_id       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cartao_id       INT NOT NULL REFERENCES cartao(cartao_id) ON DELETE CASCADE,
    mes_referencia  VARCHAR NOT NULL,
    valor_total     DECIMAL(14,2),
    data_vencimento DATE,
    status_fatura   VARCHAR NOT NULL CHECK (status_fatura IN ('aberta', 'fechada', 'paga', 'atrasada'))
);

CREATE TABLE investimento (
    investimento_id         INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cliente_id              INT NOT NULL REFERENCES cliente(cliente_id) ON DELETE CASCADE,
    tipo_investimento       VARCHAR NOT NULL CHECK (tipo_investimento IN ('CDB', 'FII', 'Tesouro', 'Renda Variavel')),
    valor_aplicado          DECIMAL(14,2) NOT NULL,
    data_aplicacao          DATE NOT NULL DEFAULT CURRENT_DATE,
    rentabilidade_simulada  DECIMAL(8,4)
);

CREATE TABLE solicitacao_credito (
    solicitacao_id      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cliente_id           INT NOT NULL REFERENCES cliente(cliente_id) ON DELETE CASCADE,
    valor_solicitado      DECIMAL(14,2) NOT NULL,
    prazo_meses           INT,
    finalidade             VARCHAR,
    data_solicitacao       DATE NOT NULL DEFAULT CURRENT_DATE,
    status_solicitacao     VARCHAR NOT NULL DEFAULT 'em_analise'
                            CHECK (status_solicitacao IN ('em_analise', 'aprovada', 'recusada'))
);

--   3d) 1:1 — análise de crédito (obrigatório) e empréstimo (opcional)

CREATE TABLE analise_credito (
    analise_id          INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    solicitacao_id      INT NOT NULL UNIQUE REFERENCES solicitacao_credito(solicitacao_id) ON DELETE CASCADE,
    score_calculado      INT,
    risco                risco_enum,
    limite_recomendado   DECIMAL(14,2),
    taxa_sugerida        DECIMAL(6,4),
    data_analise         DATE NOT NULL DEFAULT CURRENT_DATE
);
COMMENT ON TABLE analise_credito IS 'Resultado do motor de regras da Nexo para cada solicitação de crédito (relação 1:1 obrigatória com solicitacao_credito).';

CREATE TABLE emprestimo (
    emprestimo_id       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    analise_id          INT UNIQUE REFERENCES analise_credito(analise_id) ON DELETE CASCADE,
    valor_aprovado       DECIMAL(14,2),
    taxa_juros           DECIMAL(6,4),
    prazo_meses          INT,
    data_contratacao     DATE NOT NULL DEFAULT CURRENT_DATE,
    status_emprestimo    VARCHAR NOT NULL DEFAULT 'ativo'
                          CHECK (status_emprestimo IN ('ativo', 'quitado', 'inadimplente'))
);
COMMENT ON TABLE emprestimo IS 'Criado somente quando a análise resulta em aprovação (relação 1:1 opcional com analise_credito).';

CREATE TABLE parcela_emprestimo (
    parcela_id          INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    emprestimo_id       INT NOT NULL REFERENCES emprestimo(emprestimo_id) ON DELETE CASCADE,
    numero_parcela       INT NOT NULL,
    valor_parcela        DECIMAL(14,2) NOT NULL,
    data_vencimento      DATE NOT NULL,
    status_pagamento     VARCHAR NOT NULL DEFAULT 'pendente'
                          CHECK (status_pagamento IN ('pendente', 'paga', 'atrasada')),
    UNIQUE (emprestimo_id, numero_parcela)
);

CREATE INDEX idx_transacao_conta      ON transacao(conta_id);
CREATE INDEX idx_transacao_categoria  ON transacao(categoria_id);
CREATE INDEX idx_cartao_conta         ON cartao(conta_id);
CREATE INDEX idx_fatura_cartao        ON fatura(cartao_id);
CREATE INDEX idx_investimento_cliente ON investimento(cliente_id);
CREATE INDEX idx_solicitacao_cliente  ON solicitacao_credito(cliente_id);
CREATE INDEX idx_parcela_emprestimo   ON parcela_emprestimo(emprestimo_id);
CREATE INDEX idx_cliente_conta_conta  ON cliente_conta(conta_id);
