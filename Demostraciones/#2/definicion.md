# DEFINICIONES FINALES DEL SISTEMA (cerradas)

## 1. Formato de transacciones del bus

### Definición

```text
BusRequest {
    type        // BusRd | BusRdX | BusUpd
    address     // 32 bits
    src_core_id // 0–3
}
```

```text
BusEvent {
    type
    address
    src_core_id
}
```

---

### ¿Por qué así?

* `type` -> define comportamiento (coherencia)
* `address` -> todas las caches deben comparar tags
* `src_core_id` -> evita auto-reaccionar a tu propio evento

---

### Cómo se usa en el proyecto

* Core -> Cache -> genera `BusRequest`
* Bus -> ejecuta -> genera `BusEvent` (broadcast)
* Todas las caches hacen snooping sobre `BusEvent`

---

## 2. Política de reemplazo (cache)

### Definición

```text
Direct-mapped:

Si llega un bloque a una línea ocupada:
    Si estado == M:
        write-back a memoria
    Reemplazar línea
```

---

### ¿Por qué así?

* Es obligatorio en write-back
* Si no se hace -> se pierden datos correctos
* Activa tráfico realista hacia memoria

---

### En nuestro modelo

Esto ocurre en:

* miss por conflicto
* workloads con alta contención

Esto afecta directamente métricas

---

## 3. Medición de latencia

### Definición

```text
Inicio: cuando el core emite PrRd o PrWr
Fin: cuando el dato está disponible en caché
```

---

### ¿Por qué así?

* Es lo que realmente percibe el core
* Permite comparar MSI vs Firefly correctamente

---

### Implementación

```text
on access:
    start_cycle = current_cycle

cuando termina:
    latency = current_cycle - start_cycle
    total_latency += latency
    total_accesses++
```

---

## 4. Orden de eventos del bus

### Definición formal

```text
1. Core genera request (PrRd / PrWr)
2. Cache decide -> hit o miss
3. Si miss -> genera BusRequest
4. Bus recibe y encola (FIFO)
5. Arbitraje round-robin selecciona request
6. Bus ejecuta transacción
7. Se hace broadcast (BusEvent)
8. Todas las caches hacen snooping
9. Si aplica -> write-back
10. Memoria responde (si es BusRd / BusRdX)
11. Cache original recibe dato y completa operación
```

---

### ¿Por qué este orden?

* Garantiza consistencia global
* Evita estados inválidos simultáneos
* Es compatible con snooping real

---

## 5. Identificación de cores

### Definición

```text
Core IDs:
Core0, Core1, Core2, Core3
```

---

### ¿Por qué?

* Necesario para:

  * arbitraje
  * métricas
  * evitar reaccionar a eventos propios

---

### Uso

* Bus usa `src_core_id`
* Monitor agrupa métricas por core

---

## 6. Nivel de modelado

### Definición

```text
NO se modelan datos reales
Solo direcciones
```

---

### ¿Por qué?

* El objetivo es coherencia, no valores
* Simplifica muchísimo:

  * Firefly (BusUpd)
  * write-back
  * comparaciones

---

### En la práctica

* CacheLine:

```text
tag
state
(no data real)
```

---

### Analogía

No importa *qué dice el documento*
Solo importa *quién tiene la versión válida*

---
