# DoltgreSQL 1.3.1 drops brackets from saved expressions, so generated columns, defaults and checks compute wrong results

On DoltgreSQL 1.3.1, a generated column, a column default or a CHECK constraint whose expression needs
brackets silently computes the wrong result. `GENERATED ALWAYS AS ((a + 1) * 2)` stores 3 for `a = 1`
instead of 4, and `DEFAULT ((1 + 2) * 3)` inserts 7 instead of 9. No error is raised. The saved text has
lost its brackets: `information_schema.columns` shows the default as `1 + 2 * 3`.

PostgreSQL 18.6 stores 4 and 9 and keeps the brackets.

## Reproduce it

You need Docker and a POSIX shell: Linux, macOS, or Windows with WSL. The first run downloads the images.

```sh
git clone https://github.com/Reliable-Collaboration/repro-doltgresql-bug-brackets.git
cd repro-doltgresql-bug-brackets
./repro.sh
```

`repro.sh` starts a throwaway PostgreSQL 18.6 container and a throwaway DoltgreSQL 1.3.1 container, runs
[`repro.sql`](repro.sql) on each with the `psql` client inside that container, and prints the two outputs
side by side, marking the lines that differ. It exits 1 while DoltgreSQL's output differs from
PostgreSQL's and 0 once they are identical, and it removes both containers when it finishes.

To try another DoltgreSQL release, name its image:

```sh
DOLTGRESQL_IMAGE=dolthub/doltgresql:latest ./repro.sh
```

### Without the script

The same steps by hand, from the repository directory:

```sh
docker run -d --name brackets-postgres -e POSTGRES_PASSWORD=password postgres:18.6-bookworm
docker run -d --name brackets-doltgresql -e DOLTGRES_PASSWORD=password dolthub/doltgresql:1.3.1
docker cp repro.sql brackets-postgres:/tmp/repro.sql
docker cp repro.sql brackets-doltgresql:/tmp/repro.sql
docker exec -t -e PGPASSWORD=password brackets-postgres psql -X -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker exec -t -e PGPASSWORD=password brackets-doltgresql psql -X -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker rm -f brackets-postgres brackets-doltgresql
```

If a `docker exec` answers that the connection was refused, that server is still starting: wait a few
seconds and run it again.

## The test

[`repro.sql`](repro.sql):

```sql
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
```

## Expected behavior

The stored values equal the same expressions computed by the query: `b` is 4 and `c` is 9, and the saved
default keeps its brackets. This is what PostgreSQL 18.6 does:

```
-- Saved values next to the same expressions in a query.
SELECT a, b, (a + 1) * 2 AS expected_b,
       c, (1 + 2) * 3 AS expected_c
FROM t;
 a | b | expected_b | c | expected_c 
---+---+------------+---+------------
 1 | 4 |          4 | 9 |          9
(1 row)

-- The default as the server saved it.
SELECT column_default FROM information_schema.columns
WHERE table_name = 't' AND column_name = 'c';
 column_default 
----------------
 ((1 + 2) * 3)
(1 row)
```

## Actual behavior

No statement fails, but `b` is 3 and `c` is 7 while the same expressions in the query give 4 and 9, and
the saved default reads `1 + 2 * 3`. This is what DoltgreSQL 1.3.1 does:

```
-- Saved values next to the same expressions in a query.
SELECT a, b, (a + 1) * 2 AS expected_b,
       c, (1 + 2) * 3 AS expected_c
FROM t;
 a | b | expected_b | c | expected_c 
---+---+------------+---+------------
 1 | 3 |          4 | 7 |          9
(1 row)

-- The default as the server saved it.
SELECT column_default FROM information_schema.columns
WHERE table_name = 't' AND column_name = 'c';
 column_default 
----------------
 1 + 2 * 3
(1 row)
```

## Side by side

The output of `./repro.sh`:

```
Starting postgres:18.6-bookworm@sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af
Starting dolthub/doltgresql:1.3.1@sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851

Left: PostgreSQL. Right: DoltgreSQL. Lines that differ are marked with |.

-- Expressions that need their brackets.                      -- Expressions that need their brackets.
CREATE TABLE t (                                              CREATE TABLE t (
    a int,                                                        a int,
    b int GENERATED ALWAYS AS ((a + 1) * 2) STORED,               b int GENERATED ALWAYS AS ((a + 1) * 2) STORED,
    c int DEFAULT ((1 + 2) * 3)                                   c int DEFAULT ((1 + 2) * 3)
);                                                            );
CREATE TABLE                                                  CREATE TABLE
INSERT INTO t (a) VALUES (1);                                 INSERT INTO t (a) VALUES (1);
INSERT 0 1                                                    INSERT 0 1
-- Saved values next to the same expressions in a query.      -- Saved values next to the same expressions in a query.
SELECT a, b, (a + 1) * 2 AS expected_b,                       SELECT a, b, (a + 1) * 2 AS expected_b,
       c, (1 + 2) * 3 AS expected_c                                  c, (1 + 2) * 3 AS expected_c
FROM t;                                                       FROM t;
 a | b | expected_b | c | expected_c                           a | b | expected_b | c | expected_c 
---+---+------------+---+------------                         ---+---+------------+---+------------
 1 | 4 |          4 | 9 |          9                        |  1 | 3 |          4 | 7 |          9
(1 row)                                                       (1 row)

-- The default as the server saved it.                        -- The default as the server saved it.
SELECT column_default FROM information_schema.columns         SELECT column_default FROM information_schema.columns
WHERE table_name = 't' AND column_name = 'c';                 WHERE table_name = 't' AND column_name = 'c';
 column_default                                                column_default 
----------------                                              ----------------
 ((1 + 2) * 3)                                              |  1 + 2 * 3
(1 row)                                                       (1 row)


Result: DoltgreSQL's output differs from PostgreSQL's on 2 line(s), marked with |.
```

## Other observations

Each was checked on DoltgreSQL 1.3.1 and PostgreSQL 18.6 with the same kind of test:

- Brackets on the right are lost too. For `a = 1`, `2 * (a + 1)` stores 3, `a - (1 - 2)` stores -2 and
  `-(a + 1)` stores 0, where PostgreSQL stores 4, 2 and -2.
- A CHECK constraint is saved the same way. `CHECK ((a + 1) * 2 > 3)` refuses the valid row `a = 1`, and
  `information_schema.check_constraints` shows the check as `"a" + 1 * 2 > 3`. PostgreSQL accepts the row
  and shows `(((a + 1) * 2) > 3)`.
- The wrong default persists after `ALTER TABLE ... ADD PRIMARY KEY`.
- Not affected in these tests: `NOT (a = 1 AND a = 2)` as a generated column, a lookup through an
  expression index on `((a + 1) * 2)`, and a view computing `(1 + 2) * 3`.
- `information_schema.columns.generation_expression` is empty for generated columns on DoltgreSQL.
- Possibly related: [dolthub/doltgresql#3323](https://github.com/dolthub/doltgresql/issues/3323), where a
  saved generated expression is written back with an alias that DoltgreSQL cannot parse.

## Environment

- DoltgreSQL 1.3.1, the newest release when this was written: image `dolthub/doltgresql:1.3.1`, digest
  `sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851`, built for linux/amd64 and
  linux/arm64. Its bundled `psql` is 17.11.
- PostgreSQL 18.6: image `postgres:18.6-bookworm`, digest
  `sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af`.
- Reproduced on 2026-09-11 with Docker 29.7.2 on Linux x86_64.
