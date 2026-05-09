import types_pkg::*;


/*
Memory module
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

module memory #(parameter N = 8, M = 32)
(input logic clk,
input logic we,
input logic [N-1:0] adr,
input logic [M-1:0] din,
output logic [M-1:0] dout);

logic [M-1:0] mem [2**N-1:0]; // Declaración de la memoria como un arreglo de palabras de M bits  

always_ff @(posedge clk) // Bloque secuencial que se ejecuta en el flanco positivo del reloj
if (we) mem [adr] <= din; // Si we es 1, se escribe el valor de din en la dirección especificada por adr
assign dout = mem[adr]; // Asignación continua que muestra el valor almacenado en la dirección especificada por adr en dout
endmodule