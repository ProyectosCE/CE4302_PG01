import types_pkg::*;


/*
Class Memory
Descripción:
Este modulo implementa una memoria de 256 palabras de 32 bits cada una. 
La memoria es de lectura y escritura, y se accede a ella mediante una dirección de 8 bits (para seleccionar una de las 256 palabras) 
y una señal de escritura (we) que indica si se va a escribir o leer. 
La salida (dout) muestra el valor almacenado en la dirección especificada por adr.


parametros:
    - N: Número de bits para la dirección (en este caso, 8 bits para 256 palabras)
    - M: Número de bits para los datos (en este caso, 32 bits)

Entradas:
- clk: Señal de reloj para sincronizar las operaciones de lectura y escritura.
- we: Señal de escritura que indica si se va a escribir (1) o leer (0).
- adr: Dirección de 8 bits para seleccionar una de las 256 palabras en la memoria
- din: Datos de entrada de 32 bits que se escribirán en la memoria si we es 1.
Salidas:
- dout: Datos de salida de 32 bits que muestran el valor almacenado en la dirección
    especificada por adr.

Restricciones:
- La memoria solo se puede escribir en el flanco positivo del reloj (posedge clk).
- Si we es 0, la memoria se lee y el valor en la dirección especificada por adr se asigna a dout.

Refencias:
- Solo añada las referencias que se han utilizado para escribir este código, no añada referencias que no se han utilizado.
- HDL Example 5.6 RAM, Harris and Harris, Digital Design and Computer Architecture, ARM Edition, 2016, Page 271
- Rincón de SystemVerilog Soporte para Verificación de Sistemas Digitales, https://dsd.webs.upv.es/?page_id=571
- Medium Memory Design in System Verilog, Jawad Ahmed Jan 22, 2025, https://medium.com/@jawadahmed2k3/simple-memory-design-in-system-verilog-ea0ea3c70a64

*/
/*
 * ============================================
 * NOTAS:
 *   - Se ha utilizado $realtime para medir el tiempo de simulación en la tarea run del core, ya que permite obtener
 */
class Memory;

    // Parámetros para la memoria
    parameter int N = 8;  // Número de bits para la dirección (256 palabras)
    parameter int M = 32; // Número de bits para los datos

    // Entradas
    logic clk;           // Señal de reloj
    logic we;            // Señal de escritura
    logic [N-1:0] adr;   // Dirección de la memoria
    logic [M-1:0] din;   // Datos de entrada

    // Salidas
    logic [M-1:0] dout;  // Datos de salida

    // Memoria interna: arreglo de 256 palabras de 32 bits
    logic [M-1:0] mem [0:(1<<N)-1];

    // Proceso de lectura/escritura sincronizado con el reloj
    always_ff @(posedge clk) begin
        if (we) begin
            mem[adr] <= din;  // Escribir en la memoria
        end else begin
            dout <= mem[adr]; // Leer de la memoria
        end
    end

endclass