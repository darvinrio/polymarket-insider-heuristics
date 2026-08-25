# AGENTS.md

Guidance for AI agents and human contributors working in this repository.

## Tooling

- **uv** — project and environment management. Run all code and tools via `uv run`.
- **ruff** — linting and formatting (config in `pyproject.toml`).
- **ty** — strict type checking (config in `pyproject.toml`).

## Commands

All commands live in [COMMANDS.md](COMMANDS.md). Use the commands documented
there verbatim. Do not improvise new flags, commands, or install new tools
without adding them to `COMMANDS.md` first.

## Requirements

### Strict typing

- Code must pass `uv run ty check` with zero errors.
- Every function and method has fully annotated parameters and a return type.
- Prefer `typing`-stdlib annotations over string annotations; use `pd`-style
  (PEP 604) unions — e.g. `str | None`, not `Optional[str]`.
- Do not use bare `Any` unless strictly necessary; prefer precise types.
- Do not suppress type errors with `# type: ignore` (or `# ty: ignore`).
  If a suppression is unavoidable, add a brief justification comment.

### Strict docstrings

- Every public module, class, and function/method requires a docstring
  (enforced by ruff's `D` rules).
- Docstrings follow the Google convention as configured in `pyproject.toml`.
- Keep docstrings accurate when changing behavior; update them in the same edit.

### Logging

- Use `loguru` for all logging — never the stdlib `logging` module or
  `print` for diagnostics.
- Every application setup configures a file sink for debug logs under the
  `logs/` directory (gitignored). Logs are organized per file name, each in
  its own subfolder: `logs/<name>/<name>_{time:YYYY-MM-DD}.log` (e.g.
  `logs/debug/debug_2026-08-12.log`), with `rotation="5MB"` and `retention`
  as appropriate.
- The terminal sink shows only info-level (normal) logs; debug details go to
  the file.

### Typed structs

- Use `msgspec.Struct` for all typed structs/models — never `dataclasses`.
- Prefer decoding API responses with `msgspec` decoders over manual parsing.

### Dataframes

- Use `polars` for all dataframe work — never `pandas`.
- Prefer lazy evaluation: use `pl.scan_*` / `LazyFrame` and force with
  `.collect()` only when a concrete `DataFrame` is required.
- Every polars `DataFrame` declares a clear schema; define all schemas in
  `models/schema.py` (or `src/models/schema.py` under a src layout).

### Code quality

- Follow ruff lint and format rules; the project is formatted with
  `ruff format`.
- After completing any task, run the full checklist below.

## Verification checklist

Run before finishing any change:

1. `uv run ruff format .`
2. `uv run ruff check . --fix`
3. `uv run ruff check .`
4. `uv run ty check`

All four must pass.
