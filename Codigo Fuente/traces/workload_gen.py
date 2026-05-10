#!/usr/bin/env python3
"""
Generador de workloads sintéticos por PE.

Lee un archivo workload.config con:

N_inst=1000000
Cores=4

Genera archivos CSV sin columna cycle y sin core_id, porque cada archivo
corresponde a un PE específico.

Formato de cada CSV:

op,address
R,0x00001000
W,0x00001000

Workloads generados:

1. Contention:
   workload_contention_N_PE0.csv
   workload_contention_N_PE1.csv
   ...

2. Migration:
   workload_migration_N_PE0.csv
   workload_migration_N_PE1.csv
   ...

3. Producer-Consumer:
   workload_prod-cons_N_PE0.csv
   workload_prod-cons_N_PE1.csv
   ...
"""

import csv
import os
import argparse
from pathlib import Path


# Direcciones cacheables compartidas usadas por los workloads.
# Se cambian por bloques para mantener localidad temporal y coherencia lógica.
ADDR_POOL = [
    "0x00001000",
    "0x00002000",
    "0x00003000",
]


def read_config(config_path):
    """
    Lee workload.config.

    Formatos válidos:
        N_inst=1000000
        Cores=4

    También:
        N_inst: 1000000
        Cores: 4
    """

    config = {}

    with open(config_path, "r", encoding="utf-8") as f:
        for line_number, line in enumerate(f, start=1):
            line = line.strip()

            # Ignorar líneas vacías y comentarios
            if not line or line.startswith("#"):
                continue

            # Permitir comentarios al final de línea
            line = line.split("#", 1)[0].strip()

            if "=" in line:
                key, value = line.split("=", 1)
            elif ":" in line:
                key, value = line.split(":", 1)
            else:
                raise ValueError(
                    f"Error en workload.config línea {line_number}: "
                    f"se esperaba formato clave=valor o clave:valor"
                )

            key = key.strip()
            value = value.strip()

            config[key] = value

    if "N_inst" not in config:
        raise ValueError("Falta N_inst en workload.config")

    if "Cores" not in config:
        raise ValueError("Falta Cores en workload.config")

    n_inst = int(config["N_inst"].replace("_", ""))
    cores = int(config["Cores"].replace("_", ""))

    if n_inst <= 0:
        raise ValueError("N_inst debe ser mayor que cero")

    if cores <= 0:
        raise ValueError("Cores debe ser mayor que cero")

    return n_inst, cores


def address_by_block(inst_idx, block_size, offset=0):
    """
    Selecciona una dirección de ADDR_POOL por bloques.

    No cambia la dirección en cada instrucción individual, porque eso eliminaría
    parte de la localidad temporal. Al cambiar por bloques, se generan hits,
    misses y eventos de coherencia de forma más representativa.
    """

    block_idx = inst_idx // block_size
    addr_idx = (block_idx + offset) % len(ADDR_POOL)

    return ADDR_POOL[addr_idx]


def write_row(writer, op, address):
    """
    Escribe una instrucción en el CSV.

    El formato final es:
        op,address
    """

    writer.writerow([op, address])


def generate_contention_workload(outdir, n_inst, cores):
    """
    Workload 4.1:
    Variable compartida con alta contención.

    Lógica:
    - Todos los PEs acceden a la misma dirección cacheable compartida.
    - Cada PE ejecuta lecturas y escrituras frecuentes.
    - La dirección cambia por bloques entre 0x1000, 0x2000 y 0x3000.
    - Se fuerza contención porque todos los PEs usan la misma dirección
      durante el mismo bloque lógico.

    Patrón:
    - Aproximadamente 2/3 lecturas.
    - Aproximadamente 1/3 escrituras.
    - Las escrituras se desfasan por PE para provocar invalidaciones
      o actualizaciones frecuentes.
    """

    workload_name = "workload_contention"

    for pe_id in range(cores):
        output_file = outdir / f"{workload_name}_{n_inst}_PE{pe_id}.csv"

        with open(output_file, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["op", "address"])

            for inst_idx in range(n_inst):
                address = address_by_block(
                    inst_idx=inst_idx,
                    block_size=32,
                    offset=0
                )

                # Patrón de alta contención:
                # Cada PE alterna lecturas y escrituras, pero no todos escriben
                # exactamente en la misma posición. Esto genera tráfico coherente.
                if (inst_idx + pe_id) % 3 == 0:
                    op = "W"
                else:
                    op = "R"

                write_row(writer, op, address)

        print(f"✓ {output_file}")


