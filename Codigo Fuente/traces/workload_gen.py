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
import random
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

    if n_inst <= 10:
        raise ValueError("N_inst debe ser mayor que 10 para generar un workload representativo")

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

    Además del patrón normal de contención, este generador inserta
    obligatoriamente al menos una sección donde uno o más PEs mantienen
    ownership en estado Modified sobre direcciones distintas.

    Secuencia mínima garantizada para estado M:
        W, W, R, W, R

    La sección de estado M:
    - Tiene longitud mínima 5.
    - Tiene longitud máxima 20.
    - Puede aparecer más de una vez.
    - Usa direcciones distintas entre PEs activos para evitar interferencia.
    - Mientras un PE está trabajando una dirección en M, los otros PEs usan
      otras direcciones disponibles.
    """

    if n_inst < 10:
        raise ValueError("N_inst debe ser mayor o igual que 10 para generar secciones en estado M")

    if cores <= 0:
        raise ValueError("La cantidad de cores debe ser mayor que cero")

    workload_name = "workload_contention"

    # Matriz temporal:
    # traces[pe_id][inst_idx] = [op, address]
    traces = [[] for _ in range(cores)]

    # ------------------------------------------------------------
    # 1. Generación base: alta contención compartida
    # ------------------------------------------------------------
    for inst_idx in range(n_inst):
        address = address_by_block(
            inst_idx=inst_idx,
            block_size=32,
            offset=0
        )

        for pe_id in range(cores):
            if (inst_idx + pe_id) % 3 == 0:
                op = "W"
            else:
                op = "R"

            traces[pe_id].append([op, address])

    # ------------------------------------------------------------
    # 2. Inserción obligatoria de al menos una sección Modified
    # ------------------------------------------------------------
    min_m_len = 5
    max_m_len = min(20, n_inst)

    m_section_len = random.randint(min_m_len, max_m_len)

    # Debe caber dentro del workload
    start_idx = random.randint(0, n_inst - m_section_len)

    # Cantidad de PEs que tendrán sección M simultánea.
    # Limitada por cantidad de cores y cantidad de direcciones.
    max_active_modified = min(cores, len(ADDR_POOL))

    # Al menos un PE debe tener sección M.
    active_modified_count = random.randint(1, max_active_modified)

    active_pes = random.sample(range(cores), active_modified_count)
    active_addresses = random.sample(ADDR_POOL, active_modified_count)

    pe_to_m_address = {
        pe_id: active_addresses[idx]
        for idx, pe_id in enumerate(active_pes)
    }

    # Direcciones auxiliares para PEs que no están en la sección M.
    # Si no quedan direcciones libres, usan cualquier dirección distinta
    # cuando sea posible.
    used_m_addresses = set(active_addresses)
    free_addresses = [addr for addr in ADDR_POOL if addr not in used_m_addresses]

    # Secuencia mínima obligatoria para garantizar hits en Modified:
    # Primera W: obtiene M con BusRdX.
    # Segunda W: hit en M.
    # R: hit en M.
    # Tercera W: hit en M.
    # R: hit en M.
    base_m_sequence = ["W", "W", "R", "W", "R"]

    # Si la sección es más larga, se extiende con R/W aleatorios,
    # pero favoreciendo escrituras para observar write hits en M.
    extra_len = m_section_len - len(base_m_sequence)
    extra_ops = random.choices(
        population=["W", "R"],
        weights=[0.60, 0.40],
        k=extra_len
    )

    m_sequence = base_m_sequence + extra_ops

    for local_idx, op in enumerate(m_sequence):
        inst_idx = start_idx + local_idx

        for pe_id in range(cores):
            if pe_id in pe_to_m_address:
                # Este PE mantiene ownership en su dirección privada
                # durante la sección M.
                traces[pe_id][inst_idx] = [op, pe_to_m_address[pe_id]]
            else:
                # Los demás PEs se mandan a otras direcciones para no invalidar
                # la línea del PE que está en estado M.
                if free_addresses:
                    other_address = random.choice(free_addresses)
                else:
                    # Si todas las direcciones están ocupadas por secciones M,
                    # usa una dirección de ADDR_POOL intentando variar.
                    other_address = ADDR_POOL[(pe_id + local_idx) % len(ADDR_POOL)]

                other_op = random.choice(["R", "W"])
                traces[pe_id][inst_idx] = [other_op, other_address]

    # ------------------------------------------------------------
    # 3. Inserción opcional de más secciones Modified
    # ------------------------------------------------------------
    # Para workloads grandes, puede insertar secciones extra.
    # No es obligatorio, pero ayuda a observar más write hits en M.
    optional_sections = 0

    if n_inst >= 50:
        optional_sections = random.randint(0, max(1, n_inst // 200))

    for _ in range(optional_sections):
        m_section_len = random.randint(min_m_len, max_m_len)
        start_idx = random.randint(0, n_inst - m_section_len)

        active_modified_count = random.randint(1, max_active_modified)
        active_pes = random.sample(range(cores), active_modified_count)
        active_addresses = random.sample(ADDR_POOL, active_modified_count)

        pe_to_m_address = {
            pe_id: active_addresses[idx]
            for idx, pe_id in enumerate(active_pes)
        }

        used_m_addresses = set(active_addresses)
        free_addresses = [addr for addr in ADDR_POOL if addr not in used_m_addresses]

        extra_len = m_section_len - len(base_m_sequence)
        extra_ops = random.choices(
            population=["W", "R"],
            weights=[0.60, 0.40],
            k=extra_len
        )

        m_sequence = base_m_sequence + extra_ops

        for local_idx, op in enumerate(m_sequence):
            inst_idx = start_idx + local_idx

            for pe_id in range(cores):
                if pe_id in pe_to_m_address:
                    traces[pe_id][inst_idx] = [op, pe_to_m_address[pe_id]]
                else:
                    if free_addresses:
                        other_address = random.choice(free_addresses)
                    else:
                        other_address = ADDR_POOL[(pe_id + local_idx) % len(ADDR_POOL)]

                    other_op = random.choice(["R", "W"])
                    traces[pe_id][inst_idx] = [other_op, other_address]

    # ------------------------------------------------------------
    # 4. Escritura de archivos CSV por PE
    # ------------------------------------------------------------
    for pe_id in range(cores):
        output_file = outdir / f"{workload_name}_{n_inst}_PE{pe_id}.csv"

        with open(output_file, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["op", "address"])

            for op, address in traces[pe_id]:
                write_row(writer, op, address)

        print(f"✓ {output_file}")

    print(
        f"[contention] Sección M obligatoria: "
        f"start={start_idx}, len={m_section_len}, "
        f"active_pes={active_pes}, addresses={active_addresses}"
    )

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

    # Una única dirección compartida para productores y consumidores.
    # Se escoge una vez por generación del workload.
    shared_address = random.choice(ADDR_POOL)

    for pe_id in range(cores):
        output_file = outdir / f"{workload_name}_{n_inst}_PE{pe_id}.csv"

        with open(output_file, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["op", "address"])

            for inst_idx in range(n_inst):
                address = shared_address

                if pe_id in producers:
                    op = "W"
                else:
                    op = "R"

                write_row(writer, op, address)

        print(f"✓ {output_file}")

    print(f"[prod-cons] Dirección compartida usada por productores y consumidores: {shared_address}")

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