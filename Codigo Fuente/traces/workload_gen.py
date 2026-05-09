#!/usr/bin/env python3
"""
Generador de workloads sintéticos de NUM_LINES líneas.
Mantiene los patrones funcionales de cada caso usando probabilidades.
"""

import csv
import os

# Configuración
NUM_LINES = 1000000
NUM_CORES = 4

def generate_contention_workload(output_file):
    """
    Patrón Contention: Todos los cores acceden a la misma dirección
    con patrones alternados Read/Write.
    
    Patrón actual:
    - Primeras mitades de ciclos: todos leen (R)
    - Segundas mitades de ciclos: todos escriben (W)
    - Dirección fija: 0x00001000
    """
    rows = [['core_id', 'op', 'address']]
    
    cycle = 0
    lines_written = 0
    
    while lines_written < NUM_LINES:
        op = 'R' if (cycle % 2 == 0) else 'W'
        
        for core_id in range(NUM_CORES):
            rows.append([str(core_id), op, '0x00001000'])
            lines_written += 1
            if lines_written >= NUM_LINES:
                break
        
        cycle += 1
    
    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerows(rows)
    
    print(f"✓ {output_file}: {len(rows)-1} líneas generadas")


def generate_migration_workload(output_file):
    """
    Patrón Migration: Escrituras que rotan entre cores secuencialmente.
    
    Patrón actual:
    - Línea i: core (i % 4) escribe
    - Dirección fija: 0x00003000
    - Simula migración de datos entre cachés
    """
    rows = [['core_id', 'op', 'address']]
    
    for line_idx in range(NUM_LINES):
        core_id = line_idx % NUM_CORES
        rows.append([str(core_id), 'W', '0x00003000'])
    
    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerows(rows)
    
    print(f"✓ {output_file}: {len(rows)-1} líneas generadas")


def generate_prodcons_workload(output_file):
    """
    Patrón Producer-Consumer: Dos productores (cores 0,1) escriben,
    dos consumidores (cores 2,3) leen.
    
    Patrón actual:
    - Líneas pares: cores 0,1 escriben (productores)
    - Líneas impares: cores 2,3 leen (consumidores)
    - Dirección fija: 0x00002000
    """
    rows = [['core_id', 'op', 'address']]
    
    cycle = 0
    lines_written = 0
    
    while lines_written < NUM_LINES:
        if cycle % 2 == 0:
            # Ciclo par: productores escriben
            for core_id in [0, 1]:
                rows.append([str(core_id), 'W', '0x00002000'])
                lines_written += 1
                if lines_written >= NUM_LINES:
                    break
        else:
            # Ciclo impar: consumidores leen
            for core_id in [2, 3]:
                rows.append([str(core_id), 'R', '0x00002000'])
                lines_written += 1
                if lines_written >= NUM_LINES:
                    break
        
        cycle += 1
    
    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerows(rows)
    
    print(f"✓ {output_file}: {len(rows)-1} líneas generadas")


def main():
    """Genera los tres workloads de NUM_LINES líneas."""
    traces_dir = os.path.dirname(os.path.abspath(__file__))
    
    print("=" * 60)
    print(f"Generador de Workloads Sintéticos ({NUM_LINES} líneas)")
    print("=" * 60)
    
    # Contention: todos a la misma dirección, patrones alternados
    contention_file = os.path.join(traces_dir, f'workload_contention_{NUM_LINES}.csv')
    generate_contention_workload(contention_file)
    
    # Migration: escrituras que rotan entre cores
    migration_file = os.path.join(traces_dir, f'workload_migration_{NUM_LINES}.csv')
    generate_migration_workload(migration_file)
    
    # Producer-Consumer: productores escriben, consumidores leen
    prodcons_file = os.path.join(traces_dir, f'workload_prod-cons_{NUM_LINES}.csv')
    generate_prodcons_workload(prodcons_file)
    
    print("=" * 60)
    print(f"Total de líneas por workload: {NUM_LINES}")
    print("=" * 60)


if __name__ == '__main__':
    main()