def generate_prodcons_workload(outdir, n_inst, cores):
    """
    Workload 4.2:
    Productor-consumidor multicore.

    Lógica:
    - PE0 y PE1 son productores.
    - PE2 y PE3 son consumidores.
    - Los productores escriben en el buffer compartido.
    - Los consumidores leen del mismo buffer compartido.
    - Todos los accesos son a memoria cacheable compartida.
    - La dirección del buffer cambia por bloques para probar varias líneas.

    Si Cores > 4:
    - PE0 y PE1 siguen siendo productores.
    - PE2, PE3 y los demás PEs se comportan como consumidores.

    Si Cores < 4:
    - Se genera error, porque el patrón solicitado necesita al menos 4 PEs.
    """

    if cores < 4:
        raise ValueError(
            "El workload producer-consumer requiere al menos 4 cores: "
            "PE0, PE1 productores y PE2, PE3 consumidores."
        )

    workload_name = "workload_prod-cons"

    producers = {0, 1}

    for pe_id in range(cores):
        output_file = outdir / f"{workload_name}_{n_inst}_PE{pe_id}.csv"

        with open(output_file, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["op", "address"])

            for inst_idx in range(n_inst):
                address = address_by_block(
                    inst_idx=inst_idx,
                    block_size=16,
                    offset=1
                )

                if pe_id in producers:
                    op = "W"
                else:
                    op = "R"

                write_row(writer, op, address)

        print(f"✓ {output_file}")


def generate_migration_workload(outdir, n_inst, cores):
    """
    Workload 4.3:
    Migración de ownership.

    Lógica:
    - Una misma dirección cacheable compartida es escrita de forma alternada.
    - En la posición lógica i, escribe PE(i % Cores).
    - Los demás PEs leen esa misma dirección.

    Esto permite representar:

        PE0 escribe
        PE1 escribe
        PE2 escribe
        PE3 escribe
        PE0 escribe
        ...

    Como ya no existe columna cycle, la posición de línea dentro de cada archivo
    funciona como una posición lógica de ejecución si el testbench consume las
    trazas de todos los PEs en paralelo.

    No se usan NOPs para mantener compatibilidad con trazas que solo aceptan R/W.
    """

    workload_name = "workload_migration"

    for pe_id in range(cores):
        output_file = outdir / f"{workload_name}_{n_inst}_PE{pe_id}.csv"

        with open(output_file, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["op", "address"])

            for inst_idx in range(n_inst):
                address = address_by_block(
                    inst_idx=inst_idx,
                    block_size=cores * 8,
                    offset=2
                )

                active_writer = inst_idx % cores

                if pe_id == active_writer:
                    op = "W"
                else:
                    op = "R"

                write_row(writer, op, address)

        print(f"✓ {output_file}")


def main():
    parser = argparse.ArgumentParser(
        description="Generador de workloads por PE usando workload.config"
    )

    parser.add_argument(
        "-c",
        "--config",
        default="workload.config",
        help="Archivo de configuración. Default: workload.config"
    )

    parser.add_argument(
        "-o",
        "--outdir",
        default="traces_gen",
        help="Directorio de salida. Default: traces_gen"
    )

    args = parser.parse_args()

    script_dir = Path(__file__).resolve().parent

    config_path = Path(args.config)
    if not config_path.is_absolute():
        config_path = script_dir / config_path

    outdir = outdir = config_path.parent / args.outdir

    if not config_path.exists():
        raise FileNotFoundError(f"No existe el archivo de configuración: {config_path}")

    outdir.mkdir(parents=True, exist_ok=True)

    n_inst, cores = read_config(config_path)

    print("=" * 70)
    print("Generador de workloads sintéticos por PE")
    print("=" * 70)
    print(f"N_inst : {n_inst}")
    print(f"Cores  : {cores}")
    print(f"Outdir : {outdir.resolve()}")
    print("=" * 70)

    generate_contention_workload(outdir, n_inst, cores)
    generate_prodcons_workload(outdir, n_inst, cores)
    generate_migration_workload(outdir, n_inst, cores)

    print("=" * 70)
    print("Workloads generados correctamente.")
    print("=" * 70)


if __name__ == "__main__":
    main()