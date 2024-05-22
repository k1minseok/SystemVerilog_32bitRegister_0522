`timescale 1ns / 1ps

module register (
    input        clk,
    input        reset,
    input [31:0] D,

    output [31:0] Q
);

    reg [31:0] Q_reg;
    // reg [31:0] Q_next;


    assign Q = Q_reg;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            Q_reg <= 0;
        end else begin
            Q_reg <= D;
        end
    end

    // always @(*) begin
    //     Q_next = D;
    // end

endmodule
