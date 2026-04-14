# Explicaciones clave – Demostración 2

Este documento resume y aclara los conceptos más importantes del proyecto, con explicaciones simples, analogías y cómo se aplican directamente en la implementación.

---

## 1. Política de escritura: Write-back + Write-allocate

### ¿Qué es?

**Write-back:**
Cuando se escribe en caché:

- NO se actualiza memoria inmediatamente
- La línea se marca como **Modified (M)**
- La memoria se actualiza solo cuando esa línea se reemplaza o se pierde

**Write-allocate:**
Cuando ocurre un write miss:

- Primero se trae el bloque a caché
- Luego se realiza la escritura en caché

En otras palabras: si vas a escribir, ese dato “merece estar en caché”

---

### ¿Cómo se aplica en el proyecto?

Esto es clave porque:

- Genera estados **M**, que son esenciales para coherencia
- Hace que existan datos “sucios” (diferentes a memoria)
- Obliga a hacer **write-back** cuando otros cores acceden

Sin esto, los protocolos MSI y Firefly no generan comportamiento interesante

---

### Analogía

- Caché = cuaderno personal  
- Memoria = documento oficial  

Write-back:
> Escribes en tu cuaderno y NO actualizas el documento oficial inmediatamente  

Write-allocate:
> Antes de editar algo, lo copias a tu cuaderno  

---

## 2. Líneas de caché

### ¿Qué son?

La caché no guarda bytes individuales, sino bloques llamados **líneas de caché**.

Una línea = un bloque completo (ej: 32 bytes)

---

### ¿Cómo se calculan?

- Caché: 2048 bytes  
- Bloque: 32 bytes  

```text
líneas = 2048 / 32 = 64
```

---

### ¿Cómo se aplica en el proyecto?

Cada caché tiene:

- 64 líneas
- Cada línea contiene:

  - Tag
  - Estado (M/S/I)
  - Datos

---

### Analogía

- Caché = estantería
- Línea = cajón

Cada cajón guarda un bloque completo, no pedacitos

---

## 3. Dirección: Tag, Index y Offset

### ¿Qué son?

La dirección se divide así:

```text
| TAG | INDEX | OFFSET |
```

---

### Offset (5 bits)

- Indica el byte dentro del bloque
- 32 bytes → 2⁵ = 32

No afecta coherencia

---

### Index (6 bits)

- Indica qué línea usar
- 64 líneas → 2⁶ = 64

---

### Tag (21 bits)

- Identifica qué bloque está en esa línea

---

### ¿Cómo se usa?

Cuando se hace `read(addr)`:

1. Se saca el index -> se va a la línea
2. Se compara el tag:

   - Igual -> HIT
   - Diferente -> MISS

---

### Analogía

Dirección como dirección de casa:

- Tag = ciudad
- Index = calle
- Offset = número

---

## 4. Arbitraje del bus

### ¿Qué es?

Cuando varios cores quieren usar el bus al mismo tiempo:

alguien decide quién pasa primero

---

### ¿Cómo se aplica?

- 4 cores compiten
- El bus solo atiende 1 a la vez

---

### Analogía

Puente de un solo carril:

> varios carros -> alguien organiza el paso

---

## 5. Round-robin

### ¿Cómo funciona?

Turnos rotativos:

```text
Core0 -> Core1 -> Core2 -> Core3 -> ...
```

---

### ¿Por qué usarlo?

- Evita que un core monopolice el bus
- Todos tienen oportunidad justa

---

### Analogía

Como una ronda para hablar en grupo

---

## 6. Modelos de bus

### Tipos comunes

- Bus bloqueante (el nuestro)
- Bus pipelined
- Crossbar
- Network-on-Chip

---

### ¿Por qué usamos bus simple?

Porque el enfoque es coherencia, no interconnect complejo

---

## 7. ¿Qué se transmite en el bus?

No solo datos, también:

- Tipo de operación (BusRd, etc)
- Dirección
- Señales de control

---

### Ejemplo

```text
BusRd(addr=0x1000)
```

Todas las cachés lo ven y reaccionan

---

### Analogía

Como gritar en una sala:

> “¡Alguien quiere leer X!”

---

## 8. Eventos del sistema

### Procesador

- **PrRd**: el core quiere leer
- **PrWr**: el core quiere escribir

---

### Bus

