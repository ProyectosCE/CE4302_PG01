#!/usr/bin/env python3
"""
plot_results.py

Genera gráficas comparativas MSI vs FIREFLY a partir de los CSV exportados
por el testbench workload_csv_tb.

Lee por defecto:
    ../sim_results/batch_reports/*_batch_summary.csv
    ../sim_results/csv_summary/*_summary.csv
    ../sim_results/csv_per_cache/*_cache_metrics.csv
    ../sim_results/csv_bus_events/*_bus_summary.csv
    ../sim_results/csv_memory/*_memory_metrics.csv
    ../sim_results/csv_state_transitions/*_state_transitions.csv
    ../sim_results/csv_timeline/*.csv

Uso:
    python plot_results.py
    python plot_results.py --results-dir ../sim_results
    python plot_results.py --batch-summary ../sim_results/batch_reports/XXXX_batch_summary.csv
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

WORKLOAD_ORDER = ["CONTENTION", "MIGRATION", "PROD-CONS"]
PROTOCOL_ORDER = ["MSI", "FIREFLY"]

MARKER_BY_WORKLOAD = {
    "CONTENTION": "o",
    "MIGRATION": "s",
    "PROD-CONS": "^",
}

LINESTYLE_BY_PROTOCOL = {
    "MSI": "-",
    "FIREFLY": "--",
}


# ============================================================
# Utilidades generales
# ============================================================

def sanitize_filename(name: str) -> str:
    name = str(name)
    name = name.replace("/", "_").replace("\\", "_")
    name = name.replace(" ", "_")
    name = name.replace("-", "_")
    return re.sub(r"[^A-Za-z0-9_]+", "", name)


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def latest_file(pattern: str, base_dir: Path) -> Optional[Path]:
    files = sorted(base_dir.glob(pattern), key=lambda p: p.stat().st_mtime, reverse=True)
    return files[0] if files else None


def read_csv_safe(path: Path) -> Optional[pd.DataFrame]:
    if not path.exists():
        return None

    try:
        return pd.read_csv(path)
    except Exception as exc:
        print(f"[WARN] No se pudo leer {path}: {exc}")
        return None


def read_many_csvs(folder: Path, pattern: str) -> pd.DataFrame:
    files = sorted(folder.glob(pattern))

    frames = []
    for file in files:
        df = read_csv_safe(file)
        if df is not None and not df.empty:
            df["source_file"] = str(file)
            frames.append(df)

    if not frames:
        return pd.DataFrame()

    return pd.concat(frames, ignore_index=True)


def to_numeric_if_exists(df: pd.DataFrame, cols: list[str]) -> pd.DataFrame:
    for col in cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")
    return df


def infer_size_from_workload_base(workload_base: str) -> Optional[int]:
    match = re.search(r"_(\d+)$", str(workload_base))
    if match:
        return int(match.group(1))
    return None


def infer_workload_model(workload_base: str) -> str:
    wb = str(workload_base).lower()

    if "contention" in wb:
        return "CONTENTION"
    if "migration" in wb:
        return "MIGRATION"
    if "prod-cons" in wb or "prod_cons" in wb or "producer" in wb:
        return "PROD-CONS"

    return "UNKNOWN"


def infer_metadata_from_source_file(source_file: str) -> dict:
    """
    Extrae metadata desde nombres como:

        20260510_153012_r01_MSI_workload_contention_20_summary.csv
        20260510_153012_r01_FIREFLY_workload_prod-cons_100_state_transitions.csv

    Devuelve:
        run_id
        protocol
        workload_base
        workload_model
        size
    """

    if source_file is None or pd.isna(source_file):
        return {}

    stem = Path(str(source_file)).stem

    known_suffixes = [
        "_state_transitions",
        "_cache_metrics",
        "_bus_summary",
        "_memory_metrics",
        "_summary",
        "_timeline",
    ]

    base = stem

    for suffix in known_suffixes:
        if base.endswith(suffix):
            base = base[: -len(suffix)]
            break

    # Busca el separador _MSI_ o _FIREFLY_
    match = re.search(r"_(MSI|FIREFLY)_", base, flags=re.IGNORECASE)

    if not match:
        return {}

    protocol = match.group(1).upper()
    run_id = base[: match.start()]
    workload_base = base[match.end():]

    size = infer_size_from_workload_base(workload_base)
    workload_model = infer_workload_model(workload_base)

    return {
        "run_id": run_id,
        "protocol": protocol,
        "workload_base": workload_base,
        "workload_model": workload_model,
        "size": size,
    }

def save_fig(path: Path) -> None:
    plt.tight_layout()
    plt.savefig(path, dpi=180)
    plt.close()
    print(f"[PLOT] {path}")


# ============================================================
# Carga de datos
# ============================================================

def load_batch_summary(results_dir: Path, explicit_path: Optional[Path]) -> pd.DataFrame:
    if explicit_path is not None:
        batch_path = explicit_path
    else:
        batch_path = latest_file("*_batch_summary.csv", results_dir / "batch_reports")

    if batch_path is None or not batch_path.exists():
        print("[WARN] No se encontró batch_summary.csv. Se intentará inferir desde los CSV.")
        return pd.DataFrame()

    print(f"[INFO] Usando batch summary: {batch_path}")

    df = pd.read_csv(batch_path)

    if "size" in df.columns:
        df["size"] = pd.to_numeric(df["size"], errors="coerce")

    if "status" in df.columns:
        df = df[df["status"].astype(str).str.upper() == "PASS"].copy()

    return df


def load_all_data(results_dir: Path, batch_summary_path: Optional[Path]) -> dict[str, pd.DataFrame]:
    batch_df = load_batch_summary(results_dir, batch_summary_path)

    summary_df = read_many_csvs(results_dir / "csv_summary", "*_summary.csv")
    cache_df = read_many_csvs(results_dir / "csv_per_cache", "*_cache_metrics.csv")
    bus_df = read_many_csvs(results_dir / "csv_bus_events", "*_bus_summary.csv")
    memory_df = read_many_csvs(results_dir / "csv_memory", "*_memory_metrics.csv")
    state_df = read_many_csvs(results_dir / "csv_state_transitions", "*_state_transitions.csv")
    timeline_df = read_many_csvs(results_dir / "csv_timeline", "*.csv")

    # Normalizar columnas numéricas comunes
    summary_df = to_numeric_if_exists(summary_df, [
        "num_cores",
        "total_accesses",
        "total_hits",
        "total_misses",
        "global_hit_rate",
        "global_miss_rate",
        "total_bus_requests",
        "total_bus_grants",
        "total_mem_accesses",
        "total_bus_bytes",
        "busrd",
        "busrdx",
        "busupd",
        "total_invalidations",
        "total_updates",
        "total_memory_accesses",
        "total_memory_bytes",
    ])

    cache_df = to_numeric_if_exists(cache_df, [
        "core_id",
        "read_hits",
        "read_misses",
        "write_hits",
        "write_misses",
        "total_accesses",
        "global_hit_rate",
        "global_miss_rate",
        "read_hit_rate",
        "write_hit_rate",
        "snoop_busrd",
        "snoop_busrdx",
        "snoop_busupd",
        "invalidations_received",
        "updates_received",
        "writebacks",
        "bus_stalls",
        "total_stall_time_ns",
        "avg_stall_time_ns",
        "max_stall_time_ns",
    ])

    bus_df = to_numeric_if_exists(bus_df, [
        "total_requests",
        "total_grants",
        "total_mem_accesses",
        "total_bytes",
        "total_invalidations",
        "total_updates",
        "queue_backpressure_events",
        "busrd",
        "busrdx",
        "busupd",
        "total_time_ns",
        "bandwidth_bytes_per_ns",
    ])

    memory_df = to_numeric_if_exists(memory_df, [
        "total_accesses",
        "busrd",
        "busrdx",
        "busupd",
        "total_bytes",
        "sim_time_ns",
        "bandwidth_bytes_per_ns",
        "max_queue_length",
        "avg_queue_wait_ns",
        "avg_service_time_ns",
        "avg_total_latency_ns",
        "total_service_time_ns",
    ])

    timeline_df = to_numeric_if_exists(timeline_df, [
        "cycle",
        "time_ns",
        "traffic_bytes",
        "bandwidth_bytes_per_cycle",
        "bandwidth_bytes_per_ns",
        "busrd_count",
        "busrdx_count",
        "busupd_count",
        "invalidation_count",
        "update_count",
        "memory_read_count",
        "memory_write_count",
    ])

    return {
        "batch": batch_df,
        "summary": summary_df,
        "cache": cache_df,
        "bus": bus_df,
        "memory": memory_df,
        "state": state_df,
        "timeline": timeline_df,
    }


def attach_batch_metadata(df: pd.DataFrame, batch_df: pd.DataFrame) -> pd.DataFrame:
    if df.empty:
        return df

    df = df.copy()

    # ------------------------------------------------------------
    # 1. Primero intentar inferir metadata desde el nombre del CSV.
    #    Esto es clave para state_transitions, porque normalmente
    #    esos CSV no traen protocol/workload/run_id en cada fila.
    # ------------------------------------------------------------

    if "source_file" in df.columns:
        metadata_rows = df["source_file"].apply(infer_metadata_from_source_file)
        metadata_df = pd.DataFrame(metadata_rows.tolist())

        for col in ["run_id", "protocol", "workload_base", "workload_model", "size"]:
            if col in metadata_df.columns:
                if col not in df.columns:
                    df[col] = metadata_df[col]
                else:
                    df[col] = df[col].fillna(metadata_df[col])

    # ------------------------------------------------------------
    # 2. Si ya hay run_id, unir con batch_summary para completar
    #    metadata oficial del batch.
    # ------------------------------------------------------------

    if not batch_df.empty and "run_id" in df.columns and "run_id" in batch_df.columns:
        keep_cols = [
            col for col in [
                "run_id",
                "batch_id",
                "run_index",
                "protocol",
                "workload_model",
                "workload_base",
                "size",
                "status",
            ]
            if col in batch_df.columns
        ]

        meta = batch_df[keep_cols].drop_duplicates(subset=["run_id"])
        df = df.merge(meta, on="run_id", how="left", suffixes=("", "_batch"))

        for col in ["protocol", "workload_model", "workload_base", "size", "status", "batch_id", "run_index"]:
            batch_col = f"{col}_batch"

            if batch_col in df.columns:
                if col in df.columns:
                    df[col] = df[col].fillna(df[batch_col])
                else:
                    df[col] = df[batch_col]

                df.drop(columns=[batch_col], inplace=True)

        # Filtrar solo los run_id pertenecientes al batch seleccionado.
        # Esto evita mezclar corridas viejas que también estén en sim_results.
        valid_run_ids = set(batch_df["run_id"].dropna().astype(str))
        df = df[df["run_id"].astype(str).isin(valid_run_ids)].copy()
    # ------------------------------------------------------------
    # 3. Inferencias finales por si falta algo.
    # ------------------------------------------------------------

    if "workload_base" not in df.columns:
        if "workload" in df.columns:
            df["workload_base"] = df["workload"]
        else:
            df["workload_base"] = "unknown"

    if "workload_model" not in df.columns:
        df["workload_model"] = df["workload_base"].apply(infer_workload_model)
    else:
        df["workload_model"] = df["workload_model"].fillna(
            df["workload_base"].apply(infer_workload_model)
        )

    if "size" not in df.columns:
        df["size"] = df["workload_base"].apply(infer_size_from_workload_base)
    else:
        df["size"] = df["size"].fillna(
            df["workload_base"].apply(infer_size_from_workload_base)
        )

    if "protocol" not in df.columns:
        df["protocol"] = "UNKNOWN"
    else:
        df["protocol"] = df["protocol"].fillna("UNKNOWN")
        df["protocol"] = df["protocol"].astype(str).str.upper()

    df["size"] = pd.to_numeric(df["size"], errors="coerce")

    return df

def plot_metric_vs_size_all_workloads(
    df: pd.DataFrame,
    out_dir: Path,
    metric: str,
    ylabel: str,
    title: str,
    filename: str,
    yscale: str = "linear",
    log_x: bool = True,
) -> None:
    """
    Genera un solo gráfico por métrica con las 6 curvas:
        MSI - CONTENTION
        FIREFLY - CONTENTION
        MSI - MIGRATION
        FIREFLY - MIGRATION
        MSI - PROD-CONS
        FIREFLY - PROD-CONS
    """

    if df.empty or metric not in df.columns:
        print(f"[SKIP] No existe métrica: {metric}")
        return

    required = ["size", "protocol", "workload_model", metric]

    if any(col not in df.columns for col in required):
        print(f"[SKIP] Faltan columnas para graficar {metric}.")
        return

    plot_df = df.dropna(subset=["size", metric]).copy()

    if plot_df.empty:
        print(f"[SKIP] Sin datos válidos para: {metric}")
        return

    # Si hay varias corridas para el mismo protocolo/workload/tamaño,
    # se promedia para evitar curvas duplicadas.
    plot_df = (
        plot_df
        .groupby(["workload_model", "protocol", "size"], as_index=False)[metric]
        .mean()
    )

    plt.figure(figsize=(11, 6))

    for workload_model in WORKLOAD_ORDER:
        for protocol in PROTOCOL_ORDER:
            sub = plot_df[
                (plot_df["workload_model"] == workload_model) &
                (plot_df["protocol"] == protocol)
            ].sort_values("size")

            if sub.empty:
                continue

            label = f"{protocol} - {workload_model}"

            plt.plot(
                sub["size"],
                sub[metric],
                marker=MARKER_BY_WORKLOAD.get(workload_model, "o"),
                linestyle=LINESTYLE_BY_PROTOCOL.get(protocol, "-"),
                linewidth=2,
                label=label,
            )

    plt.title(title)
    plt.xlabel("Instrucciones por PE")
    plt.ylabel(ylabel)
    plt.grid(True, which="both", linestyle="--", linewidth=0.5)
    plt.legend(fontsize=8)

    if log_x:
        plt.xscale("log")

    if yscale == "log":
        plt.yscale("log")

    save_fig(out_dir / filename)

def plot_bus_event_counters_all_workloads(df: pd.DataFrame, out_dir: Path) -> None:
    """
    Genera un gráfico por tipo de transacción de bus (BusRd, BusRdX, BusUpd).
    Cada gráfico incluye las 6 curvas MSI/FIREFLY × 3 workloads.
    """

    metrics = [
        (
            "bus_busrd",
            "BusRd totales",
            "Transacciones BusRd por tamaño de workload",
            "busrd_all_workloads.png",
        ),
        (
            "bus_busrdx",
            "BusRdX totales",
            "Transacciones BusRdX por tamaño de workload",
            "busrdx_all_workloads.png",
        ),
        (
            "bus_busupd",
            "BusUpd totales",
            "Transacciones BusUpd por tamaño de workload",
            "busupd_all_workloads.png",
        ),
    ]

    for metric, ylabel, title, filename in metrics:
        plot_metric_vs_size_all_workloads(
            df=df,
            out_dir=out_dir,
            metric=metric,
            ylabel=ylabel,
            title=title,
            filename=filename,
            yscale="log",
            log_x=True,
        )


def plot_state_transition_counts_all_workloads(
    state_df: pd.DataFrame,
    batch_df: pd.DataFrame,
    out_dir: Path
) -> None:
    """
    Genera un único gráfico de conteo de transiciones de estado,
    agrupando MSI/FIREFLY y los 3 workloads.
    """

    state_df = normalize_state_columns(state_df)
    state_df = attach_batch_metadata(state_df, batch_df)

    if state_df.empty:
        print("[SKIP] No hay CSV de transiciones de estado.")
        return

    if "protocol" not in state_df.columns or "workload_model" not in state_df.columns:
        print("[SKIP] No se pudo determinar protocol/workload_model para transiciones.")
        print(f"       Columnas encontradas: {list(state_df.columns)}")
        return

    if "old_state" not in state_df.columns or "new_state" not in state_df.columns:
        print("[SKIP] El CSV de transiciones no tiene old_state/new_state.")
        print(f"       Columnas encontradas: {list(state_df.columns)}")
        return

    state_df = state_df[state_df["protocol"] != "UNKNOWN"].copy()

    if state_df.empty:
        print("[SKIP] Las transiciones no tienen protocol identificable.")
        return

    state_df["transition"] = (
        state_df["old_state"].astype(str)
        + "→"
        + state_df["new_state"].astype(str)
    )

    count_df = (
        state_df
        .groupby(["workload_model", "protocol", "transition"], dropna=False)
        .size()
        .reset_index(name="count")
    )

    if count_df.empty:
        print("[SKIP] No hay transiciones para graficar.")
        return

    transitions = sorted(count_df["transition"].dropna().unique())

    x = np.arange(len(transitions))
    series = []

    for workload_model in WORKLOAD_ORDER:
        for protocol in PROTOCOL_ORDER:
            label = f"{protocol} - {workload_model}"
            sub = count_df[
                (count_df["workload_model"] == workload_model) &
                (count_df["protocol"] == protocol)
            ]

            if sub.empty:
                continue

            values = []
            for transition in transitions:
                row = sub[sub["transition"] == transition]
                values.append(float(row["count"].iloc[0]) if not row.empty else 0.0)

            series.append((label, values))

    if not series:
        print("[SKIP] No hay series válidas para transiciones.")
        return

    plt.figure(figsize=(13, 6))

    width = 0.8 / max(len(series), 1)

    for idx, (label, values) in enumerate(series):
        offset = (idx - (len(series) - 1) / 2) * width

        plt.bar(
            x + offset,
            values,
            width=width,
            label=label,
        )

    plt.title("Transiciones de estado de coherencia - MSI vs FIREFLY")
    plt.xlabel("Transición")
    plt.ylabel("Cantidad de transiciones")
    plt.xticks(x, transitions, rotation=45, ha="right")
    plt.grid(True, axis="y", linestyle="--", linewidth=0.5)
    plt.legend(fontsize=8)

    save_fig(out_dir / "state_transitions_all_workloads.png")


def build_merged_summary(data: dict[str, pd.DataFrame]) -> pd.DataFrame:
    batch_df = data["batch"]

    summary_df = attach_batch_metadata(data["summary"], batch_df)
    bus_df = attach_batch_metadata(data["bus"], batch_df)
    memory_df = attach_batch_metadata(data["memory"], batch_df)

    if summary_df.empty:
        print("[WARN] No hay datos en csv_summary.")
        return pd.DataFrame()

    merged = summary_df.copy()

    if not bus_df.empty:
        bus_keep = [
            col for col in [
                "run_id",
                "total_requests",
                "total_grants",
                "total_mem_accesses",
                "total_bytes",
                "total_invalidations",
                "total_updates",
                "queue_backpressure_events",
                "busrd",
                "busrdx",
                "busupd",
                "total_time_ns",
                "bandwidth_bytes_per_ns",
            ]
            if col in bus_df.columns
        ]

        bus_renamed = bus_df[bus_keep].copy()
        rename_map = {
            "total_requests": "bus_total_requests",
            "total_grants": "bus_total_grants",
            "total_mem_accesses": "bus_total_mem_accesses",
            "total_bytes": "bus_total_bytes",
            "total_invalidations": "bus_total_invalidations",
            "total_updates": "bus_total_updates",
            "queue_backpressure_events": "bus_queue_backpressure_events",
            "busrd": "bus_busrd",
            "busrdx": "bus_busrdx",
            "busupd": "bus_busupd",
            "total_time_ns": "bus_total_time_ns",
            "bandwidth_bytes_per_ns": "bus_bandwidth_bytes_per_ns",
        }
        bus_renamed.rename(columns=rename_map, inplace=True)

        merged = merged.merge(bus_renamed, on="run_id", how="left")

    if not memory_df.empty:
        mem_keep = [
            col for col in [
                "run_id",
                "total_accesses",
                "total_bytes",
                "sim_time_ns",
                "bandwidth_bytes_per_ns",
                "max_queue_length",
                "avg_queue_wait_ns",
                "avg_service_time_ns",
                "avg_total_latency_ns",
                "total_service_time_ns",
            ]
            if col in memory_df.columns
        ]

        mem_renamed = memory_df[mem_keep].copy()
        rename_map = {
            "total_accesses": "mem_total_accesses",
            "total_bytes": "mem_total_bytes",
            "sim_time_ns": "mem_sim_time_ns",
            "bandwidth_bytes_per_ns": "mem_bandwidth_bytes_per_ns",
            "max_queue_length": "mem_max_queue_length",
            "avg_queue_wait_ns": "mem_avg_queue_wait_ns",
            "avg_service_time_ns": "mem_avg_service_time_ns",
            "avg_total_latency_ns": "mem_avg_total_latency_ns",
            "total_service_time_ns": "mem_total_service_time_ns",
        }
        mem_renamed.rename(columns=rename_map, inplace=True)

        merged = merged.merge(mem_renamed, on="run_id", how="left")

    # Métricas derivadas
    if "bus_bandwidth_bytes_per_ns" in merged.columns:
        # 1 byte/ns = 1000 MB/s usando escala decimal
        merged["bus_bandwidth_MB_s"] = merged["bus_bandwidth_bytes_per_ns"] * 1000.0

    if "mem_bandwidth_bytes_per_ns" in merged.columns:
        merged["mem_bandwidth_MB_s"] = merged["mem_bandwidth_bytes_per_ns"] * 1000.0

    if "bus_total_bytes" not in merged.columns and "total_bus_bytes" in merged.columns:
        merged["bus_total_bytes"] = merged["total_bus_bytes"]

    if "bus_busrd" not in merged.columns and "busrd" in merged.columns:
        merged["bus_busrd"] = merged["busrd"]

    if "bus_busrdx" not in merged.columns and "busrdx" in merged.columns:
        merged["bus_busrdx"] = merged["busrdx"]

    if "bus_busupd" not in merged.columns and "busupd" in merged.columns:
        merged["bus_busupd"] = merged["busupd"]

    if "bus_total_invalidations" not in merged.columns and "total_invalidations" in merged.columns:
        merged["bus_total_invalidations"] = merged["total_invalidations"]

    if "bus_total_updates" not in merged.columns and "total_updates" in merged.columns:
        merged["bus_total_updates"] = merged["total_updates"]

    if "total_accesses" in merged.columns:
        denom = merged["total_accesses"].replace(0, np.nan)

        if "bus_busrdx" in merged.columns:
            merged["busrdx_per_access"] = merged["bus_busrdx"] / denom

        if "bus_busupd" in merged.columns:
            merged["busupd_per_access"] = merged["bus_busupd"] / denom

        if "bus_total_invalidations" in merged.columns:
            merged["invalidations_per_access"] = merged["bus_total_invalidations"] / denom

        if "bus_total_updates" in merged.columns:
            merged["updates_per_access"] = merged["bus_total_updates"] / denom

        # Métrica comparativa:
        # MSI: BusRdX por acceso.
        # Firefly: BusUpd por acceso.
        merged["ownership_or_update_rate"] = np.where(
            merged["protocol"].astype(str).str.upper() == "MSI",
            merged.get("busrdx_per_access", np.nan),
            merged.get("busupd_per_access", np.nan),
        )

    return merged


# ============================================================
# Gráficas generales MSI vs Firefly  (una sola por métrica)
# ============================================================

def plot_bus_events_grouped(df: pd.DataFrame, out_dir: Path) -> None:
    """
    Un único gráfico de barras apiladas que muestra BusRd / BusRdX / BusUpd
    para todas las combinaciones protocolo × workload, agrupadas por tamaño.
    """
    required = ["size", "protocol", "workload_model", "bus_busrd", "bus_busrdx", "bus_busupd"]

    if df.empty or any(col not in df.columns for col in required):
        print("[SKIP] No hay columnas suficientes para eventos de bus.")
        return

    event_cols  = ["bus_busrd", "bus_busrdx", "bus_busupd"]
    event_labels = ["BusRd", "BusRdX", "BusUpd"]
    event_colors = {"bus_busrd": "steelblue", "bus_busrdx": "tomato", "bus_busupd": "seagreen"}

    plot_df = df.dropna(subset=["size"]).copy()
    plot_df = (
        plot_df
        .groupby(["workload_model", "protocol", "size"], as_index=False)[event_cols]
        .mean()
    )

    # Series presentes en los datos
    series_keys = [
        (protocol, workload_model)
        for workload_model in WORKLOAD_ORDER
        for protocol in PROTOCOL_ORDER
        if not plot_df[
            (plot_df["protocol"] == protocol) &
            (plot_df["workload_model"] == workload_model)
        ].empty
    ]

    if not series_keys:
        print("[SKIP] Sin series válidas para eventos de bus agrupados.")
        return

    all_sizes = sorted(plot_df["size"].dropna().unique())
    n_sizes   = len(all_sizes)
    n_series  = len(series_keys)
    x         = np.arange(n_sizes)
    width     = 0.8 / max(n_series, 1)

    fig, ax = plt.subplots(figsize=(max(12, n_sizes * n_series * 0.35 + 4), 6))

    for s_idx, (protocol, workload_model) in enumerate(series_keys):
        sub = plot_df[
            (plot_df["protocol"] == protocol) &
            (plot_df["workload_model"] == workload_model)
        ].set_index("size")

        offset = (s_idx - (n_series - 1) / 2) * width
        bottom = np.zeros(n_sizes)
        hatch  = "/" if protocol == "FIREFLY" else ""
        alpha  = 0.80 if protocol == "FIREFLY" else 1.0

        for col in event_cols:
            values = np.array([
                float(sub.loc[sz, col]) if sz in sub.index else 0.0
                for sz in all_sizes
            ])
            ax.bar(
                x + offset, values, bottom=bottom,
                width=width, color=event_colors[col],
                alpha=alpha, hatch=hatch, edgecolor="white", linewidth=0.3,
            )
            bottom += values

    ax.set_title("Eventos de bus (BusRd / BusRdX / BusUpd) - MSI vs FIREFLY - todos los workloads")
    ax.set_xlabel("Instrucciones por PE")
    ax.set_ylabel("Cantidad de transacciones")
    ax.set_xticks(x)
    ax.set_xticklabels([str(int(s)) for s in all_sizes])
    ax.set_yscale("log")
    ax.grid(True, axis="y", linestyle="--", linewidth=0.5)

    # Leyenda compuesta: series + tipos de evento
    series_handles = []
    for (protocol, workload_model) in series_keys:
        hatch  = "/" if protocol == "FIREFLY" else ""
        alpha  = 0.80 if protocol == "FIREFLY" else 1.0
        series_handles.append(
            mpatches.Patch(
                facecolor="gray", alpha=alpha, hatch=hatch,
                label=f"{protocol} - {workload_model}",
            )
        )
    event_handles = [
        mpatches.Patch(facecolor=event_colors[col], label=event_labels[i])
        for i, col in enumerate(event_cols)
    ]
    ax.legend(
        handles=series_handles + event_handles,
        fontsize=7, ncol=2, loc="upper left",
    )

    save_fig(out_dir / "bus_events_all_workloads.png")


def plot_invalidations_updates(df: pd.DataFrame, out_dir: Path) -> None:
    """
    Un único gráfico con las 6 curvas (protocolo × workload) para
    invalidaciones totales, y otro para updates totales.
    """
    if df.empty:
        print("[SKIP] DataFrame vacío para invalidaciones/updates.")
        return

    pairs = []
    if "bus_total_invalidations" in df.columns:
        pairs.append((
            "bus_total_invalidations",
            "Invalidaciones totales",
            "Invalidaciones totales - MSI vs FIREFLY",
            "invalidations_all_workloads.png",
        ))
    if "bus_total_updates" in df.columns:
        pairs.append((
            "bus_total_updates",
            "Updates totales",
            "Updates totales - MSI vs FIREFLY",
            "updates_all_workloads.png",
        ))

    if not pairs:
        print("[SKIP] No hay columnas suficientes para invalidaciones/updates.")
        return

    for metric, ylabel, title, filename in pairs:
        plot_metric_vs_size_all_workloads(
            df=df,
            out_dir=out_dir,
            metric=metric,
            ylabel=ylabel,
            title=title,
            filename=filename,
            yscale="log",
            log_x=True,
        )


# ============================================================
# Gráficas por caché / core
# ============================================================

def plot_cache_per_core(cache_df: pd.DataFrame, batch_df: pd.DataFrame, out_dir: Path) -> None:
    """
    Para cada métrica por core, genera UN ÚNICO gráfico que muestra
    todos los protocolos y workloads juntos, usando el tamaño más grande
    disponible por workload.
    """
    cache_df = attach_batch_metadata(cache_df, batch_df)

    if cache_df.empty:
        print("[SKIP] No hay datos de cache por core.")
        return

    required = ["protocol", "workload_model", "size", "core_id"]
    if any(col not in cache_df.columns for col in required):
        print("[SKIP] Faltan columnas para graficar métricas por cache/core.")
        return

    metrics_info = [
        ("global_miss_rate",        "Miss rate global (%)"),
        ("global_hit_rate",         "Hit rate global (%)"),
        ("invalidations_received",  "Invalidaciones recibidas"),
        ("updates_received",        "Updates recibidos"),
        ("writebacks",              "Writebacks"),
    ]

    for metric, ylabel in metrics_info:
        if metric not in cache_df.columns:
            continue

        # Para cada workload tomamos el tamaño máximo disponible y filtramos.
        frames = []
        for workload_model in WORKLOAD_ORDER:
            wsub = cache_df[
                (cache_df["workload_model"] == workload_model) &
                cache_df["size"].notna()
            ].copy()
            if wsub.empty:
                continue
            max_size = int(wsub["size"].max())
            frames.append(wsub[wsub["size"] == max_size].copy())

        if not frames:
            continue

        plot_data = pd.concat(frames, ignore_index=True)
        plot_data = plot_data.dropna(subset=["core_id", metric])

        all_cores = sorted(plot_data["core_id"].dropna().unique())
        if not all_cores:
            continue

        # Series: protocolo × workload
        series_keys = [
            (protocol, workload_model)
            for workload_model in WORKLOAD_ORDER
            for protocol in PROTOCOL_ORDER
            if not plot_data[
                (plot_data["protocol"] == protocol) &
                (plot_data["workload_model"] == workload_model)
            ].empty
        ]

        if not series_keys:
            continue

        n_cores  = len(all_cores)
        n_series = len(series_keys)
        x        = np.arange(n_cores)
        width    = 0.8 / max(n_series, 1)

        fig, ax = plt.subplots(figsize=(max(10, n_cores * n_series * 0.3 + 3), 6))

        for s_idx, (protocol, workload_model) in enumerate(series_keys):
            sub = plot_data[
                (plot_data["protocol"] == protocol) &
                (plot_data["workload_model"] == workload_model)
            ].sort_values("core_id")

            values = []
            for core in all_cores:
                row = sub[sub["core_id"] == core]
                values.append(float(row[metric].iloc[0]) if not row.empty else 0.0)

            offset = (s_idx - (n_series - 1) / 2) * width
            label  = f"{protocol} - {workload_model}"
            hatch  = "/" if protocol == "FIREFLY" else ""
            ax.bar(x + offset, values, width=width, label=label, hatch=hatch)

        ax.set_title(f"{ylabel} por core - MSI vs FIREFLY - todos los workloads")
        ax.set_xlabel("Core / Caché")
        ax.set_ylabel(ylabel)
        ax.set_xticks(x)
        ax.set_xticklabels([f"Core {int(c)}" for c in all_cores])
        ax.grid(True, axis="y", linestyle="--", linewidth=0.5)
        ax.legend(fontsize=7, ncol=2)

        fname = f"cache_core_{metric}_all_workloads.png"
        save_fig(out_dir / fname)


# ============================================================
# Transiciones de estado
# ============================================================

def normalize_state_columns(state_df: pd.DataFrame) -> pd.DataFrame:
    if state_df.empty:
        return state_df

    df = state_df.copy()
    lower_map = {col: col.lower().strip() for col in df.columns}
    df.rename(columns=lower_map, inplace=True)

    # Posibles nombres alternativos
    rename_candidates = {
        "old": "old_state",
        "prev_state": "old_state",
        "previous_state": "old_state",
        "from_state": "old_state",
        "new": "new_state",
        "next_state": "new_state",
        "to_state": "new_state",
        "core": "core_id",
        "cache": "core_id",
        "cache_id": "core_id",
        "time": "time_ns",
        "timestamp": "time_ns",
    }

    for old, new in rename_candidates.items():
        if old in df.columns and new not in df.columns:
            df.rename(columns={old: new}, inplace=True)

    return df


def plot_state_transitions(state_df: pd.DataFrame, batch_df: pd.DataFrame, out_dir: Path) -> None:
    """
    Genera UN ÚNICO gráfico de barras con todas las combinaciones
    protocolo × workload para el conteo de transiciones de estado.

    El timeline por core se sigue generando por separado (una imagen
    por protocolo × workload) porque mezclarlos en una sola figura
    sería ilegible.
    """
    state_df = normalize_state_columns(state_df)
    state_df = attach_batch_metadata(state_df, batch_df)

    if state_df.empty:
        print("[SKIP] No hay CSV de transiciones de estado.")
        return

    if "protocol" not in state_df.columns or "workload_model" not in state_df.columns:
        print("[SKIP] No se pudo determinar protocol/workload_model para las transiciones.")
        print(f"       Columnas encontradas: {list(state_df.columns)}")
        return

    if "old_state" not in state_df.columns or "new_state" not in state_df.columns:
        print("[SKIP] El CSV de transiciones no tiene old_state/new_state.")
        print(f"       Columnas encontradas: {list(state_df.columns)}")
        return

    state_df = state_df[state_df["protocol"] != "UNKNOWN"].copy()

    if state_df.empty:
        print("[SKIP] Las transiciones no tienen protocol identificable.")
        return

    state_df["transition"] = (
        state_df["old_state"].astype(str) + "→" + state_df["new_state"].astype(str)
    )

    count_df = (
        state_df
        .groupby(["workload_model", "protocol", "transition"], dropna=False)
        .size()
        .reset_index(name="count")
    )

    if count_df.empty:
        print("[SKIP] No hay transiciones para graficar.")
        return

    # ── Gráfico único de conteos ──────────────────────────────────────
    transitions = sorted(count_df["transition"].dropna().unique())
    series_keys = [
        (protocol, workload_model)
        for workload_model in WORKLOAD_ORDER
        for protocol in PROTOCOL_ORDER
        if not count_df[
            (count_df["workload_model"] == workload_model) &
            (count_df["protocol"] == protocol)
        ].empty
    ]

    x     = np.arange(len(transitions))
    width = 0.8 / max(len(series_keys), 1)

    plt.figure(figsize=(max(13, len(transitions) * len(series_keys) * 0.25 + 3), 6))

    for idx, (protocol, workload_model) in enumerate(series_keys):
        sub    = count_df[
            (count_df["workload_model"] == workload_model) &
            (count_df["protocol"] == protocol)
        ]
        values = [
            float(sub.loc[sub["transition"] == tr, "count"].iloc[0])
            if not sub[sub["transition"] == tr].empty else 0.0
            for tr in transitions
        ]
        offset = (idx - (len(series_keys) - 1) / 2) * width
        hatch  = "/" if protocol == "FIREFLY" else ""
        plt.bar(x + offset, values, width=width,
                label=f"{protocol} - {workload_model}", hatch=hatch)

    plt.title("Transiciones de estado de coherencia - MSI vs FIREFLY - todos los workloads")
    plt.xlabel("Transición")
    plt.ylabel("Cantidad")
    plt.xticks(x, transitions, rotation=45, ha="right")
    plt.grid(True, axis="y", linestyle="--", linewidth=0.5)
    plt.legend(fontsize=8, ncol=2)
    save_fig(out_dir / "state_transitions_count_all_workloads.png")

    # ── Timeline por core (se mantiene separado por legibilidad) ─────
    time_col = None
    if "cycle" in state_df.columns:
        time_col = "cycle"
    elif "time_ns" in state_df.columns:
        time_col = "time_ns"

    if time_col is None or "core_id" not in state_df.columns:
        print("[SKIP] No hay cycle/time_ns o core_id para timeline de estados.")
        return

    state_code = {"I": 0, "S": 1, "M": 2, "E": 3, "O": 4, "V": 5}
    state_df["state_value"] = state_df["new_state"].astype(str).map(state_code)

    for workload_model in WORKLOAD_ORDER:
        wsub = state_df[state_df["workload_model"] == workload_model].dropna(subset=["size"])
        if wsub.empty:
            continue
        max_size = int(wsub["size"].max())
        wsub = wsub[wsub["size"] == max_size]

        for protocol in PROTOCOL_ORDER:
            psub = wsub[wsub["protocol"] == protocol].dropna(
                subset=[time_col, "core_id", "state_value"]
            )
            if psub.empty:
                continue

            plt.figure(figsize=(11, 5))
            for core_id in sorted(psub["core_id"].dropna().unique()):
                csub = psub[psub["core_id"] == core_id].sort_values(time_col)
                plt.step(csub[time_col], csub["state_value"],
                         where="post", label=f"Core {int(core_id)}")

            plt.title(f"Timeline de estados - {protocol} - {workload_model} - N={max_size}")
            plt.xlabel("Ciclo" if time_col == "cycle" else "Tiempo (ns)")
            plt.ylabel("Estado")
            plt.yticks(list(state_code.values()), list(state_code.keys()))
            plt.grid(True, linestyle="--", linewidth=0.5)
            plt.legend()
            fname = (
                f"state_timeline_{sanitize_filename(protocol)}"
                f"_{sanitize_filename(workload_model)}_N{max_size}.png"
            )
            save_fig(out_dir / fname)


# ============================================================
# Timeline / bandwidth vs tiempo
# ============================================================

def plot_timeline_bandwidth(timeline_df: pd.DataFrame, batch_df: pd.DataFrame, out_dir: Path) -> None:
    """
    Un único gráfico de bandwidth vs tiempo con todas las combinaciones
    protocolo × workload (usando el tamaño más grande de cada workload).
    """
    timeline_df = attach_batch_metadata(timeline_df, batch_df)

    if timeline_df.empty:
        print("[SKIP] No hay CSV de timeline. No se genera bandwidth vs tiempo.")
        return

    time_col = None
    if "cycle" in timeline_df.columns:
        time_col = "cycle"
    elif "time_ns" in timeline_df.columns:
        time_col = "time_ns"

    if time_col is None:
        print("[SKIP] Timeline no tiene cycle ni time_ns.")
        return

    if "bandwidth_bytes_per_ns" in timeline_df.columns:
        timeline_df["bandwidth_MB_s"] = timeline_df["bandwidth_bytes_per_ns"] * 1000.0
    elif "bandwidth_bytes_per_cycle" in timeline_df.columns:
        timeline_df["bandwidth_MB_s"] = timeline_df["bandwidth_bytes_per_cycle"]
    elif "traffic_bytes" in timeline_df.columns:
        timeline_df["bandwidth_MB_s"] = timeline_df["traffic_bytes"]
    else:
        print("[SKIP] Timeline no tiene bandwidth ni traffic_bytes.")
        return

    plt.figure(figsize=(13, 6))
    any_plotted = False

    for workload_model in WORKLOAD_ORDER:
        wsub = timeline_df[
            (timeline_df["workload_model"] == workload_model) &
            timeline_df["size"].notna()
        ].copy()
        if wsub.empty:
            continue
        max_size = int(wsub["size"].max())
        wsub = wsub[wsub["size"] == max_size]

        for protocol in PROTOCOL_ORDER:
            psub = wsub[wsub["protocol"] == protocol].sort_values(time_col)
            if psub.empty:
                continue

            plt.plot(
                psub[time_col], psub["bandwidth_MB_s"],
                linewidth=1.5,
                linestyle=LINESTYLE_BY_PROTOCOL.get(protocol, "-"),
                label=f"{protocol} - {workload_model} (N={max_size})",
            )
            any_plotted = True

    if not any_plotted:
        plt.close()
        print("[SKIP] Sin datos válidos para timeline de bandwidth.")
        return

    plt.title("Ancho de banda vs tiempo - MSI vs FIREFLY - todos los workloads")
    plt.xlabel("Ciclo" if time_col == "cycle" else "Tiempo (ns)")
    plt.ylabel("Bandwidth aproximado (MB/s)")
    plt.grid(True, linestyle="--", linewidth=0.5)
    plt.legend(fontsize=8)
    save_fig(out_dir / "timeline_bandwidth_all_workloads.png")


# ============================================================
# Ejecución principal
# ============================================================

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Genera gráficas MSI vs FIREFLY desde sim_results."
    )

    parser.add_argument(
        "--results-dir",
        type=Path,
        default=Path("../sim_results"),
        help="Carpeta sim_results.",
    )

    parser.add_argument(
        "--batch-summary",
        type=Path,
        default=None,
        help="Ruta específica a un batch_summary.csv. Si no se indica, usa el más reciente.",
    )

    parser.add_argument(
        "--out-dir",
        type=Path,
        default=None,
        help="Carpeta de salida para gráficas. Por defecto: sim_results/plots/<batch_id_o_latest>",
    )

    args = parser.parse_args()

    results_dir = args.results_dir.resolve()

    if not results_dir.exists():
        raise FileNotFoundError(f"No existe results-dir: {results_dir}")

    data = load_all_data(results_dir, args.batch_summary)

    batch_df = data["batch"]

    if not batch_df.empty and "batch_id" in batch_df.columns:
        batch_id = str(batch_df["batch_id"].iloc[0])
    else:
        batch_id = "latest"

    if args.out_dir is None:
        out_dir = results_dir / "plots" / batch_id
    else:
        out_dir = args.out_dir.resolve()

    ensure_dir(out_dir)

    print("========================================")
    print(" GENERADOR DE GRAFICAS MSI VS FIREFLY")
    print("========================================")
    print(f"sim_results : {results_dir}")
    print(f"plots       : {out_dir}")

    if not batch_df.empty:
        print(f"runs PASS   : {len(batch_df)}")
        print("protocolos  :", sorted(batch_df["protocol"].dropna().unique()))
        print("workloads   :", sorted(batch_df["workload_model"].dropna().unique()))
        print("sizes       :", sorted(batch_df["size"].dropna().astype(int).unique()))
    else:
        print("[WARN] No se encontró batch summary utilizable.")

    print("")

    merged = build_merged_summary(data)

    if merged.empty:
        print("[ERROR] No hay datos consolidados para graficar.")
        return

    # Guardar tabla consolidada para análisis posterior
    consolidated_dir = results_dir / "plots" / batch_id / "consolidated"
    ensure_dir(consolidated_dir)

    consolidated_path = consolidated_dir / f"{batch_id}_merged_summary.csv"
    merged.to_csv(consolidated_path, index=False)
    print(f"[CSV] Consolidado: {consolidated_path}")

    # ========================================================
    # Gráficas principales  (una imagen por métrica)
    # ========================================================

    plot_metric_vs_size_all_workloads(
        df=merged,
        out_dir=out_dir,
        metric="bus_total_bytes",
        ylabel="Tráfico total del bus (bytes)",
        title="Tráfico total del interconnect - MSI vs FIREFLY",
        filename="bus_total_bytes_all_workloads.png",
        yscale="log",
    )

    plot_metric_vs_size_all_workloads(
        df=merged,
        out_dir=out_dir,
        metric="bus_bandwidth_MB_s",
        ylabel="Bandwidth promedio del bus (MB/s)",
        title="Ancho de banda promedio del bus - MSI vs FIREFLY",
        filename="bus_bandwidth_MB_s_all_workloads.png",
    )

    plot_metric_vs_size_all_workloads(
        df=merged,
        out_dir=out_dir,
        metric="bus_total_time_ns",
        ylabel="Tiempo total del bus (ns)",
        title="Tiempo total de ejecución / bus - MSI vs FIREFLY",
        filename="bus_total_time_ns_all_workloads.png",
        yscale="log",
    )

    plot_metric_vs_size_all_workloads(
        df=merged,
        out_dir=out_dir,
        metric="global_hit_rate",
        ylabel="Hit rate global (%)",
        title="Hit rate global - MSI vs FIREFLY",
        filename="global_hit_rate_all_workloads.png",
    )

    plot_metric_vs_size_all_workloads(
        df=merged,
        out_dir=out_dir,
        metric="global_miss_rate",
        ylabel="Miss rate global (%)",
        title="Miss rate global - MSI vs FIREFLY",
        filename="global_miss_rate_all_workloads.png",
    )

    plot_metric_vs_size_all_workloads(
        df=merged,
        out_dir=out_dir,
        metric="total_misses",
        ylabel="Total de misses",
        title="Misses totales - MSI vs FIREFLY",
        filename="total_misses_all_workloads.png",
        yscale="log",
    )

    plot_bus_event_counters_all_workloads(merged, out_dir)

    plot_metric_vs_size_all_workloads(
        df=merged,
        out_dir=out_dir,
        metric="ownership_or_update_rate",
        ylabel="BusRdX/acceso en MSI o BusUpd/acceso en Firefly",
        title="Tasa comparativa de upgrade/update - MSI vs FIREFLY",
        filename="ownership_or_update_rate_all_workloads.png",
    )

    plot_metric_vs_size_all_workloads(
        df=merged,
        out_dir=out_dir,
        metric="invalidations_per_access",
        ylabel="Invalidaciones por acceso",
        title="Tasa de invalidaciones - MSI vs FIREFLY",
        filename="invalidations_per_access_all_workloads.png",
    )

    plot_metric_vs_size_all_workloads(
        df=merged,
        out_dir=out_dir,
        metric="updates_per_access",
        ylabel="Updates por acceso",
        title="Tasa de updates - MSI vs FIREFLY",
        filename="updates_per_access_all_workloads.png",
    )

    plot_state_transition_counts_all_workloads(
        state_df=data["state"],
        batch_df=batch_df,
        out_dir=out_dir,
    )

    # Gráficas agrupadas (un gráfico por tipo, todas las combinaciones adentro)
    plot_bus_events_grouped(merged, out_dir)
    plot_invalidations_updates(merged, out_dir)

    # ========================================================
    # Gráficas por core/cache  (un gráfico por métrica)
    # ========================================================

    plot_cache_per_core(data["cache"], batch_df, out_dir)

    # ========================================================
    # Transiciones de estado
    # ========================================================

    plot_state_transitions(data["state"], batch_df, out_dir)

    # ========================================================
    # Bandwidth vs tiempo
    # ========================================================

    plot_timeline_bandwidth(data["timeline"], batch_df, out_dir)

    print("")
    print("========================================")
    print(" GRAFICAS GENERADAS")
    print("========================================")
    print(f"Salida: {out_dir}")
    print("")
    print("Nota:")
    print("  - Cada gráfica agrupa MSI y FIREFLY para los 3 workloads en una sola imagen.")
    print("  - Bandwidth vs tiempo solo se genera si existen CSV en csv_timeline.")
    print("  - Transiciones de estado solo se grafican si el CSV tiene old_state/new_state.")
    print("  - Los timelines por core se mantienen separados (uno por protocolo×workload).")


if __name__ == "__main__":
    main()