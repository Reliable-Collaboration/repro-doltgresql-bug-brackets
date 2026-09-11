-- Expressions that need their brackets.
CREATE TABLE t (
    a int,
    b int GENERATED ALWAYS AS ((a + 1) * 2) STORED,
    c int DEFAULT ((1 + 2) * 3)
);

INSERT INTO t (a) VALUES (1);

-- Saved values next to the same expressions in a query.
SELECT a, b, (a + 1) * 2 AS expected_b,
       c, (1 + 2) * 3 AS expected_c
FROM t;

-- The default as the server saved it.
SELECT column_default FROM information_schema.columns
WHERE table_name = 't' AND column_name = 'c';