- **BusRd**: alguien quiere leer
- **BusRdX**: alguien quiere escribir con exclusividad
- **BusUpd**: alguien actualiza el dato

---

### ¿Cómo se conectan?

- Core -> genera PrRd/PrWr
- Cache -> decide hit/miss
- Si hay miss -> genera evento de bus

---

### Analogía

- PrRd = “quiero leer”
- BusRd = “alguien pidió el dato”
- BusUpd = “nuevo dato para todos”

---

## 9. Protocolo MSI (intuición)

### Idea principal

Si alguien escribe -> los demás pierden su copia

---

### Casos clave

- I + PrRd → BusRd → S
- I + PrWr → BusRdX → M
- S + PrWr → BusRdX → M
- M + BusRd → write-back → S

---

### Analogía

> “Si alguien edita el documento, todos los demás pierden su copia”

---

## 10. Protocolo Firefly (intuición)

### Idea principal

Si alguien escribe -> todos actualizan su copia

---

### Caso clave

S + PrWr:

- MSI -> invalidación
- Firefly -> BusUpd

---

### Resultado

- Nadie pierde el dato
- Todos siguen sincronizados

---

### Analogía

> Documento compartido que se actualiza en tiempo real

---

## 11. MSI vs MESI

### ¿Qué agrega MESI?

Estado **E (Exclusive)**:

“solo yo tengo el dato”

---

### Ventaja

Puedes escribir sin usar el bus

---

### ¿Por qué no usarlo?

- Más complejidad
- No necesario para comparar MSI vs Firefly

---

## 12. Snooping

### ¿Qué es?

Todas las cachés:

escuchan el bus constantemente

---

### ¿Para qué sirve?

- Detectar accesos de otros cores
- Mantener coherencia

---

### Analogía

Escuchar conversaciones:

> si dicen tu nombre -> reaccionas

---

## 13. Transacciones del bus

### Tipos

- BusRd -> leer
- BusRdX -> leer + invalidar
- BusUpd -> actualizar

---

### Flujo típico

1. Core hace PrWr
2. Cache genera BusRdX
3. Bus lo transmite
4. Otras caches reaccionan

---

### BusRdX (importante)

Hace dos cosas:

- Trae el dato
- Invalida a los demás

---

### Analogía

> “Quiero el documento y nadie más puede tenerlo”

---

## 14. Write-back en memoria

### Idea clave

Si estás en M:

tienes la única copia correcta

---

### ¿Cuándo ocurre?

- Otro core hace BusRd
- Otro core hace BusRdX
- Se reemplaza la línea

---

### Ejemplo

```text
M -> BusRd -> write-back -> S
M -> BusRdX -> write-back -> I
```

---

### Analogía

Antes de borrar tu archivo:

> lo guardas en el servidor

---

## 15. Tráfico en el bus

### ¿Cómo medirlo?

Contar:

- BusRd
- BusRdX
- BusUpd

---

### Implementación

```c
bus_rd_count++;
bus_rdx_count++;
bus_upd_count++;
```

---

### Total

```text
Total = suma de todos
```

---

## 16. Latencia promedio

### ¿Qué es?

Tiempo promedio por acceso

---

### Valores

- Hit → 1 ciclo
- Miss → ~24 ciclos

---

### Implementación

```c
total_latency += latency;
total_accesses++;
```

```text
latencia promedio = total_latency / total_accesses
```

---

## 17. Firefly: por qué S no cambia a M o I

### Idea clave

Firefly = write-update

---

### En estado S

- Todos tienen copia válida
- Si escribes -> haces BusUpd
- Todos actualizan

---

### Resultado

- Nadie pierde la copia
- No necesitas M ni I

---

### Analogía

Google Docs:

- MSI -> borras copias
- Firefly -> todos ven la actualización

---

---

## 18. Explicación completa de transiciones – Protocolo MSI

En MSI, la idea fundamental es:

*si alguien quiere escribir, debe tener exclusividad*  
*eso implica invalidar a los demás*

---

### Transiciones del procesador

---

#### I + PrRd -> BusRd -> S

No tienes el dato (Invalid).

- Se genera un **BusRd**
- Se trae el bloque desde memoria
- Pasas a **Shared**

En el proyecto:

- Esto es un **read miss**
- Activa tráfico en el bus

Analogía:
> “No tengo el documento -> lo pido”

---

#### I + PrWr -> BusRdX -> M

