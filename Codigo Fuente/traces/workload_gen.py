#!/usr/bin/env python3
"""
Generador de workloads sintéticos de 10k líneas.
Mantiene los patrones funcionales de cada caso usando probabilidades.
"""

import csv
import os

# Configuración
NUM_LINES = 10000
NUM_CORES = 4

def generate_contention_workload(output_file):
    """
    Patrón Contention: Todos los cores acceden a la misma dirección
    con patrones alternados Read/Write.
    
    Patrón actual:
    - Ciclos pares (0,2,4...): todos leen (R)
    - Ciclos impares (1,3,5...): todos escriben (W)
    - Dirección fija: 0x00001000
    """
    rows = [['cycle', 'core_id', 'op', 'address']]
    
    cycle = 0
    lines_written = 0
    
    while lines_written < NUM_LINES:
        op = 'R' if (cycle % 2 == 0) else 'W'
        
        for core_id in range(NUM_CORES):
            rows.append([str(cycle), str(core_id), op, '0x00001000'])
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
    - Ciclo i: core (i % 4) escribe
    - Dirección fija: 0x00003000
    - Simula migración de datos entre cachés
    """
    rows = [['cycle', 'core_id', 'op', 'address']]
    
    for cycle in range(NUM_LINES):
        core_id = cycle % NUM_CORES
        rows.append([str(cycle), str(core_id), 'W', '0x00003000'])
    
    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerows(rows)
    
    print(f"✓ {output_file}: {len(rows)-1} líneas generadas")


def generate_prodcons_workload(output_file):
    """
    Patrón Producer-Consumer: Dos productores (cores 0,1) escriben,
    dos consumidores (cores 2,3) leen.
    
    Patrón actual:
    - Ciclos 0,2,4... (pares): cores 0,1 escriben (productores)
    - Ciclos 1,3,5... (impares): cores 2,3 leen (consumidores)
    - Dirección fija: 0x00002000
    """
    rows = [['cycle', 'core_id', 'op', 'address']]
    
    cycle = 0
    lines_written = 0
    
    while lines_written < NUM_LINES:
        if cycle % 2 == 0:
            # Ciclo par: productores escriben
            for core_id in [0, 1]:
                rows.append([str(cycle), str(core_id), 'W', '0x00002000'])
                lines_written += 1
                if lines_written >= NUM_LINES:
                    break
        else:
            # Ciclo impar: consumidores leen
            for core_id in [2, 3]:
                rows.append([str(cycle), str(core_id), 'R', '0x00002000'])
                lines_written += 1
                if lines_written >= NUM_LINES:
                    break
        
        cycle += 1
    
    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerows(rows)
    
    print(f"✓ {output_file}: {len(rows)-1} líneas generadas")


def main():
    """Genera los tres workloads de 10k líneas."""
    traces_dir = os.path.dirname(os.path.abspath(__file__))
    
    print("=" * 60)
    print("Generador de Workloads Sintéticos (10k líneas)")
    print("=" * 60)
    
    # Contention: todos a la misma dirección, patrones alternados
    contention_file = os.path.join(traces_dir, 'workload_contention_10k.csv')
    generate_contention_workload(contention_file)
    
    # Migration: escrituras que rotan entre cores
    migration_file = os.path.join(traces_dir, 'workload_migration_10k.csv')
    generate_migration_workload(migration_file)
    
    # Producer-Consumer: productores escriben, consumidores leen
    prodcons_file = os.path.join(traces_dir, 'workload_prod-cons_10k.csv')
    generate_prodcons_workload(prodcons_file)
    
    print("=" * 60)
    print(f"Total de líneas por workload: {NUM_LINES}")
    print("=" * 60)


if __name__ == '__main__':
    main()