No tienes el dato y quieres escribir.

- Generas **BusRdX**
- Traes el dato
- Invalidas a los demás
- Pasas a **Modified**

En el proyecto:

- Esto genera bastante tráfico
- Es clave para coherencia

Analogía:
> “Quiero editar -> tráiganme el documento y borren las copias de otros”

---

#### S + PrRd -> Hit

Ya tienes una copia válida.

- No hay tráfico
- Te quedas en S

Analogía:
> “Ya tengo el documento, solo lo leo”

---

#### S + PrWr -> BusRdX -> M

Tienes copia compartida, pero quieres escribir.

- Necesitas exclusividad
- Generas **BusRdX**
- Invalidas a otros
- Pasas a **M**

Analogía:
> “Todos tienen copia -> voy a editar -> borro las demás”

---

#### M + PrRd / PrWr -> Hit

Ya eres el único dueño.

- No hay tráfico
- Todo es local

Analogía:
> “El documento es solo tuyo -> haces lo que quieras”

---

### Snooping (eventos del bus)

---

#### S + BusRd -> S

Otro core quiere leer.

- No pasa nada
- Sigues compartiendo

---

#### S + BusRdX -> I

Otro core quiere escribir.

- Pierdes tu copia
- Pasas a Invalid

Analogía:
> “Alguien va a modificar -> tu copia ya no sirve”

---

#### M + BusRd -> Write-back -> S

Otro core quiere leer un dato que tú modificaste.

- Debes escribir a memoria (write-back)
- Ahora el dato se comparte
- Pasas a S

Analogía:
> “Tú tenías la versión más reciente -> la publicas para todos”

---

#### M + BusRdX -> Write-back -> I

Otro core quiere escribir.

- Haces write-back
- Pierdes la propiedad
- Pasas a I

Analogía:
> “Te quitan el control del documento”

---

## 19. Explicación completa de transiciones – Protocolo Firefly

En Firefly, la idea es diferente:

*si alguien escribe, los demás NO pierden la copia*  
*todos se actualizan*

---

### Transiciones del procesador

---

#### I + PrRd -> BusRd -> S

Igual que MSI.

- No tienes el dato
- Lo pides
- Pasas a S

---

#### I + PrWr -> BusRd -> M

No tienes el dato y quieres escribir.

- Haces BusRd (no BusRdX)
- Traes el dato
- Pasas a M

Diferencia clave:
- No invalidas a nadie

---

#### S + PrRd -> Hit

- Ya tienes el dato
- No pasa nada

---

#### S + PrWr -> BusUpd -> S

- Escribes
- Generas **BusUpd**
- Todas las cachés actualizan el valor
- Te quedas en S

Analogía:
> “Editas y todos reciben el cambio en tiempo real”

---

#### M + PrRd / PrWr -> Hit

- Sigues siendo dueño
- Todo local

---

### Snooping (eventos del bus)

---

#### S + BusUpd -> actualizar dato

Otro core escribió.

- Recibes el nuevo valor
- Te mantienes en S

Analogía:
> “Alguien editó -> tu copia se actualiza automáticamente”

---

#### S + BusRd -> S

Otro core quiere leer.

- No pasa nada

---

#### M + BusRd -> Write-back -> S

Otro core quiere leer un dato que tú modificaste.

- Haces write-back
- Ahora se comparte
- Pasas a S

---

## Comparación directa

### MSI

- Usa **invalidaciones**
- Menos tráfico
- Más misses después

bueno cuando hay pocas escrituras compartidas

---

### Firefly

- Usa **actualizaciones (BusUpd)**
- Más tráfico
- Menos misses

bueno cuando hay alta compartición

---

## Cómo se ve esto en TU simulador

Cuando se implemente:

- `PrRd / PrWr` -> vienen del Core
- Cache decide:
  - Hit -> nada
  - Miss -> genera evento de bus

Luego:

- Bus hace broadcast
- Todas las caches hacen **snooping**
- Cada una decide si cambia estado

---

## 20. Concurrencia en SystemVerilog: uso de threads (fork-join)

### ¿A qué se refiere con threads?

En SystemVerilog, los *threads* son procesos que se ejecutan en paralelo dentro de la simulación.

Esto se logra con la construcción:

```systemverilog
fork
    // proceso 1
    // proceso 2
join
```

Esto permite modelar múltiples componentes funcionando al mismo tiempo.

---

### ¿Por qué es importante en este proyecto?

El sistema que se está modelando es inherentemente concurrente:

- 4 cores ejecutando instrucciones al mismo tiempo
- Cachés reaccionando a eventos del bus
- Bus arbitrando solicitudes
- Memoria atendiendo requests

Si todo se implementa de forma secuencial, el comportamiento no representa un sistema real.

Por eso es necesario usar threads: para modelar paralelismo realista.

---

### Tipos de fork-join

#### fork ... join

- Espera a que todos los procesos terminen

```systemverilog
fork
    task1();
    task2();
join
```

---

#### fork ... join_any

- Continúa cuando uno termina

```systemverilog
fork
    task1();
    task2();
join_any
```

---

#### fork ... join_none

- No espera, todos corren en background

```systemverilog
fork
    task1();
    task2();
join_none
```

Este es el más útil para simulaciones tipo hardware

---

### ¿Cómo se aplica en el proyecto?

Cada componente puede ejecutarse como un thread independiente:

#### Core

```text
loop:
    generar acceso (PrRd / PrWr)
    enviarlo al bus
```

#### Bus

```text
loop:
    recibir requests
    arbitrar
    broadcast
```

#### Cache

```text
loop:
    escuchar bus (snooping)
    reaccionar a eventos
```

#### Memory

```text
loop:
    atender requests
```

Todos estos loops deben correr en paralelo usando fork-join

---

### Analogía

Es como una oficina:

- Cada persona trabaja al mismo tiempo
- No esperan a que uno termine para actuar

Si todo fuera secuencial:

- primero trabaja Core0
- luego Core1
- luego el bus

eso no representa un sistema real

---

## 21. IPC en SystemVerilog: Mailboxes

### ¿Qué es IPC (Interprocess Communication)?

IPC significa:

👉 comunicación entre procesos (threads)

En este proyecto:

- Core, Cache, Bus y Memory son procesos independientes
- Necesitan comunicarse entre sí

---

### ¿Qué es una mailbox?

Una mailbox es un canal de comunicación entre threads.

Permite:

- Enviar mensajes
- Recibir mensajes
- Sincronizar procesos

---

### Operaciones básicas

#### Enviar (put)

```systemverilog
mailbox.put(msg);
```

#### Recibir (get)

```systemverilog
mailbox.get(msg);
```

---

### Propiedades importantes

- FIFO (primero en entrar, primero en salir)
- Bloqueante:

  - get() espera si no hay datos
  - put() puede esperar si está llena

Esto ayuda a sincronizar automáticamente

---

### ¿Cómo se aplica en el proyecto?

#### Core -> Bus

El core envía requests:

```text
PrRd(addr)
PrWr(addr)
```

usando mailbox

---

#### Bus -> Caches

El bus hace broadcast:

```text
BusRd
BusRdX
BusUpd
```

todas las caches reciben el mensaje

---

#### Bus -> Memory

El bus solicita datos:

```text
read(addr)
write(addr)
```

---

### Flujo completo

```text
Core -> (mailbox) -> Bus -> (broadcast) -> Caches
                            -> Memory
```

---

### ¿Por qué usar mailboxes?

Sin mailboxes:

- Se tendría que manejar señales manualmente
- Riesgo alto de errores de sincronización

Con mailboxes:

- Comunicación limpia
- Sincronización automática
- Código más modular

---

### Analogía

Mailbox = buzón de mensajes

- Core deja una carta
- Bus la recoge cuando puede
- No necesitan coordinarse directamente

---

### Relación con el proyecto

Esto permite:

- Desacoplar componentes
- Modelar latencias naturalmente
- Simular comportamiento asincrónico

---

## 22. Integración: threads + mailboxes

### Idea clave

El modelo completo funciona así:

- Cada componente corre en su propio thread
- Se comunican mediante mailboxes

---

### Ejemplo conceptual

```text
Thread Core:
    genera requests -> mailbox_core_bus

Thread Bus:
    recibe -> arbitra -> broadcast -> mailbox_bus_cache

Thread Cache:
    recibe broadcast -> actualiza estado

Thread Memory:
    responde requests
```

---

### Beneficio principal

Se logra un modelo:

- Concurrente
- Modular
- Cercano a hardware real

---

### Interpretación final

- fork-join -> define *quién corre en paralelo*
- mailboxes -> definen *cómo se comunican*

---
